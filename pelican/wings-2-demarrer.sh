#!/usr/bin/env bash
# Phase 14.2 (2/2) : à lancer APRÈS la commande 'sudo wings configure ...' du panel.
# Vérifie le port d'API, crée le réseau Docker de Wings sur 10.250.0.0/16
# (la plage par défaut 172.18.0.0/16 est déjà prise par AdGuard), puis démarre Wings.
# Usage : sudo bash ~/homelab/pelican/wings-2-demarrer.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Lancer avec sudo"; exit 1; }
CFG=/etc/pelican/config.yml
[ -f "$CFG" ] || { echo "$CFG absent : lance d'abord la commande 'wings configure' du panel"; exit 1; }

echo "== Port d'API (doit être 8081) et SFTP (doit être 2022)"
awk '/^api:/{a=1} a&&/^  port:/{print "api.port =", $2; a=0}' "$CFG"
grep -E '^\s+bind_port:' "$CFG" | head -1 | sed 's/^ */sftp./'
grep -E '^remote:' "$CFG"

echo "== Réseau Docker de Wings"
if ! docker network inspect pelican_nw >/dev/null 2>&1; then
  docker network create --driver bridge --subnet 10.250.0.0/16 --gateway 10.250.0.1 \
    -o com.docker.network.bridge.name=pelican0 pelican_nw
fi
docker network inspect -f '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}' pelican_nw

echo "== Démarrage de Wings"
systemctl enable --now wings
sleep 8
# Wings complète config.yml avec ses valeurs par défaut au premier démarrage : on aligne le réseau.
if grep -q '172\.18\.0\.' "$CFG"; then
  sed -i 's|172\.18\.0\.0/16|10.250.0.0/16|; s|172\.18\.0\.1|10.250.0.1|g' "$CFG"
  systemctl restart wings
  sleep 5
fi
systemctl status wings --no-pager | head -8
journalctl -u wings -n 15 --no-pager | grep -iE 'error|fatal|listening|configured|started' || true
