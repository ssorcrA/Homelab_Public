#!/usr/bin/env python3
"""Oriente les 8 sondes Kuma vers la santé de homelab-api (14/10/2026) : 200 si le service marche ou a été éteint
volontairement depuis l'admin, 503 s'il est tombé. 30 nouveaux essais espacés de 60 s : panne déclarée (et mail) après 30 min.
Kuma doit être ARRÊTÉ. Ne touche qu'à url, maxretries et retry_interval des sondes 3 à 10 (notifications et mots de passe intacts).
Usage : sudo python3 -I ~/pack-maison/kuma/sondes-services.py /home/alex/homelab/kuma/data/kuma.db
Retour : sudo cp -a kuma.db.avant-services kuma.db (Kuma arrêté)."""
import os, sqlite3, sys
db = sys.argv[1]
if not os.path.exists(db + ".avant-services"):
    sys.exit("ARRÊT : copie kuma.db.avant-services absente, rien n'a été modifié.")
SONDES = {3: ("jellyfin", "films"), 4: ("Navidrome", "musique"), 5: ("Immich", "photos"), 6: ("Nextcloud", "cloud"),
          7: ("Paperless", "docs"), 8: ("Stirling", "pdf"), 9: ("metube", "videos"), 10: ("Home assistant", "domotique")}
c = sqlite3.connect(db)
noms = dict(c.execute("select id, name from monitor"))
for i, (nom, _) in SONDES.items():
    if noms.get(i) != nom:
        sys.exit("ARRÊT : la sonde %d s'appelle %r au lieu de %r, rien n'a été modifié." % (i, noms.get(i), nom))
for i, (_, ident) in SONDES.items():
    c.execute("update monitor set url = ?, maxretries = 30, retry_interval = 60 where id = ?",
              ("http://127.0.0.1:8095/api/sante/" + ident, i))
c.commit()
for r in c.execute("select id, name, url, maxretries, retry_interval from monitor where id between 3 and 10"):
    print(*r)
print("OK : 8 sondes modifiées.")
