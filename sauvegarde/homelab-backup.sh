#!/bin/bash
# Sauvegarde hebdomadaire du homelab vers la tour (guide phase 17.4)
# Écarts avec le guide : tour testée sur le port SMB 445 (le pare-feu Windows bloque le ping),
# umask 077 pour que les exports de bases ne soient lisibles que par root.
set -uo pipefail
umask 077
H=/home/alex
TOUR=192.168.1.198
STAMP=/var/lib/homelab-backup/last-ok
STATUT=/var/lib/homelab-backup/dernier-statut     # ok, echec ou ignoree : lu par homelab-backup-suivi
MARQ=$H/.config/homelab/sauvegarde-manuelle      # écrit par homelab-api quand on clique sur « Sauvegarder maintenant »
NTFY=http://127.0.0.1:8089/homelab
mkdir -p /var/lib/homelab-backup "$H/homelab/dumps"
notify() { echo "$1"; curl -s -H "Title: Sauvegarde homelab" -d "$1" "$NTFY" >/dev/null || true; }   # le message va aussi dans le journal
statut() { echo "$1" > "$STATUT"; }
statut echec   # par défaut : toute sortie imprévue compte comme un échec

# Lancée à la main depuis admin.lan il y a moins de 5 min : on la fait, même si une sauvegarde récente existe
manuel=0
if [ -f "$MARQ" ] && [ $(( $(date +%s) - $(stat -c %Y "$MARQ") )) -lt 300 ]; then manuel=1; echo "Lancée à la main depuis admin.lan."; fi

# Déjà réussie depuis moins de 20 h (essais de 19 h et 21 h après une réussite à 17 h) : rien à faire
if [ "$manuel" -eq 0 ] && [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt 72000 ]; then
  echo "Sauvegarde déjà réussie le $(date -d "@$(stat -c %Y "$STAMP")" '+%d/%m à %H:%M') : rien à faire."
  statut ignoree; exit 0
fi

# La tour et son partage sont-ils disponibles ?
if ! timeout 5 bash -c "</dev/tcp/$TOUR/445" 2>/dev/null; then notify "Tour éteinte ou partage fermé : sauvegarde reportée"; exit 1; fi
timeout 30 ls /mnt/tour-backup >/dev/null 2>&1
if ! mountpoint -q /mnt/tour-backup; then notify "Partage de la tour indisponible : sauvegarde échouée"; exit 1; fi

# Exports cohérents des bases de données
docker exec nextcloud-db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction' > "$H/homelab/dumps/nextcloud.sql" 2>/dev/null \
  || notify "Échec du dump Nextcloud"
docker exec paperless document_exporter ../export >/dev/null 2>&1 \
  || notify "Échec de l'export Paperless"

restic-homelab backup --exclude-caches \
  --exclude "$H/homelab/immich/postgres" \
  --exclude "$H/homelab/immich/library/thumbs" \
  --exclude "$H/homelab/immich/library/encoded-video" \
  --exclude "$H/homelab/nextcloud/db" \
  --exclude "$H/homelab/ia" \
  --exclude "$H/homelab/jellyfin/cache" \
  --exclude "$H/homelab/pelican/logs" \
  "$H/homelab" "$H/media" /etc/pelican /etc/fstab /etc/docker   # ~/media entier (avant : seulement ~/media/musique)
rc=$?

if [ $rc -ne 0 ] && [ $rc -ne 3 ]; then notify "Sauvegarde échouée (code $rc)"; exit 1; fi

restic-homelab forget --keep-weekly 8 --keep-monthly 6 --prune >/dev/null 2>&1
restic-homelab check >/dev/null 2>&1 || { notify "La vérification du dépôt a échoué"; exit 1; }
touch "$STAMP"
statut ok
notify "Sauvegarde terminée avec succès"
