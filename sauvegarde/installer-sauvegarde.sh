#!/usr/bin/env bash
# Phase 17.2 à 17.5 (sans aucun mot de passe) : point de montage, fstab, scripts, timer du samedi.
# Usage : sudo bash ~/homelab/sauvegarde/installer-sauvegarde.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Lancer avec sudo"; exit 1; }
D=/home/alex/homelab/sauvegarde

mkdir -p /mnt/tour-backup
LIGNE='//192.168.1.198/Sauvegardes-homelab /mnt/tour-backup cifs credentials=/root/.smb-tour,vers=3.0,uid=0,gid=0,file_mode=0600,dir_mode=0700,_netdev,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120,x-systemd.mount-timeout=30 0 0'
if ! grep -q '/mnt/tour-backup' /etc/fstab; then
  cp /etc/fstab /etc/fstab.bak-avant-sauvegarde
  echo "$LIGNE" >> /etc/fstab
fi

cat > /usr/local/sbin/restic-homelab <<'W'
#!/bin/bash
exec restic -r /mnt/tour-backup/restic --password-file /root/.restic-pass "$@"
W
chmod 700 /usr/local/sbin/restic-homelab
install -m 700 -o root -g root "$D/homelab-backup.sh" /usr/local/sbin/homelab-backup.sh

cat > /etc/systemd/system/homelab-backup.service <<'U'
[Unit]
Description=Sauvegarde hebdomadaire du homelab vers la tour
After=network-online.target

[Service]
Type=oneshot
# Sans HOME, restic ne peut pas ouvrir son cache ("neither XDG_CACHE_HOME nor HOME are defined")
Environment=HOME=/root
ExecStart=/usr/local/sbin/homelab-backup.sh
Nice=10
IOSchedulingClass=idle
U
cat > /etc/systemd/system/homelab-backup.timer <<'U'
[Unit]
Description=Sauvegarde du homelab le samedi

[Timer]
OnCalendar=Sat *-*-* 17,19,21:00:00
Persistent=true

[Install]
WantedBy=timers.target
U
systemctl daemon-reload
# Sans ce start, l'automontage n'est actif qu'après un redémarrage, et /mnt/tour-backup reste un dossier local
systemctl start 'mnt-tour\x2dbackup.automount'
systemctl enable --now homelab-backup.timer
grep tour-backup /etc/fstab
systemctl list-timers homelab-backup.timer --no-pager
echo "OK. Reste : /root/.smb-tour (identifiants), /root/.restic-pass (mot de passe de chiffrement), puis 'sudo restic-homelab init'."
