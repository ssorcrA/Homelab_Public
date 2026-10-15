#!/usr/bin/env python3
"""Garde une trace de CHAQUE exécution de la sauvegarde (réussie ou ratée), avec son journal.

Lancé en root par systemd après chaque exécution (ExecStopPost de homelab-backup.service).
systemd fournit SERVICE_RESULT, EXIT_CODE, EXIT_STATUS et INVOCATION_ID.
Usage : suivi-sauvegardes.py DOSSIER_DONNEES [MARQUEUR_MANUEL [SCRIPT_INSTANTANES SORTIE.json]]
Si la sauvegarde a vraiment eu lieu et réussi, rafraîchit aussi la liste des instantanés restic.
Une sauvegarde sautée (déjà faite récemment) est notée « ignoree » : homelab-backup.sh l'écrit dans DOSSIER_DONNEES/dernier-statut.
Écrit DOSSIER_DONNEES/executions.json (50 dernières exécutions, journal de 200 lignes maxi chacune).
"""
import json
import os
import re
import subprocess
import sys
import time

UNITE = os.environ.get("HOMELAB_UNITE", "homelab-backup.service")
dossier = sys.argv[1]
marqueur = sys.argv[2] if len(sys.argv) > 2 else ""
instantanes = sys.argv[3:5]
MAX_EXEC, MAX_LIGNES, MAX_CAR = 50, 200, 24000


def sh(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=60).stdout


def horodatage(v):
    m = re.match(r"@(\d+)", v or "")
    return int(m.group(1)) if m and int(m.group(1)) > 0 else None


def propriete(nom):
    # pendant ExecStopPost, l'unité est encore « deactivating » : les dates de début et de fin sont déjà connues
    s = sh(["systemctl", "show", "--timestamp=unix", UNITE, "-p" + nom])
    return s.partition("=")[2].strip()


debut = horodatage(propriete("ExecMainStartTimestamp")) or int(time.time())
fin = horodatage(propriete("ExecMainExitTimestamp")) or int(time.time())
resultat = os.environ.get("SERVICE_RESULT", "inconnu")
code = os.environ.get("EXIT_STATUS") or os.environ.get("EXIT_CODE") or ""
invocation = os.environ.get("INVOCATION_ID", "")

# statut écrit par homelab-backup.sh pendant CETTE exécution (on ignore un fichier plus ancien)
statut = ""
try:
    chemin = os.path.join(dossier, "dernier-statut")
    if os.stat(chemin).st_mtime >= debut - 5:
        with open(chemin, encoding="utf-8") as f:
            statut = f.read().strip()
except OSError:
    pass
ignoree = resultat == "success" and statut == "ignoree"

if invocation:
    journal = sh(["journalctl", "--no-pager", "-o", "short-iso", "_SYSTEMD_INVOCATION_ID=" + invocation])
else:
    journal = sh(["journalctl", "--no-pager", "-o", "short-iso", "-u", UNITE, "--since", "@%d" % (debut - 1)])
lignes = [l for l in journal.splitlines() if l.strip()]
if len(lignes) > MAX_LIGNES:
    lignes = ["[… %d lignes plus anciennes omises …]" % (len(lignes) - MAX_LIGNES)] + lignes[-MAX_LIGNES:]
texte = "\n".join(lignes)[-MAX_CAR:]

declencheur = "automatique"
try:
    if marqueur and debut - 300 <= os.stat(marqueur).st_mtime <= fin + 5:
        declencheur = "manuel"
except OSError:
    pass

entree = {
    "id": invocation or str(debut),
    "debut": debut,
    "fin": fin,
    "duree_s": max(0, fin - debut),
    "reussi": None if ignoree else resultat == "success",
    "resultat": "ignoree" if ignoree else resultat,
    "code": code,
    "declencheur": declencheur,
    "journal": texte or "(aucun message dans le journal)",
}

os.makedirs(dossier, exist_ok=True)
os.chmod(dossier, 0o755)
fichier = os.path.join(dossier, "executions.json")
try:
    with open(fichier, encoding="utf-8") as f:
        liste = json.load(f)
except (OSError, ValueError):
    liste = []
liste = [e for e in liste if e.get("id") != entree["id"]]
liste.append(entree)
liste = sorted(liste, key=lambda e: e["debut"], reverse=True)[:MAX_EXEC]
tmp = fichier + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(liste, f, ensure_ascii=False)
os.chmod(tmp, 0o644)
os.replace(tmp, fichier)

# seulement après une vraie sauvegarde réussie ; 75 s maxi pour rester sous le délai d'arrêt de systemd (90 s)
if entree["reussi"] is True and len(instantanes) == 2:
    try:
        subprocess.run(instantanes, timeout=75)
    except (OSError, subprocess.SubprocessError):
        pass
