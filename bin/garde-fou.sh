#!/usr/bin/env bash
# Garde-fou : relance les conteneurs arrêtés ou « unhealthy ».
# Lancé toutes les 2 min par garde-fou.timer (systemd --user). Voir CHANGELOG.md.
# Usage : garde-fou.sh [--dry-run]
#
# Règles :
#  - ignore les conteneurs dont la politique de redémarrage est "no" (ollama, open-webui)
#    et ceux listés dans garde-fou.ignorer (un nom par ligne, pour une maintenance) ;
#  - ignore aussi les conteneurs des services éteints par l'interrupteur de l'admin
#    (~/.config/homelab/conteneurs-eteints, écrit par caddy/api.py) ;
#  - exited/dead -> docker start ; unhealthy -> docker restart ; puis message ntfy ;
#  - au plus 3 relances par conteneur et par heure, ensuite un seul message « ne tient pas » par heure ;
#  - caddy et adguard : jamais relancés, seulement une alerte (au plus une par heure) ;
#  - ne touche jamais au démon Docker ;
#  - une ligne dans garde-fou.log par action, fichier limité à 500 lignes.
set -u

: "${GARDE_FOU_DOSSIER:=$HOME/homelab}"
: "${GARDE_FOU_NTFY:=http://127.0.0.1:8089/homelab}"
JOURNAL="$GARDE_FOU_DOSSIER/garde-fou.log"
ETAT="$GARDE_FOU_DOSSIER/garde-fou.etat"      # <epoch> <nom> <relance|abandon|alerte>
IGNORER="$GARDE_FOU_DOSSIER/garde-fou.ignorer"
: "${GARDE_FOU_ETEINTS:=$HOME/.config/homelab/conteneurs-eteints}"   # éteints par l'interrupteur de l'admin
INTOUCHABLES=" caddy adguard "
MAX_RELANCES=3
FENETRE=3600
LIGNES_MAX=500

A_SEC=0
case "${1:-}" in
    --dry-run) A_SEC=1 ;;
    "") ;;
    *) echo "usage : $0 [--dry-run]" >&2; exit 2 ;;
esac

# Un seul garde-fou à la fois.
exec 9>"$GARDE_FOU_DOSSIER/.garde-fou.lock"
flock -n 9 || exit 0

MAINTENANT=$(date +%s)

journal() {
    if [ "$A_SEC" = 1 ]; then
        echo "[à sec] $*"
        return
    fi
    echo "$(date '+%F %T') $*" >> "$JOURNAL"
    if [ "$(wc -l < "$JOURNAL")" -gt "$LIGNES_MAX" ]; then
        tail -n "$LIGNES_MAX" "$JOURNAL" > "$JOURNAL.tmp" && cat "$JOURNAL.tmp" > "$JOURNAL"
        rm -f "$JOURNAL.tmp"
    fi
}

notifier() {
    if [ "$A_SEC" = 1 ]; then
        echo "[à sec] message ntfy : $1"
        return
    fi
    curl -fsS --max-time 5 -d "$1" "$GARDE_FOU_NTFY" > /dev/null 2>&1 \
        || journal "ntfy injoignable, message perdu : $1"
}

# compter <nom> <action> : nombre d'entrées dans la dernière heure
compter() {
    [ -f "$ETAT" ] || { echo 0; return; }
    awk -v n="$1" -v a="$2" -v lim=$((MAINTENANT - FENETRE)) \
        '$1 >= lim && $2 == n && $3 == a { c++ } END { print c + 0 }' "$ETAT"
}

noter() {
    [ "$A_SEC" = 1 ] && return
    echo "$MAINTENANT $1 $2" >> "$ETAT"
}

# Oublier ce qui a plus d'une heure.
if [ "$A_SEC" = 0 ] && [ -f "$ETAT" ]; then
    awk -v lim=$((MAINTENANT - FENETRE)) '$1 >= lim' "$ETAT" > "$ETAT.tmp" && mv "$ETAT.tmp" "$ETAT"
fi

# Docker injoignable : on prévient (une fois par heure) et on s'arrête, sans toucher au démon.
if ! ids=$(docker ps -aq 2>&1); then
    if [ "$(compter docker alerte)" -lt 1 ]; then
        journal "docker ne répond pas : $ids"
        notifier "Garde-fou : Docker ne répond pas, intervention nécessaire"
        noter docker alerte
    fi
    exit 1
fi
[ -n "$ids" ] || { [ "$A_SEC" = 1 ] && echo "[à sec] aucun conteneur"; exit 0; }

surveilles=0
ignores=""
a_faire=0

while IFS='|' read -r nom politique etat sante; do
    nom=${nom#/}
    if [ -z "$politique" ] || [ "$politique" = "no" ]; then
        ignores="$ignores $nom"
        continue
    fi
    if [ -f "$IGNORER" ] && grep -qxF "$nom" "$IGNORER"; then
        ignores="$ignores $nom(fichier)"
        continue
    fi
    if [ -f "$GARDE_FOU_ETEINTS" ] && grep -qxF "$nom" "$GARDE_FOU_ETEINTS"; then
        ignores="$ignores $nom(éteint)"
        continue
    fi
    surveilles=$((surveilles + 1))

    case "$etat/$sante" in
        exited/*|dead/*)   probleme="arrêté ($etat)"; commande=start ;;
        running/unhealthy) probleme="unhealthy";      commande=restart ;;
        *) continue ;;   # running, restarting (Docker s'en occupe), created, paused...
    esac
    a_faire=$((a_faire + 1))

    if [[ "$INTOUCHABLES" == *" $nom "* ]]; then
        if [ "$(compter "$nom" alerte)" -lt 1 ]; then
            journal "$nom $probleme : alerte seulement (jamais relancé automatiquement)"
            notifier "Garde-fou : $nom $probleme, intervention nécessaire (pas de relance automatique)"
            noter "$nom" alerte
        fi
        continue
    fi

    if [ "$(compter "$nom" relance)" -ge "$MAX_RELANCES" ]; then
        if [ "$(compter "$nom" abandon)" -lt 1 ]; then
            journal "$nom $probleme : déjà $MAX_RELANCES relances dans l'heure, abandon"
            notifier "Garde-fou : $nom ne tient pas, intervention nécessaire"
            noter "$nom" abandon
        fi
        continue
    fi

    if [ "$A_SEC" = 1 ]; then
        journal "$nom $probleme : ferait docker $commande $nom"
        notifier "Garde-fou : $nom relancé"
        continue
    fi

    noter "$nom" relance
    if sortie=$(docker "$commande" "$nom" 2>&1); then
        journal "$nom $probleme : docker $commande OK"
        notifier "Garde-fou : $nom relancé"
    else
        journal "$nom $probleme : docker $commande a échoué : $sortie"
    fi
done < <(docker inspect -f '{{.Name}}|{{.HostConfig.RestartPolicy.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}' $ids)

if [ "$A_SEC" = 1 ]; then
    echo "[à sec] $surveilles conteneurs surveillés, $a_faire à traiter"
    echo "[à sec] ignorés :${ignores:- aucun}"
fi
