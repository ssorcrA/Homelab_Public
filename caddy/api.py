#!/usr/bin/env python3
"""Petit service local du homelab, à l'écoute sur 127.0.0.1:8095 (Caddy le relaie sous /api/).

- écrit etat.json (état des services) dans les pages home et admin toutes les 30 s
- GET  /api/systeme      processeur, mémoire, disque, température, batterie, conteneurs (admin)
- GET  /api/appareils    appareils de Home Assistant listés dans appareils.json (admin)
- POST /api/appareil     allume ou éteint un appareil de cette liste (admin)
- GET  /api/sauvegarde   état, exécutions (réussies ou ratées) et instantanés restic (admin)
- GET  /api/sauvegarde/journal?id=...   journal d'une exécution (admin)
- GET  /api/sauvegarde/direct           dernières lignes du journal en cours (admin)
- POST /api/sauvegarde   lance la sauvegarde maintenant (admin)
- POST /api/tour/allumer envoie le paquet Wake-on-LAN à la tour (admin)
- POST /api/tour/eteindre éteint la tour par SSH (clé dédiée, commande imposée côté Windows) (admin)
- GET  /api/services     interrupteurs : état de chaque service de la liste SVC (admin)
- POST /api/service      allume ou éteint un service de cette liste, {"id":…, "action":"allumer"|"eteindre"} (admin)
- GET  /api/sante/<id>   pour Uptime Kuma : 200 si le service marche OU a été éteint volontairement, 503 s'il est tombé

Aucun mot de passe n'est stocké ici. Le jeton de Home Assistant est lu dans
~/.config/homelab/ha-token (droits 600), que tu crées toi-même.
"""
import glob
import json
import os
import re
import shutil
import socket
import ssl
import subprocess
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOME = os.path.expanduser("~")
BASE = os.environ.get("HOMELAB_DIR", os.path.join(HOME, "homelab"))
PAGES = os.path.join(BASE, "caddy", "pages")
CONF = os.environ.get("HOMELAB_CONF", os.path.join(HOME, ".config", "homelab"))
PORT = int(os.environ.get("HOMELAB_API_PORT", "8095"))
TOUR_IP = os.environ.get("HOMELAB_TOUR_IP", "192.168.1.198")
HA_URL = os.environ.get("HOMELAB_HA_URL", "http://127.0.0.1:8123")
TOUR_MAC = os.environ.get("HOMELAB_TOUR_MAC", "00:11:22:33:44:55")
WOL_ADDR = (os.environ.get("HOMELAB_WOL_IP", "192.168.1.255"), int(os.environ.get("HOMELAB_WOL_PORT", "9")))
BACKUP_UNIT = "homelab-backup.service"
BACKUP_TIMER = "homelab-backup.timer"
RUNS = os.environ.get("HOMELAB_RUNS", "/var/lib/homelab-backup/executions.json")
MARQUEUR = os.path.join(CONF, "sauvegarde-manuelle")

SERVICES = {
    "films": "http://127.0.0.1:8096/",
    "musique": "http://127.0.0.1:4533/",
    "photos": "http://127.0.0.1:2283/",
    "cloud": "http://127.0.0.1:8082/",
    "docs": "http://127.0.0.1:8000/",
    "pdf": "http://127.0.0.1:8084/",
    "videos": "http://127.0.0.1:8083/",
    "domotique": "http://127.0.0.1:8123/",
    "fichiers": "http://127.0.0.1:8097/health",
    "dns": "http://127.0.0.1:3000/",
    "docker": "https://127.0.0.1:9443/",
    "logs": "http://127.0.0.1:8086/",
    "status": "http://127.0.0.1:3001/",
    "monitor": "http://127.0.0.1:8090/",
    "disque": "http://127.0.0.1:8087/",
    "notif": "http://127.0.0.1:8089/",
    "jeux": "http://127.0.0.1:8085/",
    "ia": "http://127.0.0.1:8088/",
}

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def write_json(path, obj):
    tmp = "%s.tmp%d" % (path, threading.get_ident())   # un fichier temporaire par fil : écritures simultanées sans mélange
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def sh(args, timeout=5):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


