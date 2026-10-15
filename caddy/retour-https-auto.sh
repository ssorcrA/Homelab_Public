#!/usr/bin/env bash
# Retour en arrière du « https automatique » (plan du 14/10/2026, voir ~/pack-maison/A-FAIRE-DEMAIN.md).
#
#   bash ~/homelab/caddy/retour-https-auto.sh             remet tout comme avant
#   bash ~/homelab/caddy/retour-https-auto.sh --verifier  ne change RIEN : vérifie les copies et valide le Caddyfile de retour
#
# Ce que fait le retour :
#   1. remet la page home d'avant (pages + pack) et la page certificat d'avant (pages + pack), retire sonde-https.png ;
#   2. remet le Caddyfile d'avant, EN PLACE (même inode, le conteneur le voit), avec en plus
#      « Strict-Transport-Security: max-age=0 » sur les sites .lan en https : les navigateurs qui avaient
#      reçu HSTS l'oublient à leur prochaine visite (au lieu d'attendre jusqu'à 1 jour) ;
#   3. recharge Caddy avec recharger-caddy-sur.sh (validation, tests, et retour à la dernière version qui marchait si échec).
# Un jour après, on peut retirer le bloc « hsts_effacer » (ou remettre Caddyfile.avant-https-auto tel quel).
# Ne touche ni aux ports, ni à ufw, ni à SSH, ni aux certificats.
set -uo pipefail

CADDY="$HOME/homelab/caddy"
PACK="$HOME/pack-maison/pages-maison"
CF="$CADDY/Caddyfile"
AV="$CF.avant-https-auto"
RECHARGER="$HOME/pack-maison/pages-maison/recharger-caddy-sur.sh"
COPIES=(
  "$CADDY/pages/home/index.html.avant-https-auto:$CADDY/pages/home/index.html"
  "$PACK/home/index.html.avant-https-auto:$PACK/home/index.html"
  "$CADDY/pages/home/certificat.html.avant-https-auto:$CADDY/pages/home/certificat.html"
  "$PACK/home/certificat.html.avant-https-auto:$PACK/home/certificat.html"
)
VERIF=0; [ "${1:-}" = "--verifier" ] && VERIF=1

# Caddyfile de retour = Caddyfile d'avant + HSTS max-age=0 sur chaque site qui importe https_mes_appareils
# (tous les .lan sauf cloud.lan ; les alias DuckDNS sont écartés par le filtre « host *.lan »).
fabriquer_retour() {  # $1 = source, sortie sur stdout
  python3 -I - "$1" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
bloc = """
# --- Retour en arrière du https automatique : fait oublier HSTS aux navigateurs (à retirer un jour après) ---
(hsts_effacer) {
    @hsts_effacer {
        protocol https
        host *.lan
    }
    header @hsts_effacer Strict-Transport-Security "max-age=0"
}
"""
ligne = "    import https_mes_appareils\n"
n = s.count(ligne)
if n == 0 or "(https_mes_appareils)" not in s:
    sys.exit("Caddyfile inattendu : aucun « import https_mes_appareils » trouvé")
s = s.replace(ligne, ligne + "    import hsts_effacer\n")
i = s.index("# --- Famille ---") if "# --- Famille ---" in s else len(s)
s = s[:i] + bloc.lstrip("\n") + "\n" + s[i:]
sys.stdout.write(s)
sys.stderr.write("%d sites reçoivent max-age=0\n" % n)
PY
}

valider() {  # $1 = fichier dans $CADDY (le conteneur voit ce dossier en /etc/caddy)
  docker exec caddy caddy validate --adapter caddyfile --config "/etc/caddy/$(basename "$1")" >/dev/null 2>&1
}

manque=0
[ -f "$AV" ] && echo "ok      $AV" || { echo "MANQUE  $AV"; manque=1; }
for c in "${COPIES[@]}"; do
  src="${c%%:*}"; [ -f "$src" ] && echo "ok      $src" || { echo "MANQUE  $src"; manque=1; }
done

if [ "$VERIF" -eq 1 ]; then
  base="$AV"; [ -f "$base" ] || { base="$CF"; echo "(simulation sur le Caddyfile actuel, la copie .avant-https-auto n'existe pas encore)"; }
  tmp="$CADDY/.verif-retour-https-auto.Caddyfile"
  if fabriquer_retour "$base" > "$tmp" && valider "$tmp"; then echo "Caddyfile de retour : valide"; else echo "Caddyfile de retour : INVALIDE"; fi
  rm -f "$tmp"
  echo "Vérification seulement : rien n'a été modifié."
  exit 0
fi

[ "$manque" -eq 0 ] || { echo "ARRÊT : il manque des copies, rien n'a été modifié."; exit 1; }

# Caddyfile d'abord (préparé et validé avant d'écrire quoi que ce soit)
tmp="$CADDY/.retour-https-auto.Caddyfile"
fabriquer_retour "$AV" > "$tmp" || { rm -f "$tmp"; echo "ARRÊT : impossible de préparer le Caddyfile de retour."; exit 1; }
valider "$tmp" || { rm -f "$tmp"; echo "ARRÊT : le Caddyfile de retour est invalide, rien n'a été modifié."; exit 1; }
cp -a "$CF" "$CF.avant-retour-$(date +%Y%m%d-%H%M%S)"
cat "$tmp" > "$CF"; rm -f "$tmp"                       # réécriture en place : même inode

for c in "${COPIES[@]}"; do cp -a "${c%%:*}" "${c#*:}"; done
rm -f "$CADDY/pages/home/sonde-https.png" "$PACK/home/sonde-https.png"
echo "Pages home et certificat d'avant remises (pages + pack), sonde retirée."

bash "$RECHARGER"
