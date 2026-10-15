#!/usr/bin/env bash
# Met à jour exemple.duckdns.org vers l'adresse LOCALE du portable (192.168.1.199).
# Lancé chaque jour par duckdns-maj.timer (systemd utilisateur). Voir ~/homelab/CHANGELOG.md.
# Le jeton est lu dans ~/.config/homelab/duckdns-token et passé à curl par l'entrée standard
# (jamais en argument, donc invisible dans « ps ») ; il n'est jamais écrit dans le journal.
set -uo pipefail
DOMAINE="exemple"
IP="192.168.1.199"
JETON_F="$HOME/.config/homelab/duckdns-token"
LOG="$HOME/homelab/logs/duckdns.log"
ntfy() { curl -s -m 5 -d "$1" http://127.0.0.1:8089/homelab >/dev/null 2>&1 || true; }
note() { echo "$(date '+%F %T') $1" >> "$LOG"; echo "$1"; }

jeton="$(tr -d ' \r\n' < "$JETON_F" 2>/dev/null || true)"
if [ -z "$jeton" ]; then
  note "ÉCHEC : jeton absent ou vide ($JETON_F)"; ntfy "DuckDNS : jeton absent, mise à jour impossible"; exit 1
fi

rep="$(printf 'url = "https://www.duckdns.org/update?domains=%s&token=%s&ip=%s"\n' "$DOMAINE" "$jeton" "$IP" \
       | curl -s -m 20 --retry 3 --retry-delay 10 -K -)"
unset jeton
if [ "$rep" = "OK" ]; then
  note "OK : $DOMAINE.duckdns.org -> $IP"
else
  note "ÉCHEC : réponse DuckDNS « ${rep:-aucune} »"; ntfy "DuckDNS : mise à jour refusée (${rep:-pas de réponse})"; exit 1
fi