# ---------------------------------------------------------------- état des services
ETAT = {"maj": 0, "services": {}, "tour": False}


def check_raison(url):
    """(en ligne ?, raison) : en ligne s'il répond avec un code inférieur à 500."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "homelab-etat"})
        with urllib.request.urlopen(req, timeout=3, context=CTX) as r:
            return r.status < 500, "code %d" % r.status
    except urllib.error.HTTPError as e:
        return e.code < 500, "code %d" % e.code
    except Exception as e:
        return False, "%s: %s" % (type(e).__name__, e)


def check(url):
    return check_raison(url)[0]


ECHECS = {}        # id -> vérifications échouées d'affilée (boucle des 30 s)
ECHECS_MAX = 2     # « hors ligne » seulement après 2 échecs d'affilée (évite les fausses pannes de quelques secondes)


def tour_en_ligne():
    try:
        socket.create_connection((TOUR_IP, 445), 2).close()
        return True
    except OSError:
        return False


def boucle_etat():
    while True:
        try:
            with ThreadPoolExecutor(8) as ex:
                brut = dict(zip(SERVICES, ex.map(check_raison, SERVICES.values())))
            res = {}
            for k, (ok, raison) in brut.items():
                if ok:
                    if ECHECS.get(k):
                        print("sonde %s : revenu après %d échec(s)" % (k, ECHECS[k]), flush=True)
                    ECHECS[k] = 0
                else:
                    ECHECS[k] = ECHECS.get(k, 0) + 1
                    if k not in eteints():
                        print("sonde %s : échec %d d'affilée (%s)" % (k, ECHECS[k], raison), flush=True)
                res[k] = ok or (k not in eteints() and ECHECS[k] < ECHECS_MAX and ETAT["services"].get(k) is not False)
            ETAT.update(maj=int(time.time()), services=res, tour=tour_en_ligne(), eteints=sorted(eteints()))
            for d in ("home", "admin"):
                if os.path.isdir(os.path.join(PAGES, d)):
                    write_json(os.path.join(PAGES, d, "etat.json"), ETAT)
        except Exception as e:  # le service ne doit jamais s'arrêter
            print("etat:", e, flush=True)
        time.sleep(30)


# ---------------------------------------------------------------- système
CPU = {"pct": None}


def cpu_sample():
    with open("/proc/stat") as f:
        v = list(map(int, f.readline().split()[1:]))
    return v[3] + v[4], sum(v)


def boucle_cpu():
    prev = cpu_sample()
    while True:
        time.sleep(2)
        cur = cpu_sample()
        d_total = cur[1] - prev[1]
        if d_total > 0:
            CPU["pct"] = round(100 * (1 - (cur[0] - prev[0]) / d_total), 1)
        prev = cur


def meminfo():
    m = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, _, v = line.partition(":")
            m[k] = int(v.split()[0])
    total, dispo = m["MemTotal"], m["MemAvailable"]
    st, sf = m.get("SwapTotal", 0), m.get("SwapFree", 0)
    return {
        "total_mo": total // 1024,
        "utilise_mo": (total - dispo) // 1024,
        "pct": round(100 * (total - dispo) / total, 1),
        "swap_mo": (st - sf) // 1024,
    }


def temperature():
    vals = []
    for p in glob.glob("/sys/class/thermal/thermal_zone*/temp") + glob.glob("/sys/class/hwmon/hwmon*/temp*_input"):
        try:
            vals.append(int(open(p).read()) / 1000)
        except (OSError, ValueError):
            pass
    vals = [v for v in vals if 0 < v < 130]
    return round(max(vals), 1) if vals else None


def batterie():
    for d in glob.glob("/sys/class/power_supply/BAT*"):
        try:
            return {"pct": int(read_text(d + "/capacity")), "etat": read_text(d + "/status")}
        except (TypeError, ValueError):
            pass
    return None


_docker = {"t": 0, "v": None}


def conteneurs():
    if time.time() - _docker["t"] > 20:
        try:
            r = sh(["docker", "ps", "-a", "--format", '{{.Names}} {{.State}} {{.Label "com.docker.compose.oneoff"}}'], 6)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.strip())  # Docker injoignable : la page affiche "Docker ne répond pas"
            voulus = set(c for i in eteints() for c in SVC_ID[i][4])   # conteneurs des services éteints par l'interrupteur
            actifs = arretes = volontaires = 0
            for l in r.stdout.splitlines():
                p = l.split()
                if len(p) < 2:
                    continue
                if p[1] == "running":
                    actifs += 1
                elif p[1] in ("exited", "dead", "created"):
                    if len(p) > 2 and p[2] == "True":
                        continue                     # tâche ponctuelle (docker compose run) : pas un problème
                    if p[0] in voulus:
                        volontaires += 1
                    else:
                        arretes += 1
            _docker["v"] = {"actifs": actifs, "arretes": arretes, "eteints": volontaires, "services_eteints": len(eteints())}
        except Exception:
            _docker["v"] = None
        _docker["t"] = time.time()
    return _docker["v"]


def systeme():
    du = shutil.disk_usage("/")
    media = os.path.join(HOME, "media")
    dm = shutil.disk_usage(media) if os.path.isdir(media) else None
    with open("/proc/uptime") as f:
        up = int(float(f.read().split()[0]))
    return {
        "cpu": CPU["pct"],
        "charge": os.getloadavg(),
        "coeurs": os.cpu_count(),
        "ram": meminfo(),
        "disque": {"pct": round(100 * du.used / du.total, 1), "libre_go": round(du.free / 1e9, 1), "total_go": round(du.total / 1e9)},
        "media": {"libre_go": round(dm.free / 1e9, 1)} if dm else None,
        "temp": temperature(),
        "batterie": batterie(),
        "uptime_s": up,
        "conteneurs": conteneurs(),
        "tour": ETAT["tour"],
        "maj": int(time.time()),
    }


# ---------------------------------------------------------------- sauvegarde
def ts(v):
    m = re.match(r"@(\d+)", v or "")
    return int(m.group(1)) if m and int(m.group(1)) > 0 else None


def show(unit, *props):
    r = sh(["systemctl", "show", "--timestamp=unix", unit] + ["-p" + p for p in props])
    d = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition("=")
        d[k] = v
    return d


def prochaine(timer):
    # systemd 257 laisse NextElapseUSecRealtime en texte même avec --timestamp=unix : on lit list-timers en JSON
    r = sh(["systemctl", "list-timers", timer, "--all", "--output=json"])
    try:
        n = json.loads(r.stdout or "[]")[0].get("next")
        return int(n) // 1000000 if n else None
    except (ValueError, IndexError, TypeError, AttributeError):
        return None


def sauvegarde():
    s = show(BACKUP_UNIT, "ActiveState", "Result", "ExecMainStatus", "ExecMainStartTimestamp", "ExecMainExitTimestamp")
    try:
        with open(os.path.join(PAGES, "admin", "sauvegardes.json"), encoding="utf-8") as f:
            hist = json.load(f)
    except (OSError, ValueError):
        hist = []
    return {
        "actif": s.get("ActiveState") in ("active", "activating"),
        "resultat": s.get("Result"),
        "code": s.get("ExecMainStatus"),
        "debut": ts(s.get("ExecMainStartTimestamp")),
        "fin": ts(s.get("ExecMainExitTimestamp")),
        "prochaine": prochaine(BACKUP_TIMER),
        "historique": hist,
        "executions": [{k: v for k, v in e.items() if k != "journal"} for e in executions()],
    }


def executions():
    try:
        with open(RUNS, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def journal_execution(ident):
    for e in executions():
        if e.get("id") == ident:
            return 200, {"id": ident, "journal": e.get("journal", "")}
    return 404, {"erreur": "Exécution introuvable."}


def journal_direct():
    r = sh(["sudo", "-n", "/usr/bin/journalctl", "-u", BACKUP_UNIT, "-n", "150", "--no-pager", "-o", "short-iso"], 10)
    if r.returncode != 0:
        return 500, {"erreur": "Journal illisible (droit sudo manquant ?)."}
    return 200, {"journal": r.stdout}


def lancer_sauvegarde():
    if sauvegarde()["actif"]:
        return 409, {"erreur": "Une sauvegarde est déjà en cours."}
    try:
        os.makedirs(CONF, exist_ok=True)
        with open(MARQUEUR, "w") as f:
            f.write(str(int(time.time())))
    except OSError:
        pass
    r = sh(["sudo", "-n", "/usr/bin/systemctl", "start", "--no-block", BACKUP_UNIT], 10)
    if r.returncode != 0:
        return 500, {"erreur": "Impossible de lancer la sauvegarde (droit sudo manquant ?)."}
    return 200, {"ok": True}


# ---------------------------------------------------------------- tour (Wake-on-LAN)
_wol = {"t": 0}


def allumer_tour():
    if time.time() - _wol["t"] < 15:
        return 429, {"erreur": "Paquet déjà envoyé, patiente quelques secondes."}
    mac = re.sub(r"[^0-9A-Fa-f]", "", TOUR_MAC)
    if len(mac) != 12:
        return 500, {"erreur": "Adresse MAC de la tour invalide."}
    paquet = b"\xff" * 6 + bytes.fromhex(mac) * 16
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(paquet, WOL_ADDR)
    except OSError as e:
        return 500, {"erreur": "Envoi impossible : %s" % e}
    _wol["t"] = time.time()
    return 200, {"ok": True, "deja": ETAT.get("tour") is True}


_ext = {"t": 0}
TOUR_CLE = os.path.join(CONF, "tour-extinction")             # clé dédiée, sans phrase de passe (600)
TOUR_KNOWN = os.path.join(CONF, "tour-known_hosts")          # empreinte de la tour, vérifiée par Alex
TOUR_USER = os.path.join(CONF, "tour-utilisateur")           # nom du compte Windows


def sauvegarde_active():
    return show(BACKUP_UNIT, "ActiveState").get("ActiveState") in ("active", "activating")


def ssh_tour(user):
    # Aucune commande envoyée : la clé est limitée côté Windows à "shutdown /s /t 30" (command=).
    return sh(["ssh", "-F", "/dev/null", "-T", "-i", TOUR_CLE,
               "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none",
               "-o", "UserKnownHostsFile=" + TOUR_KNOWN, "-o", "GlobalKnownHostsFile=/dev/null",
               "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
               "%s@%s" % (user, TOUR_IP)], 20)


def eteindre_tour():
    if sauvegarde_active():
        return 409, {"erreur": "Sauvegarde en cours, réessaie après."}
    if not tour_en_ligne():
        return 409, {"erreur": "La tour est déjà éteinte ou ne répond pas."}
    if time.time() - _ext["t"] < 60:
        return 429, {"erreur": "Extinction déjà demandée : la tour s'éteint dans quelques secondes."}
    user = read_text(TOUR_USER)
    if not user or not os.path.isfile(TOUR_CLE) or not os.path.isfile(TOUR_KNOWN):
        return 500, {"erreur": "Extinction pas encore configurée (clé, compte ou empreinte de la tour)."}
    try:
        r = ssh_tour(user)
    except subprocess.TimeoutExpired:
        return 504, {"erreur": "La tour ne répond pas en SSH."}
    if r.returncode == 255:
        return 502, {"erreur": "Connexion SSH à la tour impossible."}
    if r.returncode != 0:
        return 502, {"erreur": "La tour a refusé l'extinction (code %d)." % r.returncode}
    _ext["t"] = time.time()
    return 200, {"ok": True, "delai": 30}


# ---------------------------------------------------------------- appareils (Home Assistant)
TOGGLE = {"light", "switch", "fan", "input_boolean", "cover"}
_app = {"t": 0, "v": None}


def ha(path, data=None):
    token = read_text(os.path.join(CONF, "ha-token"))
    req = urllib.request.Request(
        HA_URL + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": "Bearer " + (token or ""), "Content-Type": "application/json"},
        method="POST" if data is not None else "GET",
    )
    with urllib.request.urlopen(req, timeout=4) as r:
        return json.load(r)


def liste_appareils():
    try:
        with open(os.path.join(CONF, "appareils.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def appareils(force=False):
    if not force and time.time() - _app["t"] < 3 and _app["v"]:
        return _app["v"]
    cfg = liste_appareils()
    if not cfg:
        res = {"ok": False, "raison": "pas_de_liste", "appareils": []}
    elif not read_text(os.path.join(CONF, "ha-token")):
        res = {"ok": False, "raison": "pas_de_jeton", "appareils": []}
    else:
        try:
            etats = {s["entity_id"]: s for s in ha("/api/states")}
        except Exception:
            return {"ok": False, "raison": "ha_injoignable", "appareils": []}
        out = []
        for c in cfg:
            s = etats.get(c["id"])
            dom = c["id"].split(".")[0]
            at = (s or {}).get("attributes", {})
            item = {
                "id": c["id"],
                "nom": c.get("nom") or at.get("friendly_name") or c["id"],
                "piece": c.get("piece", ""),
                "type": dom,
                "etat": s["state"] if s else "absent",
                "bascule": dom in TOGGLE,
            }
            if dom == "sensor" and s:
                item["valeur"], item["unite"] = s["state"], at.get("unit_of_measurement", "")
            if dom == "climate" and s:
                item["valeur"], item["unite"] = at.get("current_temperature"), "°C"
                item["consigne"] = at.get("temperature")
            out.append(item)
        res = {"ok": True, "appareils": out}
    _app.update(t=time.time(), v=res)
    return res


def basculer(entity):
    cfg = liste_appareils() or []
    if entity not in [c["id"] for c in cfg]:
        return 404, {"erreur": "Appareil inconnu."}
    dom = entity.split(".")[0]
    if dom not in TOGGLE:
        return 400, {"erreur": "Cet appareil ne peut pas être commandé."}
    try:
        ha("/api/services/%s/toggle" % dom, {"entity_id": entity})
    except Exception:
        return 502, {"erreur": "Home Assistant ne répond pas."}
    time.sleep(0.5)
    return 200, appareils(force=True)


# ---------------------------------------------------------------- services (interrupteurs de l'admin, santé pour Kuma)
# Liste fixe : la page n'envoie qu'un identifiant, jamais un nom de conteneur ou une commande.
# Hors liste (l'admin en dépend, ou outils de secours) : caddy, adguard, portainer, dozzle.
# id, nom, groupe, dossiers compose (dans ~/homelab), conteneurs, adresse de santé (None : conteneurs seulement), avertissement
SVC = [
    ("films", "Films et séries", "Famille", ["jellyfin"], ["jellyfin"], "http://127.0.0.1:8096/health", ""),
    ("musique", "Musique", "Famille", ["navidrome"], ["navidrome"], "http://127.0.0.1:4533/ping", ""),
    ("photos", "Photos", "Famille", ["immich"], ["immich_server", "immich_machine_learning", "immich_postgres", "immich_redis"],
     "http://127.0.0.1:2283/api/server/ping", ""),
    ("cloud", "Cloud", "Famille", ["nextcloud"], ["nextcloud", "nextcloud-db", "nextcloud-redis", "nextcloud-cron"],
     "http://127.0.0.1:8082/status.php", "Tant qu'il est éteint, la sauvegarde ne peut pas exporter sa base."),
    ("docs", "Documents", "Famille", ["paperless"], ["paperless", "paperless-broker"], "http://127.0.0.1:8000",
     "Tant qu'il est éteint, la sauvegarde ne peut pas exporter les documents."),
    ("pdf", "Outils PDF", "Famille", ["stirling"], ["stirling"], "http://127.0.0.1:8084", ""),
    ("videos", "Vidéos (MeTube)", "Famille", ["metube"], ["metube"], "http://127.0.0.1:8083", ""),
    ("fichiers", "Fichiers", "Famille", ["fichiers"], ["fichiers"], "http://127.0.0.1:8097/health", ""),
    ("domotique", "Maison connectée", "Famille", ["homeassistant"], ["homeassistant"], "http://127.0.0.1:8123",
     "Les appareils de cette page et l'appli du téléphone ne marcheront plus."),
    ("jeux", "Pelican (jeux)", "Jeux et IA", ["pelican"], ["pelican-panel"], "http://127.0.0.1:8085", ""),
    ("ia", "Open WebUI (IA)", "Jeux et IA", ["ia"], ["ollama", "open-webui"], "http://127.0.0.1:8088",
     "Démarre en 1 à 2 minutes et utilise beaucoup de mémoire."),
    ("status", "Uptime Kuma", "Surveillance", ["kuma"], ["kuma"], "http://127.0.0.1:3001",
     "Plus aucune alerte par mail tant qu'il est éteint."),
    ("monitor", "Beszel", "Surveillance", ["beszel", "beszel-agent"], ["beszel", "beszel-agent"], "http://127.0.0.1:8090", ""),
    ("disque", "Scrutiny", "Surveillance", ["scrutiny"], ["scrutiny"], "http://127.0.0.1:8087", ""),
    ("diun", "Diun", "Surveillance", ["diun"], ["diun"], None, ""),
    ("notif", "ntfy", "Surveillance", ["ntfy"], ["ntfy"], "http://127.0.0.1:8089/v1/health", ""),
]
SVC_ID = {s[0]: s for s in SVC}
ETEINTS = os.path.join(CONF, "services-eteints.json")   # services éteints volontairement (pas d'alerte)
CONTENEURS_ETEINTS = os.path.join(CONF, "conteneurs-eteints")   # leurs conteneurs, un par ligne : lu par garde-fou.sh
_svc_lock = threading.Lock()
_svc_action = {}    # id -> "allumer" / "eteindre" pendant l'opération
_svc_erreur = {}    # id -> message du dernier échec
_svc_demarre = {}   # id -> heure de fin d'un allumage : « Démarrage… » tant qu'il ne répond pas (5 min maxi)
DEMARRAGE_MAX = 300
_ps = {"t": 0, "v": None}


def etats_conteneurs():
    """nom -> état Docker (running, exited…), relu au plus toutes les 10 s ; None si Docker ne répond pas."""
    if time.time() - _ps["t"] > 10:
        try:
            r = sh(["docker", "ps", "-a", "--format", "{{.Names}} {{.State}}"], 6)
            _ps["v"] = dict(l.split(" ", 1) for l in r.stdout.splitlines() if " " in l) if r.returncode == 0 else None
        except Exception:
            _ps["v"] = None
        _ps["t"] = time.time()
    return _ps["v"]


def eteints():
    try:
        with open(ETEINTS, encoding="utf-8") as f:
            return set(i for i in json.load(f) if i in SVC_ID)
    except (OSError, ValueError, TypeError):
        return set()


def noter_eteint(ident, oui):
    with _svc_lock:
        e = eteints()
        e.add(ident) if oui else e.discard(ident)
        os.makedirs(CONF, exist_ok=True)
        write_json(ETEINTS, sorted(e))
        ecrire_conteneurs(e)


def ecrire_conteneurs(e):
    """Conteneurs des services éteints par l'interrupteur : le garde-fou ne les relance pas."""
    tmp = CONTENEURS_ETEINTS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("".join(c + "\n" for i in sorted(e) for c in SVC_ID[i][4]))
    os.chmod(tmp, 0o644)
    os.replace(tmp, CONTENEURS_ETEINTS)


