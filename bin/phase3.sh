#!/usr/bin/env bash
# Phase 3 : outils de base + mises à jour de sécurité automatiques + diagnostic Ethernet
# Usage : sudo bash ~/homelab/phase3.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Lancer avec sudo"; exit 1; }

LOGDIR=/home/alex/homelab/logs
mkdir -p "$LOGDIR"

echo "== Diagnostic Ethernet (lecture seule) =="
journalctl -k -b --no-pager > "$LOGDIR/kernel-boot.log"
grep -iE 'usb|r815|enx|cdc' "$LOGDIR/kernel-boot.log" > "$LOGDIR/kernel-usb-net.log" || true
journalctl -b -u NetworkManager --no-pager > "$LOGDIR/networkmanager.log"
chown -R alex:alex "$LOGDIR"

echo "== Mises à jour =="
apt-get update
apt-get full-upgrade -y

echo "== Outils de base =="
apt-get install -y git vim htop btop tmux rsync jq tree ncdu bind9-dnsutils net-tools \
  ca-certificates gnupg unattended-upgrades apt-listchanges

echo "== Mises à jour de sécurité automatiques =="
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== Nettoyage =="
apt-get autoremove -y
apt-get clean

echo "== Terminé =="
