#!/usr/bin/env bash
# Prépare l'interface de sauvegarde (bouton, historique, journaux). À lancer par Alex, AVEC sudo :
#   sudo bash installer-sauvegarde-ui.sh
# Ne lance aucune sauvegarde.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Lance ce script avec sudo."; exit 1; }
U="${SUDO_USER:?lance-le avec sudo depuis ton utilisateur}"
H="$(getent passwd "$U" | cut -d: -f6)"
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="$H/homelab/caddy/pages/admin/sauvegardes.json"
DATA=/var/lib/homelab-backup
MARQ="$H/.config/homelab/sauvegarde-manuelle"

[ -x /usr/local/sbin/restic-homelab ] || { echo "/usr/local/sbin/restic-homelab introuvable : fais d'abord la phase 17."; exit 1; }
systemctl cat homelab-backup.service >/dev/null || { echo "homelab-backup.service introuvable."; exit 1; }

install -m 755 -o root -g root "$SRC/historique-sauvegardes.py" /usr/local/sbin/homelab-backup-historique
install -m 755 -o root -g root "$SRC/suivi-sauvegardes.py" /usr/local/sbin/homelab-backup-suivi
install -d -m 755 "$DATA"
install -d -m 700 -o "$U" -g "$U" "$H/.config/homelab"

# droits minimaux : lancer ce service précis et lire son journal, rien d'autre
TMP="$(mktemp)"
cat > "$TMP" <<SUDO
$U ALL=(root) NOPASSWD: /usr/bin/systemctl start --no-block homelab-backup.service
$U ALL=(root) NOPASSWD: /usr/bin/journalctl -u homelab-backup.service -n 150 --no-pager -o short-iso
SUDO
visudo -cf "$TMP" >/dev/null
install -m 440 -o root -g root "$TMP" /etc/sudoers.d/homelab-backup
rm -f "$TMP"

# après CHAQUE exécution (réussie ou ratée), enregistre le résultat et le journal.
# ExecStopPost s'exécute même quand le script a échoué ; le « - » évite de changer le résultat du service.
mkdir -p /etc/systemd/system/homelab-backup.service.d
cat > /etc/systemd/system/homelab-backup.service.d/historique.conf <<CONF
[Service]
ExecStartPost=
ExecStopPost=
ExecStopPost=-/usr/local/sbin/homelab-backup-suivi $DATA $MARQ /usr/local/sbin/homelab-backup-historique $OUT
CONF
systemctl daemon-reload

# premier remplissage de la liste des instantanés (lecture seule, s'arrête après 90 s si la tour est éteinte)
timeout 90 /usr/local/sbin/homelab-backup-historique "$OUT" && echo "Instantanés écrits dans $OUT" \
  || echo "Instantanés non remplis (tour éteinte ?) : ils se rempliront après la prochaine sauvegarde réussie."

echo "Terminé. Aucune sauvegarde n'a été lancée."