def etat_service(s, frais=False):
    """marche | eteint (par Alex) | tombe | en_cours | inconnu (Docker ne répond pas)."""
    ident, url = s[0], s[5]
    if ident in _svc_action:
        return "en_cours"
    ps = etats_conteneurs()
    if ps is None:
        return "inconnu"
    tournent = [ps.get(c) == "running" for c in s[4]]
    if ident in eteints():
        if not any(tournent):
            return "eteint"
        if not all(tournent):
            return "eteint"          # arrêt partiel en cours ou reste d'un arrêt : toujours volontaire
        noter_eteint(ident, False)   # rallumé à la main en dehors de l'admin : les alertes reprennent
    if not all(tournent):
        return "tombe"
    if url is None:
        return "marche"
    demarre = time.time() - _svc_demarre.get(ident, 0) < DEMARRAGE_MAX
    ok = ETAT["services"].get(ident) if not (frais or demarre) else None
    if ok is None:
        ok = check(url)
    if ok:
        _svc_demarre.pop(ident, None)
        return "marche"
    return "en_cours" if demarre else "tombe"


RAM = {"t": 0, "v": {}}   # conteneur -> mémoire utilisée (Mo), relue toutes les 30 s en tâche de fond
UNITES = {"B": 1 / 1048576, "KiB": 1 / 1024, "kB": 1 / 1024, "MiB": 1, "MB": 1, "GiB": 1024, "GB": 1024}


