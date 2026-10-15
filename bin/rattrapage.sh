#!/usr/bin/env bash
# Rattrapage phases 3-4 du guide (veille, zram, paquets, DNS du portable)
# Usage : sudo bash ~/homelab/rattrapage.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Lancer avec sudo"; exit 1; }

echo "== 1. Paquets manquants =="
DEBIAN_FRONTEND=noninteractive apt-get install -y restic cifs-utils systemd-zram-generator vainfo

echo "== 2. Plus de veille =="
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/; s/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf

echo "== 3. zram =="
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service

echo "== 4. DNS fixe du portable =="
nmcli con mod "Freebox-220D19" ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1 9.9.9.9"
nmcli con mod "Wired connection 1" ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1 9.9.9.9"
nmcli device reapply wlp1s0

echo "== 5. Tailscale ne gère plus le DNS du portable =="
tailscale set --accept-dns=false

echo "== Terminé =="
