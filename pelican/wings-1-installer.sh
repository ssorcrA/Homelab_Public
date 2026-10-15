#!/usr/bin/env bash
# Phase 14.2 (1/2) : installe Wings et son service systemd (sans le démarrer).
# Usage : sudo bash ~/homelab/pelican/wings-1-installer.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Lancer avec sudo"; exit 1; }

mkdir -p /etc/pelican /var/run/wings /var/lib/pelican
curl -fL -o /usr/local/bin/wings "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_amd64"
chmod u+x /usr/local/bin/wings
sudo /usr/local/bin/wings version || echo "Avertissement : impossible d'afficher la version de Wings (on continue)"

cat > /etc/systemd/system/wings.service <<'UNIT'
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
echo "OK : Wings installé. Prochaine étape : créer le nœud dans le panel puis lancer la commande 'wings configure'."
