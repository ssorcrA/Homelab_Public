#!/usr/bin/env bash
# Définit le mot de passe admin Caddy (Dozzle, Scrutiny, page admin) puis (re)démarre Caddy.
# Usage : bash ~/homelab/caddy/set-admin-password.sh
set -euo pipefail
cd "$(dirname "$0")"
read -s -p "Mot de passe admin (Dozzle, Scrutiny, page admin) : " ADMINPW; echo
read -s -p "Confirme : " ADMINPW2; echo
[ "$ADMINPW" = "$ADMINPW2" ] || { echo "Les mots de passe ne correspondent pas."; exit 1; }
HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "$ADMINPW")
unset ADMINPW ADMINPW2
sed -i "s|^        admin .*|        admin $HASH|" Caddyfile
docker compose up -d
sleep 2
docker exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
docker compose logs --tail 10
echo "OK : utilisateur 'admin', mot de passe enregistré (haché) dans le Caddyfile."
