#!/usr/bin/env python3
"""Écrit la liste des dernières sauvegardes restic dans un fichier JSON lu par admin.lan.
Lancé en root par systemd après chaque sauvegarde (ExecStartPost). Usage : historique-sauvegardes.py SORTIE.json"""
import json
import os
import re
import socket
import subprocess
import sys
from datetime import datetime

sortie = sys.argv[1]

# Tour éteinte : on n'interroge pas restic (le partage réseau ferait attendre, et systemd couperait le service)
TOUR = os.environ.get("HOMELAB_TOUR", "192.168.1.198")
PORT = int(os.environ.get("HOMELAB_TOUR_PORT", "445"))
try:
    socket.create_connection((TOUR, PORT), timeout=3).close()
except OSError:
    sys.exit("Tour injoignable (%s:%d) : liste des instantanés non rafraîchie." % (TOUR, PORT))

try:
    r = subprocess.run([os.environ.get("RESTIC_WRAPPER", "/usr/local/sbin/restic-homelab"), "snapshots", "--json"], capture_output=True, text=True, timeout=60)
except subprocess.TimeoutExpired:
    sys.exit("restic snapshots : pas de réponse en 60 s, liste non rafraîchie.")
if r.returncode != 0:
    sys.exit("restic snapshots a échoué : " + r.stderr.strip()[:300])


def instant(s):
    return datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", s).replace("Z", "+00:00"))


out = []
for s in sorted(json.loads(r.stdout), key=lambda x: x["time"], reverse=True)[:30]:
    sm = s.get("summary") or {}
    duree = None
    try:
        duree = (instant(sm["backup_end"]) - instant(sm["backup_start"])).total_seconds()
    except (KeyError, ValueError):
        pass
    fichiers = None
    if "files_new" in sm:
        fichiers = sm.get("files_new", 0) + sm.get("files_changed", 0)
    out.append({"id": s["short_id"], "date": instant(s["time"]).isoformat(timespec="seconds"), "ajoute": sm.get("data_added"), "fichiers": fichiers, "duree_s": duree})

tmp = sortie + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False)
os.chmod(tmp, 0o644)
os.replace(tmp, sortie)
