#!/usr/bin/env python3
"""Crée les sondes Kuma « Fichiers » et « Pelican » en copiant la sonde 8 (Stirling : HTTP, 60 s, 30 essais × 60 s,
mêmes notifications dont Courriel), avec l'URL de santé de homelab-api. Kuma doit être ARRÊTÉ.
Usage : sudo python3 -I ~/pack-maison/kuma/sondes-nouvelles.py /home/alex/homelab/kuma/data/kuma.db
Retour : sudo cp -a kuma.db.avant-sondes kuma.db (Kuma arrêté)."""
import os, sqlite3, sys
db = sys.argv[1]
if not os.path.exists(db + ".avant-sondes"):
    sys.exit("ARRÊT : copie kuma.db.avant-sondes absente, rien n'a été modifié.")
c = sqlite3.connect(db)
modele = c.execute("select name from monitor where id = 8").fetchone()
if not modele or modele[0] != "Stirling":
    sys.exit("ARRÊT : la sonde 8 n'est pas Stirling, rien n'a été modifié.")
cols = [r[1] for r in c.execute("pragma table_info(monitor)") if r[1] != "id"]
for nom, ident in (("Fichiers", "fichiers"), ("Pelican", "jeux")):
    if c.execute("select 1 from monitor where name = ?", (nom,)).fetchone():
        print("déjà là :", nom); continue
    liste = ", ".join('"%s"' % k for k in cols)
    c.execute("insert into monitor (%s) select %s from monitor where id = 8" % (liste, liste))
    nid = c.execute("select last_insert_rowid()").fetchone()[0]
    c.execute("update monitor set name = ?, url = ? where id = ?", (nom, "http://127.0.0.1:8095/api/sante/" + ident, nid))
    c.execute("insert into monitor_notification (monitor_id, notification_id) select ?, notification_id from monitor_notification where monitor_id = 8", (nid,))
    print("créée :", nid, nom)
c.commit()
print("OK")
