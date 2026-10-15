#!/usr/bin/env bash
# Recharge Caddy SANS risque : vérifie que le conteneur voit bien le Caddyfile, valide, recharge, teste,
# et remet la dernière version qui marchait si un test échoue.
# Usage : bash recharger-caddy-sur.sh   (sans sudo, depuis ton utilisateur)
set -uo pipefail
CF="${CADDYFILE:-$HOME/homelab/caddy/Caddyfile}"
CT="${CADDY_CONTAINER:-caddy}"
SAUV="$CF.avant-$(date +%Y%m%d-%H%M%S)"
BON="$CF.dernier-bon"   # dernière version qui a passé les tests : c'est elle qu'on remet en cas d'échec
cp -a "$CF" "$SAUV" || { echo "Impossible de sauvegarder $CF"; exit 1; }
[ -f "$BON" ] || { cp -a "$CF" "$BON"; echo "Premier lancement : version de référence créée ($BON)."; }
ntfy() { curl -s -m 5 -d "$1" http://127.0.0.1:8089/homelab >/dev/null 2>&1 || true; }

# 1) Le conteneur voit-il le même fichier que moi ? (un fichier remplacé par un éditeur change d'inode et le conteneur garde l'ancien)
local_sum="$(sha256sum "$CF" | cut -d' ' -f1)"
cont_sum="$(docker exec "$CT" sha256sum /etc/caddy/Caddyfile 2>/dev/null | cut -d' ' -f1)"
if [ "$local_sum" != "$cont_sum" ]; then
  echo "ARRÊT : le conteneur '$CT' ne voit pas le Caddyfile actuel (le fichier a été remplacé). Un rechargement n'appliquerait rien."
  echo "Il faut redémarrer ou recréer le conteneur (chez toi) : rien n'a été rechargé."
  exit 1
fi

# 2) Validation puis rechargement
docker exec "$CT" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || {
  echo "Caddyfile invalide : rien n'a été rechargé. Ancienne version : $SAUV"; exit 1; }
echec=0
docker exec "$CT" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || { echo "Rechargement refusé."; echec=1; }
sleep 3

# 3) Tests
for h in home.lan admin.lan films.lan; do
  c="$(curl -s -o /dev/null -m 8 -w '%{http_code}' -H "Host: $h" http://127.0.0.1/)"
  case "$c" in 200|301|302|307|308|401) echo "ok  $h ($c)";; *) echo "ÉCHEC $h ($c)"; echec=1;; esac
done

if [ "$echec" -ne 0 ]; then
  cat "$BON" > "$CF"   # réécrit EN PLACE (même inode) pour que le conteneur voie le retour arrière
  docker exec "$CT" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1
  ntfy "Caddy : la modification a échoué, dernière version qui marchait remise ($BON)."
  echo "Retour à la dernière version qui marchait effectué."; exit 1
fi
cat "$CF" > "$BON"
echo "Caddy rechargé, tests réussis. Version de référence mise à jour : $BON"
