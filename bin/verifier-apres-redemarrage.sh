#!/usr/bin/env bash
# Vérification après redémarrage du portable (14/10/2026). Lecture seule : ne modifie rien, ne lance aucune sauvegarde.
#   bash ~/homelab/bin/verifier-apres-redemarrage.sh
# Attendre 2-3 minutes après le démarrage (Docker et Caddy mettent un moment à tout relancer).
set -u
ok=0; ko=0
t(){ if eval "$2" >/dev/null 2>&1; then printf 'ok    %s\n' "$1"; ok=$((ok+1)); else printf 'ÉCHEC %s\n' "$1"; ko=$((ko+1)); fi; }
code(){ curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "$1"; }

echo "== Système"
for s in docker ufw crowdsec crowdsec-firewall-bouncer tailscaled; do t "service $s" "systemctl is-active --quiet $s"; done
t "règles ufw activées (ufw.conf)" "grep -q ^ENABLED=yes /etc/ufw/ufw.conf"
t "service utilisateur homelab-api" "systemctl --user is-active --quiet homelab-api"
t "timer duckdns-maj" "systemctl --user is-active --quiet duckdns-maj.timer"
t "timer homelab-backup" "systemctl is-active --quiet homelab-backup.timer"

echo "== Conteneurs (Open WebUI « ia » démarre à la demande : pas vérifié)"
ATTENDUS="adguard beszel beszel-agent caddy diun dozzle fichiers homeassistant immich_machine_learning immich_postgres immich_redis immich_server jellyfin kuma metube navidrome nextcloud nextcloud-cron nextcloud-db nextcloud-redis ntfy paperless paperless-broker pelican-panel portainer scrutiny stirling"
EN_ROUTE=" $(docker ps --format '{{.Names}}' | tr '\n' ' ') "
for c in $ATTENDUS; do t "conteneur $c" "[[ \"$EN_ROUTE\" == *\" $c \"* ]]"; done

echo "== Caddy et pages"
t "http://home.lan → 200"            "[ \"\$(code http://home.lan)\" = 200 ]"
t "http://admin.lan → 401"           "[ \"\$(code http://admin.lan)\" = 401 ]"
t "https://films.lan avec HSTS"      "curl -skI --max-time 8 https://films.lan | grep -qi '^strict-transport-security: max-age=86400'"
t "https://cloud.lan sans HSTS"      "! curl -skI --max-time 8 https://cloud.lan | grep -qi '^strict-transport-security'"
t "sonde https → 200"                "[ \"\$(code https://home.lan/sonde-https.png)\" = 200 ]"
t "fichiers.lan (File Browser)"      "[ \"\$(code https://fichiers.lan)\" = 200 ]"
t "home.exemple.duckdns.org"     "[ \"\$(code http://home.exemple.duckdns.org)\" = 200 ]"
t "état des services à jour (< 2 min)" "[ \$(( \$(date +%s) - \$(stat -c %Y ~/homelab/caddy/pages/home/etat.json) )) -lt 120 ]"

echo "== Jellyfin"
t "Jellyfin en bonne santé"          "[ \"\$(curl -s --max-time 8 http://127.0.0.1:8096/health)\" = Healthy ]"
t "/media en écriture"               "docker inspect jellyfin --format '{{range .Mounts}}{{.Destination}}={{.RW}} {{end}}' | grep -q '/media=true'"
t "/media/musique en lecture seule"  "docker inspect jellyfin --format '{{range .Mounts}}{{.Destination}}={{.RW}} {{end}}' | grep -q '/media/musique=false'"

echo "== Réseau"
t "AdGuard répond (home.lan)"        "[ \"\$(dig +short home.lan @127.0.0.1)\" = 192.168.1.199 ]"
t "DuckDNS public → 192.168.1.199"   "[ \"\$(dig +short exemple.duckdns.org @1.1.1.1)\" = 192.168.1.199 ]"
t "Tailscale connecté"               "tailscale status --peers=false >/dev/null"
t "Tailscale annonce 192.168.1.199/32" "tailscale debug prefs 2>/dev/null | grep -q '192.168.1.199/32'"

echo "== Tour et sauvegarde"
if ping -c1 -W2 192.168.1.198 >/dev/null 2>&1; then
  t "tour : partage (445)"           "timeout 4 bash -c '</dev/tcp/192.168.1.198/445'"
  t "tour : montage /mnt/tour-backup" "timeout 10 df /mnt/tour-backup"
else
  echo "info  tour éteinte (normal si tu ne l'as pas allumée)"
fi
echo "info  prochaine sauvegarde : $(systemctl list-timers homelab-backup.timer --no-pager | sed -n 2p | awk '{print $1, $2, $3}')"
echo "info  dernière exécution : $(python3 -c "import json,datetime;e=max(json.load(open('/var/lib/homelab-backup/executions.json')),key=lambda x:x.get('debut',0));print(datetime.datetime.fromtimestamp(e['debut']).strftime('%d/%m %H:%M'), e.get('resultat'))" 2>/dev/null)"

echo
echo "Résultat : $ok ok, $ko échec(s)."
[ "$ko" -eq 0 ]