def boucle_ram():
    while True:
        try:
            r = sh(["docker", "stats", "--no-stream", "--format", "{{.Name}}\t{{.MemUsage}}"], 20)
            v = {}
            for l in r.stdout.splitlines():
                nom, _, mem = l.partition("\t")
                m = re.match(r"([\d.]+)\s*([A-Za-z]+)", mem)
                if m and m.group(2) in UNITES:
                    v[nom] = float(m.group(1)) * UNITES[m.group(2)]
            if r.returncode == 0:
                RAM.update(t=int(time.time()), v=v)
        except Exception as e:
            print("ram:", e, flush=True)
        time.sleep(30)


def ram_service(s):
    """Mémoire de tous les conteneurs du service, en Mo (None si inconnue ; 0 si rien ne tourne)."""
    if not RAM["t"]:
        return None
    return round(sum(RAM["v"].get(c, 0) for c in s[4]))


def recaler_etat(ident, e):
    """Met tout de suite etat.json d'accord avec l'état vu par l'admin (sinon jusqu'à 30 s de retard)."""
    if ident not in ETAT["services"]:
        return False
    v = True if e == "marche" else False if e in ("tombe", "eteint") else None
    if v is None or ETAT["services"][ident] == v:
        return False
    ETAT["services"][ident] = v
    return True


