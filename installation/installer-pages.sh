#!/usr/bin/env bash
# Installe les pages home.lan / admin.lan (v2), le service homelab-api et le mode d'emploi.
# À lancer depuis le dossier pages-maison, SANS sudo :  bash installer-pages.sh
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "Lance ce script avec ton utilisateur, pas avec sudo."; exit 1; }

SRC="$(cd "$(dirname "$0")" && pwd)"
CADDY="$HOME/homelab/caddy"
PAGES="$CADDY/pages"
DATE="$(date +%Y%m%d-%H%M%S)"

[ -d "$CADDY" ] || { echo "Dossier $CADDY introuvable."; exit 1; }
for f in home/index.html home/guide.html home/certificat.html admin/index.html api.py fonts/bricolage-latin.woff2 fonts/bricolage-latin-ext.woff2; do
  [ -f "$SRC/$f" ] || { echo "Fichier manquant : $SRC/$f"; exit 1; }
done
command -v python3 >/dev/null || { echo "python3 est nécessaire (sudo apt install python3)."; exit 1; }

if [ -d "$PAGES" ]; then
  cp -a "$PAGES" "$CADDY/pages-ancien-$DATE"
  echo "Anciennes pages sauvegardées dans $CADDY/pages-ancien-$DATE"
fi

mkdir -p "$PAGES/home" "$PAGES/admin" "$PAGES/home/fonts" "$PAGES/admin/fonts" "$HOME/.config/homelab"
install -m 644 "$SRC/home/index.html"       "$PAGES/home/index.html"
install -m 644 "$SRC/home/guide.html"       "$PAGES/home/guide.html"
install -m 644 "$SRC/home/certificat.html"  "$PAGES/home/certificat.html"
install -m 644 "$SRC/admin/index.html"      "$PAGES/admin/index.html"
# polices du design : servies en /fonts/ sur home.lan et admin.lan (chaque site a son propre dossier dans Caddy)
for d in home admin; do
  install -m 644 "$SRC/fonts/bricolage-latin.woff2"     "$PAGES/$d/fonts/bricolage-latin.woff2"
  install -m 644 "$SRC/fonts/bricolage-latin-ext.woff2" "$PAGES/$d/fonts/bricolage-latin-ext.woff2"
done
chmod 755 "$PAGES" "$PAGES/home" "$PAGES/admin" "$PAGES/home/fonts" "$PAGES/admin/fonts"

install -m 755 "$SRC/api.py" "$CADDY/api.py"
install -m 755 "$SRC/historique-sauvegardes.py" "$CADDY/historique-sauvegardes.py"
[ -f "$HOME/.config/homelab/appareils.json" ] || echo '[]' > "$HOME/.config/homelab/appareils.json"

UNITS="$HOME/.config/systemd/user"
mkdir -p "$UNITS"

# l'ancien contrôle d'état (v1) est remplacé par le service homelab-api
if systemctl --user list-unit-files homelab-etat.timer >/dev/null 2>&1; then
  systemctl --user disable --now homelab-etat.timer 2>/dev/null || true
  rm -f "$UNITS/homelab-etat.timer" "$UNITS/homelab-etat.service" "$CADDY/etat.sh"
fi

cat > "$UNITS/homelab-api.service" <<UNIT
[Unit]
Description=Service local du homelab (état, appareils, sauvegarde)
After=network-online.target

[Service]
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 $CADDY/api.py
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable homelab-api.service
systemctl --user restart homelab-api.service
loginctl enable-linger "$USER" 2>/dev/null || echo "Note : lance 'sudo loginctl enable-linger $USER' pour que le service démarre après un redémarrage."

sleep 4
echo
echo "Service :"; systemctl --user is-active homelab-api.service
echo "etat.json :"; head -c 400 "$PAGES/home/etat.json" 2>/dev/null || echo "pas encore écrit"
echo
echo
echo "Fait. Ouvre http://home.lan et http://admin.lan (Ctrl+F5 pour vider le cache)."
echo "Pour les mesures, le bouton de sauvegarde et les appareils, il reste la route Caddy /api (phase 20 du guide)."