def services():
    out, change = [], False
    for s in SVC:
        e = etat_service(s)
        change = recaler_etat(s[0], e) or change
        out.append({"id": s[0], "nom": s[1], "groupe": s[2], "note": s[6], "etat": e,
                    "action": _svc_action.get(s[0]) or ("allumer" if e == "en_cours" else None),
                    "erreur": _svc_erreur.get(s[0]), "ram_mo": ram_service(s)})
    if change or sorted(eteints()) != ETAT.get("eteints"):
        ETAT["eteints"] = sorted(eteints())
        for d in ("home", "admin"):
            if os.path.isdir(os.path.join(PAGES, d)):
                write_json(os.path.join(PAGES, d, "etat.json"), ETAT)
    return {"services": out}


def _executer(s, action):
    ident = s[0]
    try:
        for d in (reversed(s[3]) if action == "eteindre" else s[3]):
            f = os.path.join(BASE, d, "docker-compose.yml")
            args = ["docker", "compose", "-f", f] + (["stop"] if action == "eteindre" else ["up", "-d", "--no-recreate"])
            r = sh(args, 300)
            if r.returncode != 0:
                _svc_erreur[ident] = "Échec : " + (r.stderr.strip().splitlines() or ["code %d" % r.returncode])[-1][:160]
                break
        else:
            if action == "allumer":
                _svc_demarre[ident] = time.time()
    except Exception as e:
        _svc_erreur[ident] = "Échec : %s" % e
    finally:
        _ps["t"] = 0
        _docker["t"] = 0
        _svc_action.pop(ident, None)


def piloter(ident, action):
    s = SVC_ID.get(ident)
    if not s:
        return 404, {"erreur": "Service inconnu."}
    if action not in ("allumer", "eteindre"):
        return 400, {"erreur": "Action inconnue."}
    if ident in _svc_action:
        return 409, {"erreur": "Une opération est déjà en cours sur ce service."}
    if action == "eteindre" and ident in ("cloud", "docs") and sauvegarde_active():
        return 409, {"erreur": "Sauvegarde en cours : réessaie après."}
    _svc_erreur.pop(ident, None)
    _svc_action[ident] = action
    # éteint : noté AVANT l'arrêt (Kuma ne voit jamais de panne) ; allumé : retiré AVANT, un échec devient une vraie panne
    noter_eteint(ident, action == "eteindre")
    threading.Thread(target=_executer, args=(s, action), daemon=True).start()
    return 202, {"ok": True}


def sante(ident):
    s = SVC_ID.get(ident)
    if not s:
        return 404, {"erreur": "Service inconnu."}
    e = etat_service(s, frais=True)
    return (200 if e in ("marche", "eteint", "en_cours") else 503), {"id": ident, "etat": e}


# ---------------------------------------------------------------- serveur HTTP
class Handler(BaseHTTPRequestHandler):
    server_version = "homelab-api"

    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def est_admin(self):
        h = self.headers.get("Host", "").lower()
        return h.startswith(("admin.", "127.0.0.1", "localhost"))

    def refuse_admin(self):
        if self.est_admin():
            return False
        self.reply(403, {"erreur": "Réservé à admin.lan."})
        return True

    def do_GET(self):
        p, _, q = self.path.partition("?")
        if p == "/api/etat":
            return self.reply(200, ETAT)
        if p.startswith("/api/sante/"):
            return self.reply(*sante(p[len("/api/sante/"):]))
        if p in ("/api/systeme", "/api/sauvegarde", "/api/sauvegarde/journal", "/api/sauvegarde/direct", "/api/appareils", "/api/services"):
            if self.refuse_admin():
                return
            if p == "/api/systeme":
                return self.reply(200, systeme())
            if p == "/api/appareils":
                return self.reply(200, appareils())
            if p == "/api/services":
                return self.reply(200, services())
            if p == "/api/sauvegarde/journal":
                m = re.search(r"(?:^|&)id=([\w.-]{1,64})", q)
                return self.reply(*journal_execution(m.group(1) if m else ""))
            if p == "/api/sauvegarde/direct":
                return self.reply(*journal_direct())
            return self.reply(200, sauvegarde())
        self.reply(404, {"erreur": "Introuvable."})

    def do_POST(self):
        p = self.path.split("?")[0]
        if self.headers.get("X-Homelab") != "1":
            return self.reply(403, {"erreur": "Requête refusée."})
        n = int(self.headers.get("Content-Length") or 0)
        try:
            data = json.loads(self.rfile.read(min(n, 4096)) or b"{}")
        except ValueError:
            data = {}
        if p == "/api/appareil":
            if self.refuse_admin():
                return
            return self.reply(*basculer(str(data.get("id", ""))))
        if p == "/api/sauvegarde":
            if self.refuse_admin():
                return
            return self.reply(*lancer_sauvegarde())
        if p == "/api/service":
            if self.refuse_admin():
                return
            return self.reply(*piloter(str(data.get("id", "")), str(data.get("action", ""))))
        if p == "/api/tour/allumer":
            if self.refuse_admin():
                return
            return self.reply(*allumer_tour())
        if p == "/api/tour/eteindre":
            if self.refuse_admin():
                return
            return self.reply(*eteindre_tour())
        self.reply(404, {"erreur": "Introuvable."})


def main():
    os.makedirs(CONF, exist_ok=True)
    with _svc_lock:
        ecrire_conteneurs(eteints())
    for fn in (boucle_etat, boucle_cpu, boucle_ram):
        threading.Thread(target=fn, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
