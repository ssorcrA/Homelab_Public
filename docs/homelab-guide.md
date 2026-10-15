# Guide homelab : procédure complète

Tout tourne sur **ton portable** (Debian 13 + XFCE), allumé 24h/24, écran éteint, sans veille.
Tu y accèdes depuis ta **tour** (navigateur) avec des noms en `.lan`. La tour sert uniquement de **destination de sauvegarde** le samedi.

---

## 0. Vue d'ensemble

### Ce qui a été retiré ou remplacé

| Retiré / remplacé | Pourquoi |
|---|---|
| fail2ban | CrowdSec fait le même travail |
| Wazuh | Trop gourmand en RAM (4 à 8 Go) pour 16 Go partagés |
| Cockpit | Portainer + Beszel couvrent ses usages |
| Crafty Controller | Remplacé par Pelican Panel (tous les jeux, Minecraft compris) |
| BentoPDF | Doublon de Stirling PDF |
| Syncthing | Nextcloud fait déjà la synchro de fichiers, et c'est plus simple pour tes parents |
| Homepage | Remplacé par 2 pages HTML statiques servies par Caddy (0 Mo de RAM en plus) |
| Backrest | Remplacé par un script restic + timer systemd : plus fiable quand la tour est éteinte |
| Agent Beszel sur la tour | Tu surveilles seulement le portable, depuis ta tour |

### Services, noms et ports

Les noms `.lan` sont des propositions : tu peux les changer en modifiant seulement le `Caddyfile` (le DNS `*.lan` n'a pas à changer).

| Nom `.lan` | Service | Port interne | Pour qui |
|---|---|---|---|
| `home.lan` | Page d'accueil famille | statique | Tout le monde |
| `films.lan` | Jellyfin (films, séries) | 8096 | Famille |
| `musique.lan` | Navidrome | 4533 | Famille |
| `photos.lan` | Immich | 2283 | Famille |
| `cloud.lan` | Nextcloud | 8082 | Famille |
| `docs.lan` | Paperless-ngx | 8000 | Famille |
| `pdf.lan` | Stirling PDF | 8084 | Famille |
| `videos.lan` | MeTube | 8083 | Famille |
| `domotique.lan` | Home Assistant | 8123 | Famille / toi |
| `admin.lan` | Page d'accueil admin | statique | Toi |
| `dns.lan` | AdGuard Home | 3000 | Toi |
| `docker.lan` | Portainer | 9443 (https) | Toi |
| `status.lan` | Uptime Kuma | 3001 | Toi |
| `monitor.lan` | Beszel (ressources) | 8090 | Toi |
| `logs.lan` | Dozzle (logs Docker) | 8086 | Toi |
| `disque.lan` | Scrutiny (santé du disque) | 8087 | Toi |
| `notif.lan` | ntfy (notifications) | 8089 | Toi |
| `jeux.lan` | Pelican Panel | 8085 | Toi |
| `ia.lan` | Open WebUI (IA locale) | 8088 | Toi, à la demande |


### Ressources estimées (16 Go de RAM, sans en racheter)

| Bloc | RAM au repos |
|---|---|
| Debian + XFCE | ~1 Go |
| AdGuard, Caddy, Kuma, Beszel, Portainer, Dozzle, Diun, Scrutiny, ntfy, CrowdSec, Tailscale | ~1,2 Go |
| Jellyfin + Navidrome | ~0,7 Go |
| Immich (la RAM des modèles se libère après inactivité) | ~2,3 Go |
| Nextcloud + base de données | ~1 Go |
| Paperless-ngx | ~1 Go |
| Stirling PDF | ~0,7 Go |
| MeTube + Home Assistant | ~0,55 Go |
| Pelican (panel SQLite) + Wings | ~0,5 Go |
| **Total au repos** | **≈ 9 Go** |

Il reste donc **≈ 7 Go** pour un serveur de jeu ou l'IA, qui ne tournent que quand tu les lances. ARK seul peut tenir si tu arrêtes Immich, Nextcloud et Paperless le temps de jouer. Ce sont des ordres de grandeur : la vraie mesure viendra de Beszel.

### Électricité (estimation)

Au tarif réglementé, on est autour de 0,20 €/kWh TTC.

| Scénario | Puissance moyenne | Coût / an |
|---|---|---|
| Portable au repos, écran éteint | ~12 W | ~21 € |
| Usage normal | ~20 W | ~35 € |
| Serveur de jeu ou IA souvent sollicités | ~45 W | ~79 € |

Pour mesurer la vraie valeur : `sudo powertop` (onglet « Device stats ») ou une prise connectée avec compteur.

---

## 1. Préparer l'installation

1. **Sauvegarde** tout ce que tu veux garder du portable : l'installation efface Windows 11 et tout le disque.
2. Ton portable : **AMD Ryzen 7 5700U** (8 cœurs, 16 threads) avec **GPU Radeon intégré**, 16 Go de RAM, SSD NVMe. C'est un processeur très économe, idéal pour un serveur 24h/24. Le GPU intégré sert au transcodage de Jellyfin (VAAPI). Il n'est pas adapté à l'IA : l'IA locale tournera sur le processeur.
3. Télécharge l'ISO **Debian 13 netinst (amd64)** sur debian.org.
4. Avec **Rufus** (depuis ta tour), flashe l'ISO sur une clé USB de 8 Go minimum (schéma GPT, mode DD si demandé).
5. Branche le portable **en Ethernet** et sur secteur.
6. Redémarre et ouvre le menu de démarrage (F12, F2 ou Échap selon la marque) pour démarrer sur la clé.

Si le disque n'apparaît pas pendant l'installation, passe le mode SATA du BIOS de « RAID / Intel RST » à **AHCI**. Si ça ne démarre pas, désactive Secure Boot.

---

## 2. Installer Debian

1. Choisis **Install** (ou Graphical install).
2. Langue et clavier : français. Nom de la machine : `homelab`.
3. **Laisse le mot de passe root vide** et crée ton utilisateur : il aura `sudo`.
4. Partitionnement : **disque entier**, tout dans une seule partition.
5. Dans **Sélection des logiciels**, coche uniquement : **Xfce**, **serveur SSH**, **utilitaires usuels du système**. Décoche le reste.
6. Installe GRUB sur le disque principal, redémarre et retire la clé.

---

## 3. Base du système

Ouvre un terminal sur le bureau XFCE.

### Mises à jour et outils

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y curl wget git htop nano ca-certificates jq powertop restic cifs-utils
```

### Plus de veille, écran éteint seulement

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/; s/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
```

Dans XFCE : **Gestionnaire d'alimentation** → mise en veille système sur **Jamais**, extinction de l'écran sur 5 minutes par exemple.
Dans le BIOS, active le redémarrage automatique après coupure de courant (« AC Recovery » ou « Power on AC »), s'il existe.

### Mises à jour de sécurité automatiques

```bash
sudo apt install -y unattended-upgrades
sudo tee /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

Debian n'applique ainsi que les mises à jour de **sécurité**, sans redémarrage automatique. Redémarre le portable à la main environ une fois par mois (pour les mises à jour du noyau) : `sudo reboot`.

### Gagner de la RAM avec zram (RAM compressée)

```bash
sudo apt install -y systemd-zram-generator
sudo tee /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
swapon --show
```

`swapon --show` doit afficher un périphérique `/dev/zram0`.

### Pilotes du GPU Radeon (pour le transcodage de Jellyfin)

```bash
grep -E 'non-free-firmware' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null | head -3
sudo apt install -y firmware-amd-graphics mesa-va-drivers vainfo
sudo reboot
```

La première commande doit afficher au moins une ligne contenant `non-free-firmware`. Si elle ne renvoie rien, ajoute ce composant dans `/etc/apt/sources.list` (ou `/etc/apt/sources.list.d/debian.sources`, ligne `Components:` → `main non-free-firmware`), puis refais `sudo apt update` avant l'installation.

Après le redémarrage, vérifie que le GPU est utilisable :

```bash
ls /dev/dri
vainfo | head -15
```

Tu dois voir `renderD128` dans `/dev/dri`, et `vainfo` doit lister des profils comme `VAProfileH264` et `VAProfileHEVC`.

### Économie d'énergie et batterie (optionnel)

```bash
sudo apt install -y tlp
sudo systemctl enable --now tlp
```

Pour limiter la charge de la batterie à 80 % (marche seulement sur certains modèles, comme Lenovo/ThinkPad et quelques autres), édite `/etc/tlp.conf` : `START_CHARGE_THRESH_BAT0=75` et `STOP_CHARGE_THRESH_BAT0=80`, puis `sudo tlp start`.

---

## 4. Freebox : IP fixe (obligatoire)

1. Sur le portable, note le nom de l'interface Ethernet et son adresse MAC :
   ```bash
   ip -br link
   ip -4 a
   ```
2. Depuis ta tour, ouvre `http://mafreebox.freebox.fr` et connecte-toi (depuis un ordinateur, pas un mobile).
3. **Paramètres de la Freebox → Mode avancé → DHCP → onglet Baux statiques → Ajouter un bail DHCP statique.**
   - Choisis la MAC du portable (elle apparaît dans « Baux actifs »).
   - Choisis une IP **dans la plage DHCP** de la Freebox (le réseau Free est souvent en `192.168.0.x`). Note cette IP : c'est **`IP_PORTABLE`** dans tout le guide.
4. Redémarre le portable : `sudo reboot`, puis vérifie avec `ip -4 a` qu'il a bien l'IP choisie.
   Si ce n'est pas le cas, débranche puis rebranche le câble Ethernet.
5. Fais la même chose pour **ta tour** (bail statique). Note son IP : **`IP_TOUR`** (utile pour les sauvegardes).

### DNS du portable lui-même

Le portable ne doit **jamais** dépendre d'AdGuard (sinon, impossible de télécharger les images Docker si AdGuard est arrêté).

```bash
CON=$(nmcli -t -f NAME,TYPE con show --active | awk -F: '$2 ~ /ethernet/ {print $1; exit}')
echo "Connexion : $CON"
sudo nmcli con mod "$CON" ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1 9.9.9.9"
sudo nmcli con up "$CON"
```

Si la commande ne trouve pas de connexion, fais la même chose avec l'icône réseau de XFCE : clic droit → **Modifier les connexions** → ta connexion filaire → IPv4 → « Automatique (DHCP) adresses seulement » → DNS : `1.1.1.1, 9.9.9.9`.

---

## 5. Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Déconnecte-toi puis reconnecte-toi, et vérifie :

```bash
docker run --rm hello-world
mkdir -p ~/homelab
```

Tous les services vivent dans `~/homelab/<service>/` avec leur propre `docker-compose.yml`.

---

## 6. Tailscale (accès à distance, sans rien ouvrir sur la Freebox)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Ouvre le lien affiché, connecte-toi, puis installe Tailscale sur ta tour et ton téléphone avec le même compte.

À faire ensuite dans la console d'admin Tailscale (login.tailscale.com) :
- **Machines → portable → ⋯ → Disable key expiry** (sinon l'accès tombe au bout de quelques mois).
- Active la **double authentification sur le compte** que tu utilises pour te connecter à Tailscale (Google, Microsoft ou GitHub) : c'est la clé de tout l'accès à distance.
- Ne partage pas la machine avec tes parents si ce n'est pas nécessaire.


---

## 7. AdGuard Home (DNS anti-pubs + noms `.lan`)

Vérifie d'abord que le port 53 est libre (la commande ne doit rien afficher) :

```bash
sudo ss -tulpn | grep ':53 '
```

Puis :

```bash
mkdir -p ~/homelab/adguard && cd ~/homelab/adguard
cat > docker-compose.yml <<'EOF'
services:
  adguard:
    image: adguard/adguardhome
    container_name: adguard
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
    volumes:
      - ./work:/opt/adguardhome/work
      - ./conf:/opt/adguardhome/conf
EOF
docker compose up -d
```

1. Depuis ta tour, ouvre `http://IP_PORTABLE:3000`.
2. Dans l'assistant, **garde le port 3000 pour l'interface web** (le défaut est 80, qui est réservé à Caddy) et le port 53 pour le DNS. Crée ton compte admin avec un mot de passe long.
3. **Paramètres → Paramètres DNS** : serveurs amont `1.1.1.1` et `9.9.9.9`.
4. **Filtres → Blocklists DNS** : garde la liste AdGuard par défaut (tu peux en ajouter d'autres plus tard).
5. **Filtres → Réécritures DNS → Ajouter** :
   - Domaine : `*.lan`
   - Réponse : `IP_PORTABLE`

   Tous les noms en `.lan` pointent ainsi vers le portable, et c'est Caddy qui les envoie au bon service.

### Tester sur ta tour (avant de toucher à la Freebox)

1. Sur ta tour : **Paramètres → Réseau et Internet → Ethernet → Attribution du serveur DNS → Manuel** → IPv4 : DNS préféré `IP_PORTABLE`, DNS auxiliaire `1.1.1.1`.
2. Dans PowerShell :
   ```powershell
   ipconfig /flushdns
   nslookup photos.lan
   ```
   La réponse doit donner `IP_PORTABLE`.
3. Si les noms ne marchent pas dans le navigateur alors que `nslookup` fonctionne, désactive le **DNS sécurisé** du navigateur (Chrome/Edge : Confidentialité et sécurité → Sécurité → « Utiliser un DNS sécurisé » ; Firefox : Vie privée → Protection DNS over HTTPS), qui contourne ton DNS.

---

## 8. Caddy : les noms `.lan` et les pages d'accueil

Caddy écoute sur le port 80 et envoie chaque nom vers le bon service. Il sert aussi tes deux pages d'accueil (famille et admin), sans conteneur supplémentaire.

### 8.1 Caddy et les pages

> **Pages d'accueil** : les deux pages générées par le script ci-dessous sont la première version. Les pages définitives (tablette, télé, état du serveur, appareils) sont fournies sous forme de fichiers dans le dossier `pages-maison` et s'installent en **phase 20**. Tu peux donc te contenter ici d'une page simple.

```bash
mkdir -p ~/homelab/caddy/pages/{home,admin} && cd ~/homelab/caddy
cat > docker-compose.yml <<'EOF'
services:
  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./pages:/srv/pages:ro
      - ./data:/data
      - ./config:/config
EOF
```

Colle ensuite la fonction qui génère une page de liens, puis les deux pages :

```bash
page() {   # $1 = titre, $2 = sous-titre, stdin = lignes "emoji|nom|adresse|description"
  cat <<HTML
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$1</title>
<style>
:root{--bg:#f5f6f8;--card:#fff;--txt:#1b1f24;--mut:#667085;--acc:#3b6cf6;--bd:#e4e7ec}
@media (prefers-color-scheme:dark){:root{--bg:#0f1318;--card:#171c23;--txt:#e8ecf1;--mut:#9aa5b4;--acc:#7ea2ff;--bd:#27303a}}
*{box-sizing:border-box}
body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--txt);padding:2rem 1rem}
main{max-width:960px;margin:0 auto}
h1{margin:0 0 .25rem;font-size:1.8rem}
p.sub{margin:0 0 1.5rem;color:var(--mut)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:.9rem}
a.card{display:block;background:var(--card);border:1px solid var(--bd);border-radius:14px;padding:1rem;text-decoration:none;color:inherit;transition:transform .12s,border-color .12s}
a.card:hover{transform:translateY(-2px);border-color:var(--acc)}
.ico{font-size:1.6rem}
.nom{font-weight:600;margin-top:.4rem}
.desc{color:var(--mut);font-size:.88rem;margin-top:.15rem}
</style>
</head>
<body><main>
<h1>$1</h1><p class="sub">$2</p>
<div class="grid">
HTML
  while IFS='|' read -r ico nom url desc; do
    echo "<a class=\"card\" href=\"$url\"><div class=\"ico\">$ico</div><div class=\"nom\">$nom</div><div class=\"desc\">$desc</div></a>"
  done
  echo '</div></main></body></html>'
}

page "Maison" "Nos services à la maison" > pages/home/index.html <<'EOF'
🎬|Films et séries|http://films.lan|Jellyfin
🎵|Musique|http://musique.lan|Navidrome
📷|Photos|http://photos.lan|Immich
☁️|Cloud|http://cloud.lan|Nextcloud : fichiers et partage
📄|Documents|http://docs.lan|Paperless-ngx : papiers scannés
🧰|Outils PDF|http://pdf.lan|Stirling PDF
⬇️|Télécharger une vidéo|http://videos.lan|MeTube
🏠|Domotique|http://domotique.lan|Home Assistant
EOF

page "Administration" "Outils réservés à l'admin" > pages/admin/index.html <<'EOF'
🛡️|AdGuard Home|http://dns.lan|DNS anti-pubs
🐳|Portainer|http://docker.lan|Conteneurs Docker
🟢|Uptime Kuma|http://status.lan|Qui est en ligne
📈|Beszel|http://monitor.lan|CPU, RAM, disque
📜|Dozzle|http://logs.lan|Logs Docker
💽|Scrutiny|http://disque.lan|Santé du disque
🔔|ntfy|http://notif.lan|Notifications
🎮|Pelican|http://jeux.lan|Serveurs de jeu
🤖|IA locale|http://ia.lan|Open WebUI (à lancer avant)
🏡|Page famille|http://home.lan|Accueil des parents
EOF
```

### 8.2 Le Caddyfile (avec un mot de passe admin sur les outils sans login)

Dozzle, Scrutiny et la page admin n'ont pas de système de connexion : on y met un mot de passe dans Caddy. Les autres outils ont déjà leur propre login, donc pas de double saisie.

```bash
read -s -p "Mot de passe admin (Dozzle, Scrutiny, page admin) : " ADMINPW; echo
HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "$ADMINPW")
unset ADMINPW

cat > Caddyfile <<EOF
{
    auto_https off
}

(admin) {
    basic_auth {
        admin $HASH
    }
}

# --- Famille ---
http://home.lan {
    root * /srv/pages/home
    file_server
}
http://films.lan {
    reverse_proxy 127.0.0.1:8096
}
http://musique.lan {
    reverse_proxy 127.0.0.1:4533
}
http://photos.lan {
    reverse_proxy 127.0.0.1:2283
}
http://cloud.lan {
    reverse_proxy 127.0.0.1:8082
}
http://docs.lan {
    reverse_proxy 127.0.0.1:8000
}
http://pdf.lan {
    reverse_proxy 127.0.0.1:8084
}
http://videos.lan {
    reverse_proxy 127.0.0.1:8083
}
http://domotique.lan {
    reverse_proxy 127.0.0.1:8123
}

# --- Admin ---
http://admin.lan {
    import admin
    root * /srv/pages/admin
    file_server
}
http://dns.lan {
    reverse_proxy 127.0.0.1:3000
}
http://docker.lan {
    reverse_proxy https://127.0.0.1:9443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
http://status.lan {
    reverse_proxy 127.0.0.1:3001
}
http://monitor.lan {
    reverse_proxy 127.0.0.1:8090
}
http://logs.lan {
    import admin
    reverse_proxy 127.0.0.1:8086
}
http://disque.lan {
    import admin
    reverse_proxy 127.0.0.1:8087
}
http://notif.lan {
    reverse_proxy 127.0.0.1:8089
}
http://jeux.lan {
    reverse_proxy 127.0.0.1:8085
}
http://ia.lan {
    reverse_proxy 127.0.0.1:8088
}
EOF

docker compose up -d
docker compose logs --tail 20
```

Le nom d'utilisateur de la protection est `admin`, avec le mot de passe que tu viens de saisir.

> `jeux.lan` n'a **pas** de mot de passe Caddy : Pelican a son propre login (avec double authentification) et Wings doit pouvoir joindre le panel sans identifiants.

### 8.3 Tester

Sur le portable :
```bash
curl -sI -H "Host: home.lan" http://127.0.0.1/ | head -1
```
Tu dois voir `HTTP/1.1 200 OK`. Depuis ta tour (qui utilise ton DNS), ouvre `http://home.lan` : la page famille s'affiche. `http://admin.lan` demande ton mot de passe.

Pour modifier un nom ou une règle : édite `~/homelab/caddy/Caddyfile`, puis :
```bash
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### 8.4 Mettre la page en accueil du navigateur

- **Chrome / Edge** : Paramètres → « Au démarrage » → « Ouvrir une page ou un ensemble de pages spécifiques » → `http://home.lan` (ou `http://admin.lan` pour toi). Pour le bouton Accueil : Paramètres → Apparence → « Afficher le bouton Accueil ».
- **Firefox** : Paramètres → Accueil → « Page d'accueil et nouvelles fenêtres » → URL personnalisées → `http://home.lan`.
- **Téléphone** : ajoute `home.lan` à l'écran d'accueil (disponible seulement quand le DNS passe par AdGuard, voir phase 16).

Chrome et Firefox ne permettent pas de changer la page « nouvel onglet » sans extension : la page de démarrage et le bouton Accueil suffisent.

---

## 9. Supervision et maintenance

On commence par **ntfy** : c'est lui qui t'envoie les alertes sur ton téléphone, les autres outils s'y connectent.

### 9.1 ntfy (notifications)

```bash
mkdir -p ~/homelab/ntfy && cd ~/homelab/ntfy
cat > docker-compose.yml <<'EOF'
services:
  ntfy:
    image: binwiederhier/ntfy
    container_name: ntfy
    command: serve
    restart: unless-stopped
    environment:
      TZ: Europe/Paris
      NTFY_BASE_URL: http://notif.lan
      NTFY_CACHE_FILE: /var/cache/ntfy/cache.db
      NTFY_BEHIND_PROXY: "true"
    volumes:
      - ./cache:/var/cache/ntfy
    ports:
      - "8089:80"
EOF
docker compose up -d
curl -d "Test depuis le homelab" http://127.0.0.1:8089/homelab
```

> **Attention** : dans ntfy, les noms de sujets sont **sensibles à la casse**. Abonne-toi à `homelab` en minuscules (pas `Homelab`), sinon tu ne verras pas les alertes. Le port de ntfy est **8089** (celui de Beszel est 8090 : ne les confonds pas).

Sur ton téléphone (facultatif : tu peux aussi garder ntfy seulement sur tes deux PC) : installe l'appli **ntfy**, ajoute un serveur `http://IP_PORTABLE:8089` (à la maison) et abonne-toi au sujet `homelab`. Hors de chez toi, utilise l'IP Tailscale du portable (`tailscale ip -4`).
Sur iPhone, les notifications instantanées demandent d'ajouter `NTFY_UPSTREAM_BASE_URL: https://ntfy.sh` dans les variables d'environnement ci-dessus.

### 9.2 Portainer (gestion de Docker)

```bash
mkdir -p ~/homelab/portainer && cd ~/homelab/portainer
cat > docker-compose.yml <<'EOF'
services:
  portainer:
    image: portainer/portainer-ce
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/data
EOF
docker compose up -d
```

Ouvre `https://IP_PORTABLE:9443` (**`https://`**, pas `http://`, et accepte l'alerte de certificat) et **crée tout de suite ton compte admin** : sinon Portainer se verrouille au bout de 5 minutes.

Les versions récentes demandent un **jeton d'installation** (« Setup token »), affiché dans les logs :
```bash
sg docker -c "docker logs portainer 2>&1 | grep setup_token | tail -1"
```
Colle la valeur après `setup_token=`, avec un mot de passe d'au moins 12 caractères (utilise l'icône œil pour vérifier ce que tu tapes). Si le formulaire affiche une erreur ou « timed out », redémarre avec `docker restart portainer`, **récupère le nouveau jeton** (il change à chaque démarrage) et recommence. Passe l'écran « Edge Compute » avec **Skip**. Si tu n'arrives plus à te connecter et que Portainer est vide, le plus simple est de repartir à zéro : `docker compose down`, `sudo rm -rf ./data`, `docker compose up -d`, puis refaire la création du compte.

### 9.3 Uptime Kuma (qui est en ligne)

Kuma tourne en réseau « host » pour surveiller les services via `127.0.0.1`, même quand on durcira les ports plus tard.

```bash
mkdir -p ~/homelab/kuma && cd ~/homelab/kuma
cat > docker-compose.yml <<'EOF'
services:
  kuma:
    image: louislam/uptime-kuma:latest
    container_name: kuma
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data:/app/data
EOF
docker compose up -d
```

Ouvre `http://IP_PORTABLE:3001`, crée ton compte admin, puis :

1. **Paramètres → Notifications → Configurer une notification** : type **ntfy**, serveur `http://127.0.0.1:8089`, sujet `homelab`, coche « Par défaut » et « Appliquer sur tous les moniteurs existants ».
2. Ajoute ces moniteurs (type **HTTP(s)**, sauf indication) :

| Moniteur | Adresse à surveiller |
|---|---|
| AdGuard (interface) | `http://127.0.0.1:3000` |
| AdGuard (DNS) | type **DNS**, résolveur `127.0.0.1`, port 53, domaine `example.com` |
| Jellyfin | `http://127.0.0.1:8096/health` |
| Navidrome | `http://127.0.0.1:4533/ping` |
| Immich | `http://127.0.0.1:2283/api/server/ping` |
| Nextcloud | `http://127.0.0.1:8082/status.php` |
| Paperless | `http://127.0.0.1:8000` |
| Stirling PDF | `http://127.0.0.1:8084` |
| MeTube | `http://127.0.0.1:8083` |
| Home Assistant | `http://127.0.0.1:8123` |
| Pelican | `http://127.0.0.1:8085` |
| Caddy | `http://127.0.0.1` (accepte le code 404 si tu veux) |

Tu peux les ajouter au fur et à mesure que les services sont installés.

### 9.4 Beszel (CPU, RAM, disque, conteneurs, depuis ta tour)

Le « hub » est l'interface, l'« agent » tourne sur le portable pour lui envoyer ses mesures.

```bash
mkdir -p ~/homelab/beszel && cd ~/homelab/beszel
cat > docker-compose.yml <<'EOF'
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: beszel
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - ./beszel_data:/beszel_data
EOF
docker compose up -d
```

1. Ouvre `http://IP_PORTABLE:8090` et crée ton compte admin.
2. Clique sur **Add System** : nom `homelab`, **Host / IP** = `IP_PORTABLE`, **port** `45876`. Le hub affiche une **clé publique** : copie-la (ne ferme pas la fenêtre).
3. Dans un terminal du portable, lance l'agent avec cette clé :

```bash
mkdir -p ~/homelab/beszel-agent && cd ~/homelab/beszel-agent
read -r -p "Colle la clé publique Beszel : " BKEY
cat > docker-compose.yml <<EOF
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      PORT: 45876
      KEY: "$BKEY"
EOF
docker compose up -d
```

4. Retourne sur le hub et clique sur **Add System** pour valider : le portable apparaît avec ses courbes.
5. Dans les réglages d'alertes de la machine, active les alertes sur le **statut (down)**, le **CPU**, la **RAM**, le **disque** et la **température**. Ajoute une notification dans **Settings → Notifications** avec l'URL `ntfy://IP_PORTABLE:8089/homelab?scheme=http`, puis utilise le bouton de test pour vérifier que ton téléphone reçoit le message.

### 9.5 Dozzle (logs Docker en direct)

```bash
mkdir -p ~/homelab/dozzle && cd ~/homelab/dozzle
cat > docker-compose.yml <<'EOF'
services:
  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    environment:
      DOZZLE_NO_ANALYTICS: "true"
    ports:
      - "8086:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOF
docker compose up -d
```

Accessible sur `http://logs.lan` (mot de passe admin Caddy).

### 9.6 Scrutiny (santé du disque)

```bash
mkdir -p ~/homelab/scrutiny && cd ~/homelab/scrutiny
DISK=$(lsblk -dno NAME,TYPE | awk '$2=="disk" {print $1; exit}')
echo "Disque détecté : /dev/$DISK"
cat > docker-compose.yml <<EOF
services:
  scrutiny:
    image: ghcr.io/analogj/scrutiny:master-omnibus
    container_name: scrutiny
    restart: unless-stopped
    cap_add:
      - SYS_RAWIO
      - SYS_ADMIN
    ports:
      - "8087:8080"
    volumes:
      - /run/udev:/run/udev:ro
      - ./config:/opt/scrutiny/config
      - ./influxdb:/opt/scrutiny/influxdb
    devices:
      - /dev/$DISK:/dev/$DISK
EOF
docker compose up -d
sleep 20
docker exec scrutiny /opt/scrutiny/bin/scrutiny-collector-metrics run
```

Accessible sur `http://disque.lan` (mot de passe admin Caddy). La dernière commande lance la première collecte ; ensuite, Scrutiny relit les données SMART tout seul chaque jour.

### 9.7 Diun (prévient quand une image Docker a une nouvelle version)

Diun ne met **rien à jour tout seul** : il te prévient, et tu mets à jour quand tu veux.

```bash
mkdir -p ~/homelab/diun && cd ~/homelab/diun
cat > docker-compose.yml <<'EOF'
services:
  diun:
    image: crazymax/diun:latest
    container_name: diun
    command: serve
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      TZ: Europe/Paris
      LOG_LEVEL: info
      DIUN_WATCH_WORKERS: "10"
      DIUN_WATCH_SCHEDULE: "0 9 * * 0"
      DIUN_WATCH_JITTER: 30s
      DIUN_PROVIDERS_DOCKER: "true"
      DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT: "true"
      DIUN_NOTIF_NTFY_ENDPOINT: http://127.0.0.1:8089
      DIUN_NOTIF_NTFY_TOPIC: homelab
EOF
docker compose up -d
```

Il vérifie chaque dimanche à 9h et t'envoie une notification pour chaque image qui a une nouvelle version.

**Pour mettre à jour un service** (exemple Jellyfin) :
```bash
cd ~/homelab/jellyfin && docker compose pull && docker compose up -d
```
Fais une sauvegarde avant les mises à jour majeures d'Immich, Nextcloud et Paperless, et lis leurs notes de version.


---

## Règles communes aux phases 10 à 19

- **Les nouveaux services écoutent seulement sur `127.0.0.1`** (ligne `127.0.0.1:PORT:PORT` dans les `docker-compose.yml`). Ils ne sont donc accessibles que par Caddy, via leur nom `.lan` : `http://films.lan`, `http://photos.lan`, etc. Pour la première configuration, ouvre ces noms **depuis ta tour** (le DNS y est déjà réglé). Sur le portable, les noms `.lan` ne marchent que si tu as appliqué la correction DNS (`nmcli … ipv4.dns "192.168.1.199 1.1.1.1"`).
- **Les mots de passe ne passent jamais par Claude Code.** Quand une étape demande un mot de passe (compte admin, base de données, clé de chiffrement), c'est toi qui le saisis dans ton navigateur ou ton terminal. Les mots de passe techniques de bases de données sont générés automatiquement dans un fichier `.env` (droits `600`), que personne n'a besoin de lire.
- **Une étape à la fois, une vérification à la fin de chaque phase**, avec le moniteur Uptime Kuma correspondant (tableau de la phase 9.3).
- **Dossiers de données** : chaque service a son dossier `~/homelab/<service>/`, et les médias sont dans `~/media/` (créé en phase 10).
- Avant de lancer un service lourd, regarde la RAM dans Beszel (`monitor.lan`). Si le portable dépasse **85 % de RAM**, n'ajoute rien d'autre avant d'avoir compris pourquoi.
- **Colle les commandes avec `Ctrl+Maj+V`, une par une, et relis la ligne avant d'appuyer sur Entrée.** Si tu vois `^[[200~` au début d'une ligne, efface et recolle : la commande est cassée. Ne colle **jamais plusieurs commandes d'un coup** quand l'une d'elles pose une question (mot de passe, confirmation) : les lignes suivantes seraient prises pour la réponse.
- **Quand Claude Code a la main dans une fenêtre de terminal**, ouvre un **autre onglet** (`Ctrl+Maj+T`) pour tes propres commandes `sudo`, et reviens à Claude Code avec un clic sur son onglet.
- **Un `ls` qui ne répond rien ne prouve pas qu'un partage est monté.** Vérifie toujours avec `findmnt` (voir 17.2).

---

## 10. Médias : Jellyfin (films, séries) et Navidrome (musique)

### 10.1 Dossiers de médias

```bash
mkdir -p ~/media/{films,series,musique,vod,cuisine,tutos,documentaires,enfants,concerts,podcasts,a-trier}
ls -ld ~/media/*
```

Copie ensuite tes films, séries et musiques dedans (par exemple depuis ta tour avec le partage réseau, une clé USB, ou Nextcloud plus tard). Range-les ainsi, ça aide la reconnaissance automatique :

- Films : `~/media/films/Nom du film (2019)/Nom du film (2019).mkv`
- Séries : `~/media/series/Nom de la série/Saison 01/Nom de la série S01E01.mkv`
- Musique : `~/media/musique/Artiste/Album/01 - Titre.flac`

### 10.2 Jellyfin

```bash
mkdir -p ~/homelab/jellyfin && cd ~/homelab/jellyfin
VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3)
cat > docker-compose.yml <<EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    user: "$(id -u):$(id -g)"
    group_add:
      - "$VIDEO_GID"
      - "$RENDER_GID"
    devices:
      - /dev/dri:/dev/dri
    ports:
      - "127.0.0.1:8096:8096"
    environment:
      TZ: Europe/Paris
    volumes:
      - ./config:/config
      - ./cache:/cache
      - $HOME/media:/media:ro
EOF
docker compose up -d
sleep 15
docker compose logs --tail 15
```

Ouvre `http://films.lan` (depuis la tour) et suis l'assistant :

1. Langue : français. **Crée ton compte admin** (mot de passe long).
2. Ajoute les bibliothèques : « Films » → dossier `/media/films`, « Séries » → dossier `/media/series`. Langue des métadonnées : français.
3. Termine l'assistant, puis va dans **Tableau de bord → Lecture → Transcodage** :
   - Accélération matérielle : **VAAPI**.
   - Périphérique VA-API : `/dev/dri/renderD128`.
   - Coche le décodage matériel pour **H264**, **HEVC** et **VP9**. Ne coche pas AV1 (ton GPU ne sait pas le décoder).
   - Coche « Activer l'encodage matériel » et sauvegarde.
4. **Crée les comptes de la famille** : Tableau de bord → Utilisateurs → Ajouter. Un compte par personne, sans droits d'administration. Chacun choisit son mot de passe à sa première connexion.
5. Vérifie : lance un film sur ton téléphone avec une qualité réduite (pour forcer le transcodage). Dans Tableau de bord → Activité, la ligne de lecture doit afficher « Transcodage (HW) » ou, avec Beszel, un CPU qui reste bas.

Applications : Jellyfin (Android, iOS, Android TV, Fire TV, Samsung/LG selon les modèles) avec l'adresse `http://films.lan`.

### 10.3 Navidrome

```bash
mkdir -p ~/homelab/navidrome && cd ~/homelab/navidrome
cat > docker-compose.yml <<EOF
services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: unless-stopped
    user: "$(id -u):$(id -g)"
    ports:
      - "127.0.0.1:4533:4533"
    environment:
      TZ: Europe/Paris
      ND_LOGLEVEL: info
      ND_SCANSCHEDULE: 1h
      ND_SESSIONTIMEOUT: 24h
    volumes:
      - ./data:/data
      - $HOME/media/musique:/music:ro
EOF
docker compose up -d
sleep 10
docker compose logs --tail 10
```

Ouvre `http://musique.lan` : **le premier compte créé devient administrateur**. Crée le tien tout de suite, puis ajoute les comptes de ta famille dans Paramètres → Utilisateurs.

Applications compatibles (protocole Subsonic) : **Symfonium** (Android, payant), **Substreamer** ou **Ultrasonic** (Android), **Amperfy** ou **Substreamer** (iOS). Serveur : `http://musique.lan`.

### 10.4 Vérifier

- `http://films.lan` et `http://musique.lan` s'affichent depuis la tour.
- Dans Uptime Kuma, ajoute les moniteurs Jellyfin et Navidrome (tableau 9.3).
- Dans Beszel, vérifie que la RAM a augmenté d'environ 0,7 Go.

---

## 11. Immich (photos et vidéos)

Immich change souvent. On utilise donc **les fichiers officiels** de la dernière version, plutôt qu'une copie qui deviendrait vite fausse.

```bash
mkdir -p ~/homelab/immich && cd ~/homelab/immich
wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
wget -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
```

Édite ensuite le fichier `.env` avec ces valeurs :

```bash
sed -i "s|^UPLOAD_LOCATION=.*|UPLOAD_LOCATION=./library|" .env
sed -i "s|^DB_DATA_LOCATION=.*|DB_DATA_LOCATION=./postgres|" .env
sed -i "s|^# TZ=.*|TZ=Europe/Paris|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -hex 20)|" .env
chmod 600 .env
grep -vi password .env
```

Dans `docker-compose.yml`, change la ligne qui publie le port 2283 pour qu'elle n'écoute que sur `127.0.0.1` :

```bash
grep -n "2283" docker-compose.yml
```
La ligne ressemble à `- '2283:2283'` : remplace-la par `- '127.0.0.1:2283:2283'` (avec `nano docker-compose.yml`). Vérifie que le fichier ne contient rien d'autre à changer (les sections `hwaccel`, `extends` et `deploy` restent commentées ou ignorées : il n'y a pas d'accélération d'apprentissage sur ton GPU).

Lance, puis surveille :

```bash
docker compose up -d
sleep 30
docker compose ps
docker compose logs --tail 15 immich-server
```

Les quatre conteneurs doivent être « Up » (`immich_server`, `immich_machine_learning`, `immich_redis`, `immich_postgres`). Le premier démarrage peut prendre 1 à 2 minutes.

### Configuration dans le navigateur (`http://photos.lan`)

1. Clique sur « Démarrer » : **crée ton compte administrateur** (le premier compte l'est automatiquement).
2. **Administration → Paramètres → Tâches** : mets la **concurrence** de chaque tâche à `1` ou `2`. Sans cela, l'analyse initiale de milliers de photos peut saturer tout le processeur pendant des heures.
3. **Administration → Paramètres → Sauvegarde de la base de données** : vérifie que la sauvegarde quotidienne est active. Elle écrit dans `library/backups/`, que la phase 17 sauvegarde.
4. **Administration → Utilisateurs** : crée un compte pour chaque membre de ta famille. Chacun peut ensuite définir son mot de passe.
5. **Application mobile** (Immich, Android et iOS) : serveur `http://photos.lan`, connexion avec ton compte, puis active la **sauvegarde automatique** des photos de l'album souhaité. Hors de chez toi, il faut Tailscale (phase 16).

### Import de tes photos existantes

- Depuis l'appli mobile : sauvegarde de l'album de l'appareil.
- Depuis ta tour : installe `immich-go` ou utilise l'import web (« Envoyer » en haut à droite). Un gros import se fait la nuit, une fois la concurrence réduite.

La RAM du module d'apprentissage se libère après quelques minutes d'inactivité. Ajoute le moniteur Uptime Kuma d'Immich.

---

## 12. Nextcloud (fichiers et synchronisation) et Paperless-ngx (documents)

### 12.1 Nextcloud

```bash
mkdir -p ~/homelab/nextcloud && cd ~/homelab/nextcloud
cat > .env <<EOF
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 20)
MYSQL_PASSWORD=$(openssl rand -hex 20)
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
EOF
chmod 600 .env
cat > docker-compose.yml <<'EOF'
services:
  nextcloud-db:
    image: mariadb:11.4
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    env_file: .env
    volumes:
      - ./db:/var/lib/mysql

  nextcloud-redis:
    image: redis:7-alpine
    container_name: nextcloud-redis
    restart: unless-stopped

  nextcloud:
    image: nextcloud:apache
    container_name: nextcloud
    restart: unless-stopped
    depends_on:
      - nextcloud-db
      - nextcloud-redis
    ports:
      - "127.0.0.1:8082:80"
    env_file: .env
    environment:
      MYSQL_HOST: nextcloud-db
      REDIS_HOST: nextcloud-redis
      NEXTCLOUD_TRUSTED_DOMAINS: "cloud.lan 192.168.1.199 100.64.0.10"
      OVERWRITEPROTOCOL: http
      TRUSTED_PROXIES: "172.16.0.0/12 127.0.0.1"
      PHP_MEMORY_LIMIT: 1G
      PHP_UPLOAD_LIMIT: 16G
      APACHE_DISABLE_REWRITE_IP: "1"
      TZ: Europe/Paris
    volumes:
      - ./html:/var/www/html
      - ./data:/var/www/html/data

  nextcloud-cron:
    image: nextcloud:apache
    container_name: nextcloud-cron
    restart: unless-stopped
    depends_on:
      - nextcloud
    entrypoint: /cron.sh
    volumes:
      - ./html:/var/www/html
      - ./data:/var/www/html/data
EOF
docker compose up -d
sleep 30
docker compose ps
```

Ouvre `http://cloud.lan`. L'assistant d'installation apparaît, avec la base de données déjà préremplie :

1. **Crée ton compte administrateur** (nom différent de `admin`, mot de passe long).
2. Les champs de la base de données sont déjà remplis par les variables : ne les change pas. Décoche « Installer les applications recommandées » si tu veux un Nextcloud léger.
3. L'installation dure 1 à 3 minutes.

Réglages à faire ensuite (dans un terminal) :

```bash
cd ~/homelab/nextcloud
docker exec -u www-data nextcloud php occ config:system:set default_phone_region --value=FR
docker exec -u www-data nextcloud php occ background:cron
docker exec -u www-data nextcloud php occ maintenance:repair --include-expensive
```

Dans le navigateur :

- **Paramètres administration → Vue d'ensemble** : lis les avertissements. Les messages sur « HTTPS » ou « en-têtes » sont normaux, car tu es en réseau local sans HTTPS.
- **Applications** : active **Two-Factor TOTP** (double authentification), puis **Paramètres personnels → Sécurité** : active-la pour ton compte.
- **Comptes → Nouveau compte** : un compte par membre de la famille, sans droits d'administrateur.
- Applications de synchronisation : Nextcloud (Windows, Mac, Android, iOS), avec le serveur `http://cloud.lan`.

Pour que les agendas et contacts se retrouvent automatiquement dans les clients, remplace dans `~/homelab/caddy/Caddyfile` le bloc `cloud.lan` par :

```
http://cloud.lan {
    redir /.well-known/carddav /remote.php/dav 301
    redir /.well-known/caldav /remote.php/dav 301
    request_body {
        max_size 16GB
    }
    reverse_proxy 127.0.0.1:8082
}
```
puis : `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`.

### 12.2 Paperless-ngx

On utilise la base **SQLite** (par défaut) pour économiser un conteneur et de la RAM.

```bash
mkdir -p ~/homelab/paperless/{data,media,export,consume,redis} && cd ~/homelab/paperless
cat > .env <<EOF
PAPERLESS_URL=http://docs.lan
PAPERLESS_SECRET_KEY=$(openssl rand -hex 32)
PAPERLESS_TIME_ZONE=Europe/Paris
PAPERLESS_OCR_LANGUAGE=fra+eng
PAPERLESS_TASK_WORKERS=1
PAPERLESS_THREADS_PER_WORKER=2
PAPERLESS_CONSUMER_RECURSIVE=true
USERMAP_UID=$(id -u)
USERMAP_GID=$(id -g)
EOF
chmod 600 .env
cat > docker-compose.yml <<'EOF'
services:
  paperless-broker:
    image: docker.io/library/redis:8
    container_name: paperless-broker
    restart: unless-stopped
    volumes:
      - ./redis:/data

  paperless:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: paperless
    restart: unless-stopped
    depends_on:
      - paperless-broker
    ports:
      - "127.0.0.1:8000:8000"
    env_file: .env
    environment:
      PAPERLESS_REDIS: redis://paperless-broker:6379
    volumes:
      - ./data:/usr/src/paperless/data
      - ./media:/usr/src/paperless/media
      - ./export:/usr/src/paperless/export
      - ./consume:/usr/src/paperless/consume
EOF
docker compose up -d
sleep 40
docker compose logs --tail 10 paperless
```

Crée ton compte administrateur **toi-même** (le script te demande le mot de passe) :

```bash
cd ~/homelab/paperless
docker compose exec paperless python3 manage.py createsuperuser
```

Ouvre `http://docs.lan` et connecte-toi. Puis :

1. **Utilisateurs & groupes** : un compte par membre de la famille. Donne-leur les droits de **voir, ajouter et modifier** des documents, pas ceux de l'administration.
2. Dépose un PDF dans `~/homelab/paperless/consume/` : il est analysé (OCR) et apparaît après quelques minutes.
3. Active la double authentification sur ton compte (menu utilisateur → Mon profil).

Ajoute les moniteurs Uptime Kuma de Nextcloud et de Paperless.

---

## 13. Outils : Stirling PDF, MeTube, Home Assistant

### 13.1 Stirling PDF

```bash
mkdir -p ~/homelab/stirling && cd ~/homelab/stirling
cat > docker-compose.yml <<'EOF'
services:
  stirling:
    image: stirlingtools/stirling-pdf:latest
    container_name: stirling
    restart: unless-stopped
    mem_limit: 1g
    ports:
      - "127.0.0.1:8084:8080"
    environment:
      DISABLE_ADDITIONAL_FEATURES: "true"
      SECURITY_ENABLELOGIN: "false"
      LANGS: fr_FR
      SYSTEM_DEFAULTLOCALE: fr-FR
    volumes:
      - ./tessdata:/usr/share/tessdata
      - ./config:/configs
EOF
docker compose up -d
sleep 30
docker compose logs --tail 10
```

Accessible sur `http://pdf.lan`, sans compte (pratique pour la famille). Il ne conserve pas les fichiers que tu traites.

### 13.2 MeTube (téléchargement de vidéos)

N'utilise MeTube que pour des contenus que tu as le droit de télécharger.

```bash
mkdir -p ~/homelab/metube/state && cd ~/homelab/metube
cat > docker-compose.yml <<EOF
services:
  metube:
    image: ghcr.io/alexta69/metube:latest
    container_name: metube
    restart: unless-stopped
    user: "$(id -u):$(id -g)"
    ports:
      - "127.0.0.1:8083:8081"
    environment:
      DOWNLOAD_DIR: /downloads
      AUDIO_DOWNLOAD_DIR: /downloads/musique
      STATE_DIR: /state
      TEMP_DIR: /state/tmp
      CUSTOM_DIRS: "true"
      CREATE_CUSTOM_DIRS: "true"
    volumes:
      - $HOME/media:/downloads
      - ./state:/state
EOF
docker compose up -d
```

Accessible sur `http://videos.lan` : colle un lien, **choisis le dossier** dans la case « Dossier » (`vod`, `cuisine`, `tutos`…), puis valide. La vidéo arrive dans `~/media/<dossier>`. Pour qu'elle apparaisse dans Jellyfin, crée une bibliothèque par dossier (voir **phase 22**, qui détaille aussi les dossiers).

### 13.3 Home Assistant (domotique)

```bash
mkdir -p ~/homelab/homeassistant/config && cd ~/homelab/homeassistant
cat > docker-compose.yml <<'EOF'
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    restart: unless-stopped
    network_mode: host
    environment:
      TZ: Europe/Paris
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
EOF
docker compose up -d
sleep 60
ls config | head
```

Home Assistant utilise le réseau « host » pour découvrir tes appareils (prises, ampoules, enceintes). On y accède par `http://domotique.lan`.

Pour qu'il accepte Caddy, ajoute **à la fin** de `~/homelab/homeassistant/config/configuration.yaml` :

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - ::1
```
puis `docker restart homeassistant`.

Ouvre `http://domotique.lan` : **crée ton compte propriétaire**, donne ta position et active la double authentification (profil → Sécurité → Authentification multifacteur). Les appareils détectés apparaissent dans « Découverts » (Paramètres → Appareils et services).

---

## 14. Pelican Panel + Wings (serveurs de jeux, allumés à la demande)

Pelican remplace Crafty Controller : un seul outil pour Minecraft, ARK, Valheim, Palworld, etc. Le **panel** est l'interface web. **Wings** est le programme qui lance les serveurs de jeux dans des conteneurs. Un serveur de jeu ne consomme de la RAM **que lorsqu'il est démarré** : le bouton **Start / Stop** du panel est ton bouton marche/arrêt.

> Pelican évolue vite. **Avant de lancer les commandes, lis la page d'installation officielle** (`pelican.dev/docs`, rubriques « Panel » puis « Wings ») et compare avec ce qui suit. Si une variable ou une commande a changé, suis la documentation officielle et garde les contraintes de ce guide : port 8085 sur `127.0.0.1`, adresse `http://jeux.lan`, base SQLite, Wings sur le port 8081.

### 14.1 Le panel

```bash
mkdir -p ~/homelab/pelican && cd ~/homelab/pelican
cat > docker-compose.yml <<'EOF'
services:
  panel:
    image: ghcr.io/pelican-dev/panel:latest
    container_name: pelican-panel
    restart: unless-stopped
    ports:
      - "127.0.0.1:8085:80"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      XDG_DATA_HOME: /pelican-data
      APP_URL: "http://jeux.lan"
      TZ: Europe/Paris
    volumes:
      - ./data:/pelican-data
      - ./logs:/var/www/html/storage/logs
EOF
docker compose up -d
sleep 30
docker compose logs --tail 15
```

Ouvre **`http://jeux.lan/installer`** (depuis la tour) et suis l'assistant :

1. Base de données : **SQLite**. Cache et sessions : le choix par défaut (fichiers).
2. **Crée ton compte administrateur** (e-mail et mot de passe long). Retiens ce compte : seul toi t'en sers.
3. Une fois terminé, connecte-toi sur `http://jeux.lan`.
4. **Profil (en haut à droite) → Sécurité → Authentification à deux facteurs** : active-la.

### 14.2 Wings (le moteur des serveurs de jeux)

Wings se lance directement sur la machine (pas dans un conteneur) :

```bash
sudo mkdir -p /etc/pelican /var/run/wings /var/lib/pelican
sudo curl -L -o /usr/local/bin/wings "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_amd64"
sudo chmod +x /usr/local/bin/wings
sudo /usr/local/bin/wings version
```

(La commande est `wings version`, sans tirets : `--version` n'existe pas et affiche une erreur. Lance-la avec `sudo` : si le binaire n'a pas les droits d'exécution pour tout le monde, tu obtiens « Permission non accordée ».)

Crée le **nœud** dans le panel :

1. **Administration → Nœuds → Créer un nœud**.
2. Nom : `homelab`. **FQDN : `192.168.1.199`**. Communication : **HTTP** (sans SSL), car tu es en réseau local. Port Wings : `8081`. Port SFTP : `2022`.
   Le **port est à `8080` par défaut** dans le formulaire : change-le en `8081` (8080 est déjà pris).
3. Page **Advanced Settings** : mets **Memory Limit = 10240 Mio** (10 Go), **Disk = Limited, 200000 Mio** (200 Go), et **Overallocate à `0 %`** pour la mémoire et le CPU (par défaut 75 % et 50 %). Laisse le CPU limité à 75 %. Le port SFTP reste à `2022`.
4. Une fois le nœud créé, ouvre-le, onglet **Configuration File**, et clique sur le bouton bleu **Auto Deploy Command**. Une fenêtre affiche la commande `sudo wings configure --panel-url … --token … --node 1 --allow-insecure` avec un **jeton d'API temporaire**. Copie-la et colle-la **à l'invite normale du terminal** (`alex@Homelab:~$`), pas dans un assistant en cours.
   - **Ne copie pas** les lignes `token_id` et `token` affichées dans le fichier de configuration à l'écran : ce sont les identifiants de Wings, pas le jeton demandé. Wings répond « please provide a valid authentication token ».
   - Si tu as lancé `wings configure` sans arguments, il pose des questions (« Panel URL », « API Token ») : fais `Ctrl+C` et relance avec la commande complète du bouton.
   - Cette commande contient un jeton secret : ne la partage pas, et efface l'écran avec `clear` ensuite. Si le jeton a été visible sur une capture, clique sur **Reset Authorization Token** puis recommence avec **Auto Deploy Command**.
   - Elle doit répondre **`Successfully configured wings.`**
5. Vérifie dans `/etc/pelican/config.yml` que le port d'API est bien `8081` (clé `api.port`). S'il est à `8080`, change-le et mets la même valeur dans le nœud du panel.

Crée le service pour que Wings démarre avec le portable :

```bash
sudo tee /etc/systemd/system/wings.service > /dev/null <<'EOF'
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wings
sleep 5
sudo systemctl status wings --no-pager | head -12
```

> **Piège rencontré : conflit de réseau Docker.** Wings crée son propre réseau Docker (`pelican_nw`), par défaut en `172.18.0.0/16`. Si ce réseau est déjà pris par un autre service (par exemple AdGuard), Wings refuse de démarrer. Le plus simple est de **créer le réseau avant le premier démarrage** sur une plage libre : `docker network create --subnet 10.250.0.0/16 pelican_nw`, et de mettre la même plage dans `/etc/pelican/config.yml` (section `docker.network`). Vérifie les plages déjà utilisées avec `docker network inspect $(docker network ls -q) --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}'`.
>
> **Piège rencontré : droits des dossiers du panel.** Le panel tourne avec l'utilisateur `www-data` (uid 82). Si les dossiers `data` et `logs` ont été créés par Docker au nom de `root`, le panel redémarre en boucle. Corrige-le avec `sudo chown -R 82:82 ~/homelab/pelican/data ~/homelab/pelican/logs`.

Dans le panel, le nœud doit afficher un **cœur vert** (« en ligne »). Wings au repos consomme très peu de RAM.

### 14.3 Créer un premier serveur (exemple Minecraft)

1. **Administration → Serveurs → Créer un serveur**. Nœud : `homelab`.
2. **Allocation** : adresse `192.168.1.199`, port `25565` (à créer dans les allocations du nœud si besoin).
3. **Limites** : **mémoire 4 Go**, CPU 300 %, disque 20 Go. **C'est la protection de ton portable** : le serveur ne pourra jamais dépasser ces limites.
4. Choisis l'œuf (Minecraft Java, Paper) et la version, puis valide. L'installation se déroule dans le panel.
5. Dans l'interface du serveur : **Console → Start**. Pour éteindre : **Stop**.

Ne mets **pas** les serveurs en démarrage automatique : ils doivent rester éteints tant que tu n'appuies pas sur Start.

### 14.4 Jouer avec des amis

Pour des amis qui ne sont pas chez toi, préfère un accès par ton VPN (par exemple en partageant la machine dans Tailscale) à une redirection de port dans la box.

### 14.5 Le « mode jeu » : libérer de la RAM avant un gros serveur

Un serveur comme ARK a besoin de 8 Go ou plus. Pour que le portable ne sature pas, ce script arrête les services lourds avant la partie et les relance ensuite.

```bash
mkdir -p ~/homelab/bin
cat > ~/homelab/bin/mode-jeu.sh <<'EOF'
#!/bin/bash
# Usage : mode-jeu.sh on   -> arrête Immich, Nextcloud, Paperless, Stirling (libère ~5 Go)
#         mode-jeu.sh off  -> les relance
STACKS="immich nextcloud paperless stirling"
case "$1" in
  on)
    for s in $STACKS; do (cd ~/homelab/$s && docker compose stop); done
    echo "Mode jeu actif. Démarre ton serveur dans le panel (jeux.lan)."
    curl -s -d "Mode jeu actif : Immich, Nextcloud, Paperless et Stirling sont arrêtés" http://127.0.0.1:8089/homelab >/dev/null
    ;;
  off)
    for s in $STACKS; do (cd ~/homelab/$s && docker compose start); done
    echo "Mode jeu terminé. Pense à arrêter ton serveur de jeu dans le panel."
    curl -s -d "Mode jeu terminé : les services sont relancés" http://127.0.0.1:8089/homelab >/dev/null
    ;;
  *) echo "Usage : $0 on|off"; exit 1 ;;
esac
EOF
chmod +x ~/homelab/bin/mode-jeu.sh
```

Pense à mettre ces services en pause dans Uptime Kuma pendant le mode jeu, pour ne pas recevoir d'alertes. Tu peux aussi les arrêter et les relancer par groupe depuis **Portainer** (Stacks), mais le script est plus rapide.

Ajoute `http://127.0.0.1:8085` aux moniteurs Kuma.

---

## 15. IA locale (Ollama + Open WebUI), seulement quand tu en as besoin

L'IA tourne **sur le processeur** de ton portable (le GPU intégré n'est pas utilisable). Elle est lente mais suffisante pour **analyser des logs**. Elle est **éteinte par défaut** : elle ne consomme rien tant que tu ne la lances pas.

| Modèle | RAM utilisée | Vitesse (ordre de grandeur) | Usage |
|---|---|---|---|
| `llama3.2:3b` | ~2,5 Go | ~10 à 15 mots/s | Résumés rapides de logs |
| `qwen2.5:7b` | ~5,5 Go | ~4 à 6 mots/s | Analyse plus fine, un peu lente |

```bash
mkdir -p ~/homelab/ia && cd ~/homelab/ia
cat > docker-compose.yml <<'EOF'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: "no"
    ports:
      - "127.0.0.1:11434:11434"
    environment:
      OLLAMA_KEEP_ALIVE: 5m
      OLLAMA_NUM_PARALLEL: "1"
      OLLAMA_MAX_LOADED_MODELS: "1"
    volumes:
      - ./ollama:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: "no"
    depends_on:
      - ollama
    ports:
      - "127.0.0.1:8088:8080"
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
      WEBUI_AUTH: "true"
      ENABLE_SIGNUP: "true"
    volumes:
      - ./webui:/app/backend/data
EOF
docker compose up -d
sleep 40
docker exec ollama ollama pull llama3.2:3b
docker exec ollama ollama pull qwen2.5:7b
```

Ouvre `http://ia.lan` : **le premier compte créé est l'administrateur** (le tien). Ensuite, **coupe les inscriptions** pour que personne d'autre ne puisse créer un compte :

```bash
cd ~/homelab/ia
sed -i 's/ENABLE_SIGNUP: "true"/ENABLE_SIGNUP: "false"/' docker-compose.yml
docker compose up -d
```

### Allumer et éteindre

`restart: "no"` empêche le démarrage automatique après un redémarrage du portable. Ajoute ces raccourcis :

```bash
cat >> ~/.bashrc <<'EOF'

alias ia-on='(cd ~/homelab/ia && docker compose up -d)'
alias ia-off='(cd ~/homelab/ia && docker compose down)'
EOF
source ~/.bashrc
ia-off
```

### Analyser des logs d'un service

```bash
cat > ~/homelab/bin/analyse-logs.sh <<'EOF'
#!/bin/bash
# Usage : analyse-logs.sh <nom_du_conteneur> [lignes]
C="${1:?Nom du conteneur (ex: immich_server)}"
N="${2:-200}"
(cd ~/homelab/ia && docker compose up -d ollama) >/dev/null
sleep 8
docker logs --tail "$N" "$C" 2>&1 | docker exec -i ollama ollama run llama3.2:3b \
  "Voici les dernières lignes de logs d'un service. Dis en français, en 10 lignes maximum, s'il y a une erreur, laquelle, et quoi vérifier en premier."
(cd ~/homelab/ia && docker compose down) >/dev/null
EOF
chmod +x ~/homelab/bin/analyse-logs.sh
```

Exemple : `~/homelab/bin/analyse-logs.sh caddy 300`. Les logs restent sur ton portable : rien n'est envoyé sur internet. Remplace `llama3.2:3b` par `qwen2.5:7b` quand tu veux une analyse plus poussée (et plus lente). Attention : une IA peut se tromper. Vérifie toujours dans Dozzle (`logs.lan`) avant d'agir.

---

## 16. DNS de toute la maison (Freebox) et accès à distance (Tailscale)

Jusqu'ici, seuls tes appareils réglés à la main passent par AdGuard. Ici, on étend le blocage des pubs et les noms `.lan` à toute la maison, puis à tes appareils hors de chez toi.

**Ne fais cette phase que quand** les phases 7 à 9 sont stables et que `home.lan` s'affiche correctement.

### 16.1 Tester d'abord sur un seul appareil

Avant de toucher à la Freebox, règle le DNS de ton téléphone à la main :

- **Android** : Wi-Fi → ton réseau → Avancé → Paramètres IP : « Statique » (ou « Personnalisé ») avec DNS 1 `192.168.1.199`, DNS 2 `1.1.1.1`. Dans Paramètres → Réseau → **DNS privé**, choisis **Désactivé** ou **Automatique** (un DNS privé réglé sur un fournisseur contourne AdGuard).
- **Navigateurs** : désactive « DNS via HTTPS » (Firefox) ou « Utiliser un DNS sécurisé » (Chrome), qui contournent AdGuard.

Ouvre `http://home.lan` sur le téléphone, puis un site avec de la pub : elle doit disparaître. Dans AdGuard (`dns.lan` → Journal des requêtes), tu dois voir les requêtes de ton téléphone.

### 16.2 Changer le DNS dans la Freebox

1. Ouvre **Freebox OS** (`mafreebox.freebox.fr`) → **Paramètres de la Freebox** → **Mode avancé** → **DHCP**.
2. Dans les champs des serveurs DNS :
   - **DNS 1** : `192.168.1.199` (AdGuard).
   - **DNS 2** : `192.168.1.254` (la Freebox elle-même).
3. Enregistre.

Le DNS 2 garde internet en route si le portable est éteint. Contrepartie : quand un appareil utilise le DNS 2, les pubs ne sont pas bloquées et les noms `.lan` ne marchent pas. Pour un blocage plus strict, tu peux laisser le DNS 2 vide, mais alors **toute la maison perd internet si le portable tombe**. Garde le DNS 2 tant que ton portable n'a pas prouvé sa stabilité.

> **Piège rencontré : « DNS_PROBE_FINISHED_NXDOMAIN » sur `home.lan` en Wi-Fi.** Android et Windows n'interrogent pas toujours les DNS dans l'ordre : ils peuvent poser la question aux deux et garder la première réponse. La Freebox, en DNS 2, répond vite « ce nom n'existe pas » pour `.lan`, et c'est cette réponse qui gagne. Si ça t'arrive : mets **le DNS 2 sur `192.168.1.199` aussi** (le même que le DNS 1), ou laisse-le vide. C'est le prix à payer pour que `.lan` marche partout : sans DNS de secours, **internet tombe pour toute la maison quand le portable est éteint**. Tant que ton portable est en Ethernet et allumé en continu, c'est un risque raisonnable.

### 16.3 Vérifier

1. Sur chaque appareil, coupe puis rallume le Wi-Fi pour qu'il prenne le nouveau DNS (ou attends la fin du bail).
2. Sur ta tour, remets le DNS en **automatique** (Propriétés IPv4 → « Obtenir les adresses des serveurs DNS automatiquement »), puis dans PowerShell : `ipconfig /flushdns` et `nslookup photos.lan`.
3. Dans AdGuard, le tableau de bord montre plusieurs appareils, et le journal affiche les requêtes de la maison.
4. **Retour en arrière** : remets DNS 1 sur `192.168.1.254` dans la Freebox. Tout revient comme avant.

Sur le portable, garde la correction vue plus haut (`192.168.1.199 1.1.1.1`, AdGuard d'abord, secours ensuite).

Deux limites à connaître :

- La Freebox distribue aussi un DNS en **IPv6** (`fd00:db8::1`, visible avec `Get-DnsClientServerAddress` sous Windows). Ce DNS ne connaît pas `.lan` : `nslookup photos.lan fd00:db8::1` répond « Non-existent domain ». Les appareils qui l'utilisent contournent AdGuard. Dans Freebox OS, les onglets **Connexion Internet → Configuration IPv6 → DHCPv6** et **DNS IPv6** ne règlent pas ça : le DHCPv6 est désactivé et l'onglet DNS IPv6 ne concerne que les DNS que la Freebox utilise vers internet, pas ceux qu'elle distribue (ne coche pas « Forcer l'utilisation de serveurs DNS IPv6 personnalisés »). Sur ta tour, le plus simple est de **désactiver IPv6 sur la carte Ethernet** : `Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6` (PowerShell administrateur), puis `ipconfig /flushdns`. Pour revenir en arrière : `Enable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6`. Ne relance pas la commande de retour par erreur juste après. Pour les autres appareils, si tu le constates dans le journal d'AdGuard, accepte la limite.
- Sur **Android**, désactive aussi le **DNS privé** (Paramètres → Connexion et partage → DNS privé → Désactivé) et le **DNS sécurisé de Chrome** (Chrome → ⋮ → Paramètres → Confidentialité et sécurité → Sécurité → Utiliser un DNS sécurisé). Les réglages « Confidentialité et sécurité » de l'**appli Google** ne sont pas ceux de Chrome.
- Un site légitime peut être bloqué par erreur. Dans AdGuard → Journal des requêtes, clique sur « Débloquer » à côté de la requête concernée. Explique à ta famille qu'ils peuvent te le signaler.

### 16.4 Accès à distance avec Tailscale

Pour utiliser `films.lan`, `photos.lan` ou `home.lan` hors de chez toi, sans ouvrir de port dans la Freebox :

1. **Autorise le portable à annoncer sa propre adresse** (les noms `.lan` pointent vers `192.168.1.199`) :
```bash
sudo tailscale set --advertise-routes=192.168.1.199/32
```
2. Dans la console Tailscale (`login.tailscale.com` → Machines → `homelab` → les trois points ⋯ → « Edit route settings »), **coche la case** de la route `192.168.1.199/32` et clique sur **Save**. Tant que la fenêtre dit « 1 route is advertised but not approved » (et que l'étiquette « Subnets » porte un ⓘ), la route n'est **pas** utilisée. Ne coche pas « Use as exit node ».
3. Dans la console → **DNS → Nameservers → Add nameserver → Custom** : `100.64.0.10`, active **« Restrict to domain »** (ou « Split DNS ») avec le domaine `lan` (sans point ni étoile), puis **Save**. Une ligne `lan` doit apparaître sous « Nameservers ». Sans cette ligne, le téléphone n'a que le DNS de ton opérateur, qui répond `DNS_PROBE_FINISHED_NXDOMAIN`. Seuls les noms `.lan` passent alors par chez toi. Pour aussi bloquer les pubs hors de chez toi, active à la place **« Override DNS servers »** : tout le trafic DNS des appareils Tailscale passe alors par AdGuard (le portable doit rester allumé).
4. Sur le téléphone, ouvre l'appli Tailscale : vérifie qu'elle est connectée, que **« Utiliser les paramètres DNS de Tailscale »** et **« Utiliser les sous-réseaux Tailscale »** sont actifs, puis déconnecte-reconnecte. Garde le **DNS privé** d'Android désactivé.
5. **Test**, Wi-Fi coupé (4G ou 5G) et Tailscale actif : ouvre `http://home.lan`, puis `http://photos.lan`.

Tes parents n'ont pas besoin de Tailscale s'ils n'utilisent les services qu'à la maison. S'ils en ont besoin ailleurs, installe l'appli sur leurs appareils et invite-les dans ton réseau (console → Users → Invite).

---

## 17. Sauvegardes hebdomadaires vers la tour (restic)

Chaque samedi, le portable envoie une sauvegarde chiffrée et incrémentale vers un dossier partagé sur le disque **E:** de ta tour. Si la tour est éteinte, le script prévient par ntfy et réessaie deux fois dans la soirée, puis au prochain démarrage du portable.

### 17.1 Côté tour (Windows)

Dans **PowerShell en administrateur**, lance **les commandes une par une** (jamais collées d'un coup : `net user … *` pose une question, et les lignes suivantes seraient prises pour ton mot de passe, ce qui annule la création du compte et du partage).

```powershell
mkdir E:\Sauvegardes-homelab
```
```powershell
net user backup-homelab * /add
```
Cette commande te demande un mot de passe pour le compte **dédié** `backup-homelab` (**à taper à la main**, deux fois, rien ne s'affiche) : choisis-en un long, différent des autres, sans accents ni `#`, `\`, `"`, `$`, et note-le (tu en auras besoin à l'étape suivante). Ce n'est **pas** ton mot de passe de session Windows. Tu dois lire « La commande s'est terminée correctement ». Ce compte n'apparaît pas sur l'écran de connexion de Windows : vérifie-le avec `Get-LocalUser`.
```powershell
icacls E:\Sauvegardes-homelab /grant "backup-homelab:(OI)(CI)M"
```
```powershell
New-SmbShare -Name Sauvegardes-homelab -Path E:\Sauvegardes-homelab -FullAccess backup-homelab
```
Elle doit afficher un tableau avec `Sauvegardes-homelab`. Vérifie : `Get-SmbShare Sauvegardes-homelab` et `Get-SmbShareAccess Sauvegardes-homelab`.

Puis vérifie que le réseau de la tour est en profil **Privé**, et autorise le partage de fichiers dans le pare-feu de Windows, limité au réseau privé (au mieux à la seule adresse du portable).

### 17.2 Côté portable : monter le partage

```bash
sudo apt install -y cifs-utils
sudo mkdir -p /mnt/tour-backup
sudo nano /root/.smb-tour
```
Dans l'éditeur, écris ces deux lignes (avec **ton** mot de passe), puis `Ctrl+O`, Entrée, `Ctrl+X` :
```
username=backup-homelab
password=LE_MOT_DE_PASSE_DU_COMPTE_BACKUP
```
Puis :
```bash
sudo chmod 600 /root/.smb-tour
echo '//192.168.1.198/Sauvegardes-homelab /mnt/tour-backup cifs credentials=/root/.smb-tour,vers=3.0,uid=0,gid=0,file_mode=0600,dir_mode=0700,_netdev,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120,x-systemd.mount-timeout=30 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo systemctl start 'mnt-tour\x2dbackup.automount'
sudo ls /mnt/tour-backup
findmnt /mnt/tour-backup
```
Tour allumée, `ls` doit répondre sans erreur (le dossier est vide) et `findmnt` doit afficher **deux lignes** : une `autofs`, et une avec **`//192.168.1.198/Sauvegardes-homelab`** en `cifs`. Le partage ne se monte que quand on l'utilise et se démonte seul au bout de 2 minutes : un portable qui démarre sans la tour ne bloque donc pas.

> **Piège rencontré : un dépôt créé sur le mauvais disque.** Sans la commande `systemctl start … .automount`, l'automontage n'est actif qu'après un redémarrage, et `/mnt/tour-backup` reste un **dossier local** du portable : `ls` répond sans erreur, et `restic-homelab init` crée alors le dépôt **sur le disque du portable**. Contrôle toujours avec `findmnt` avant l'`init` (voir 17.3), et supprime un dépôt créé par erreur (`sudo rm -rf /mnt/tour-backup/restic`, avant de démarrer l'automontage).
>
> **Messages d'erreur du montage** (à lire avec `sudo mount -t cifs //192.168.1.198/Sauvegardes-homelab /mnt/test-tour -o credentials=/root/.smb-tour,vers=3.0` puis `sudo dmesg | tail -8`) : `Permission denied` / `STATUS_LOGON_FAILURE` = nom ou mot de passe faux (réinitialise avec `net user backup-homelab *` sur la tour et réécris le fichier à l'identique) ; `BAD_NETWORK_NAME` = le partage n'existe pas encore sur la tour (refais `New-SmbShare`, 17.1) ; « Aucun périphérique de ce type » sur `ls` = le montage échoue et l'automontage le cache, regarde le message ci-dessus.

### 17.3 Créer le dépôt chiffré

**Avant de continuer**, `findmnt /mnt/tour-backup` doit afficher la ligne `cifs` de la tour (17.2). Ce mot de passe de chiffrement est un **troisième** mot de passe, différent de celui de `sudo` et de celui du compte `backup-homelab` : tu l'inventes maintenant.

```bash
sudo bash -c 'umask 077; read -r -s -p "Mot de passe de chiffrement des sauvegardes : " P; echo; echo "$P" > /root/.restic-pass'
sudo tee /usr/local/sbin/restic-homelab >/dev/null <<'EOF'
#!/bin/bash
exec restic -r /mnt/tour-backup/restic --password-file /root/.restic-pass "$@"
EOF
sudo chmod 700 /usr/local/sbin/restic-homelab
sudo restic-homelab init
```

Tu dois lire `created restic repository … at /mnt/tour-backup/restic`. Vérifie dans l'Explorateur de la tour : `E:\Sauvegardes-homelab\restic` contient `data`, `index`, `keys`, `locks`, `snapshots` et `config`. Si `init` répond « /root/.restic-pass does not exist », la première commande n'a pas été exécutée (collage cassé) : refais-la seule.

> **Ce mot de passe est indispensable.** Sans lui, toutes les sauvegardes sont définitivement illisibles. Note-le dans un gestionnaire de mots de passe **et** garde-en une copie hors du portable.

### 17.4 Le script de sauvegarde

Remplace `alex` par ton nom d'utilisateur si besoin (`echo $USER`).

```bash
sudo tee /usr/local/sbin/homelab-backup.sh >/dev/null <<'EOF'
#!/bin/bash
set -uo pipefail
H=/home/alex
STAMP=/var/lib/homelab-backup/last-ok
NTFY=http://127.0.0.1:8089/homelab
mkdir -p /var/lib/homelab-backup "$H/homelab/dumps"
notify() { curl -s -H "Title: Sauvegarde homelab" -d "$1" "$NTFY" >/dev/null || true; }

# Déjà réussie dans les 5 derniers jours : rien à faire
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -lt 432000 ]; then exit 0; fi

# La tour et son partage sont-ils disponibles ?
if ! timeout 3 bash -c '</dev/tcp/192.168.1.198/445' 2>/dev/null; then notify "Tour éteinte : sauvegarde reportée"; exit 1; fi
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
  "$H/homelab" "$H/media/musique" /etc/pelican /etc/fstab /etc/docker
rc=$?

if [ $rc -ne 0 ] && [ $rc -ne 3 ]; then notify "Sauvegarde échouée (code $rc)"; exit 1; fi

restic-homelab forget --keep-weekly 8 --keep-monthly 6 --prune >/dev/null 2>&1
restic-homelab check >/dev/null 2>&1 || { notify "La vérification du dépôt a échoué"; exit 1; }
touch "$STAMP"
notify "Sauvegarde terminée avec succès"
EOF
sudo chmod 700 /usr/local/sbin/homelab-backup.sh
```

Ce que cette sauvegarde contient :

- Tous les dossiers `~/homelab` : configurations, comptes, Immich (photos et vidéos originales), Nextcloud, Paperless, Navidrome, Home Assistant, Pelican.
- Les exports de base de données (les dossiers bruts de PostgreSQL et MariaDB sont exclus : les copier en marche donne des fichiers corrompus).
- Ta musique. **Les films et séries ne sont pas sauvegardés**, car ils sont lourds et remplaçables. Ajoute `"$H/media/films"` à la commande si ta tour a la place.
- Immich écrit lui-même une sauvegarde de sa base chaque nuit dans `library/backups/`, incluse ici.

### 17.5 Planifier le samedi

```bash
sudo tee /etc/systemd/system/homelab-backup.service >/dev/null <<'EOF'
[Unit]
Description=Sauvegarde hebdomadaire du homelab vers la tour
After=network-online.target

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/usr/local/sbin/homelab-backup.sh
Nice=10
IOSchedulingClass=idle
EOF
sudo tee /etc/systemd/system/homelab-backup.timer >/dev/null <<'EOF'
[Unit]
Description=Sauvegarde du homelab le samedi

[Timer]
OnCalendar=Sat *-*-* 17,19,21:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer
systemctl list-timers homelab-backup.timer --no-pager
```

Le script s'arrête tout de suite s'il a déjà réussi dans les 5 jours : les passages de 19 h et 21 h ne servent que si la tour était éteinte à 17 h.

### 17.6 Premier test et test de restauration

Lance une première sauvegarde (la plus longue, selon la taille de tes photos) :

```bash
sudo systemctl start homelab-backup.service
journalctl -u homelab-backup.service -f
```

Quand elle est finie, tu dois recevoir « Sauvegarde terminée avec succès » dans ntfy. Puis **teste la restauration** (une sauvegarde jamais restaurée n'est pas une sauvegarde) :

```bash
sudo restic-homelab snapshots
sudo restic-homelab restore latest --target /tmp/test-restauration --include /home/alex/homelab/caddy/Caddyfile
sudo cat /tmp/test-restauration/home/alex/homelab/caddy/Caddyfile | head -5
sudo rm -rf /tmp/test-restauration
```

Une copie unique sur la tour ne protège pas contre un vol, un incendie ou une panne de ta tour. Pour tes photos, pense à une **deuxième copie** (disque externe branché de temps en temps, ou stockage chiffré en ligne). Pour restaurer Immich complètement, suis la page « Backup and restore » de la documentation officielle.

---

## 18. Sécurité

### 18.1 Mots de passe et comptes

| Service | Compte admin | Double authentification |
|---|---|---|
| Linux (portable) | `passwd` (mot de passe long) | Non |
| AdGuard | Ton compte | Non disponible |
| Caddy (admin.lan, logs, disque) | `admin` | Non |
| Portainer | Ton compte | Active-la dans « My account » |
| Uptime Kuma | Ton compte | Active-la dans Paramètres → Sécurité |
| Beszel | Ton compte | Non |
| Jellyfin, Navidrome, Immich | Ton compte, plus un compte par personne | Non |
| Nextcloud | Ton compte | Two-Factor TOTP |
| Paperless | Ton compte | Mon profil |
| Home Assistant | Ton compte propriétaire | Profil → Sécurité |
| Pelican | Ton compte | Profil → Sécurité |
| Tailscale, Google | Ton compte | Active-la |

Utilise un **gestionnaire de mots de passe** (Bitwarden, KeePassXC…) pour tous ces mots de passe : un par service, tous différents.

**Nettoyage des accès donnés à Claude Code** : si tu lui as autorisé `sudo` sans mot de passe pendant l'installation, supprime-le maintenant.
```bash
sudo ls -l /etc/sudoers.d/
```
Si un fichier autre que `README` existe, regarde son contenu (`sudo cat`), puis supprime-le avec `sudo rm /etc/sudoers.d/NOM` et vérifie avec `sudo visudo -c`.

### 18.2 SSH

Choisis le mode d'accès SSH qui convient à ton usage (clé ou mot de passe long), limite-le à ton réseau local et à ton VPN, interdis la connexion directe de `root`, et garde une session ouverte pendant tout changement de configuration. La configuration réelle de ce serveur n'est pas publiée.

### 18.3 Pare-feu (ufw)

Active un pare-feu (ufw) : tout refuser en entrée par défaut, puis n'autoriser que ce dont tes services ont besoin, depuis ton réseau local et ton VPN seulement. Garde une session ouverte pendant l'activation. Les règles réelles de ce serveur ne sont pas publiées.

> **Limite importante** : Docker ouvre lui-même les ports qu'il publie, et **ufw ne les filtre pas**. Fais écouter les conteneurs sur `127.0.0.1` derrière Caddy plutôt que sur toutes les adresses.

### 18.4 Limiter la taille des logs Docker

Sans limite, les logs peuvent remplir le disque.

```bash
cat /etc/docker/daemon.json 2>/dev/null
```
Si le fichier n'existe pas :
```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
```
S'il existe déjà, **ajoute** ces deux clés au lieu de l'écraser. Puis, à un moment calme (les conteneurs redémarrent) :

```bash
sudo systemctl restart docker
for d in ~/homelab/*/; do [ -f "$d/docker-compose.yml" ] && (cd "$d" && docker compose up -d --force-recreate); done
```
La limite ne s'applique qu'aux conteneurs **recréés**, d'où la boucle. Mets la boucle en pause pour `ia` (qui doit rester éteint) : `cd ~/homelab/ia && docker compose down` après la boucle.

### 18.5 CrowdSec (bloque les adresses qui attaquent)

Option : CrowdSec analyse les journaux et bloque, avec son « bouncer » pare-feu, les adresses qui insistent. Suis la documentation officielle (`crowdsec` et `crowdsec-firewall-bouncer`), puis teste avec une adresse de documentation :
```bash
sudo cscli decisions add -i 203.0.113.50 -t ban -d 2m
sudo cscli decisions list
sudo cscli decisions delete -i 203.0.113.50
```

### 18.6 Mises à jour de sécurité automatiques

Elles sont déjà actives depuis la phase 3. Vérifie :
```bash
systemctl list-timers apt-daily* --no-pager
sudo unattended-upgrade --dry-run -d 2>&1 | tail -5
```

---

## 19. Vérifications finales et vie de tous les jours

### 19.1 Test de redémarrage complet

Le test le plus important : le portable doit tout relancer **seul**.

```bash
sudo reboot
```

Attends 3 minutes, puis depuis ta tour :

- `http://home.lan` et `http://admin.lan` s'affichent.
- `http://dns.lan` : AdGuard tourne.
- `http://status.lan` : tous les moniteurs sont verts.
- `http://monitor.lan` : le portable est en ligne.
- `http://jeux.lan` : le nœud Pelican a un cœur vert.
- `sudo ls /mnt/tour-backup` fonctionne (tour allumée) et `findmnt /mnt/tour-backup` affiche la ligne `cifs` de la tour.

Dans le **BIOS** du portable, deux réglages utiles : « Démarrer automatiquement après une coupure de courant » (si disponible) et la **limitation de la charge de la batterie** (« Battery Health Manager » chez HP, à 80 %), qui protège la batterie d'un portable toujours branché. La batterie sert aussi de petit onduleur.

### 19.2 Entretien

| Quand | Quoi |
|---|---|
| Chaque jour | Rien : les alertes arrivent dans ntfy et par mail (Kuma). |
| Chaque dimanche | Lis les notifications de **Diun** (images avec une nouvelle version). |
| Chaque samedi | Vérifie le message « Sauvegarde terminée » (tour allumée). |
| Chaque mois | Mises à jour des services (voir ci-dessous), `sudo apt update && sudo apt full-upgrade`, regarde **Scrutiny** (`disque.lan`). |
| Tous les 3 mois | **Test de restauration** d'un fichier (17.6) et `sudo restic-homelab check --read-data-subset=5%`. |

**Mettre à jour un service** (exemple Jellyfin) :
```bash
cd ~/homelab/jellyfin && docker compose pull && docker compose up -d
docker image prune -f
```
Pour Immich, Nextcloud et Paperless, lance d'abord une sauvegarde (`sudo systemctl start homelab-backup.service`) et lis les notes de version.

### 19.3 Quand quelque chose ne marche pas

| Symptôme | Que faire |
|---|---|
| Un service est rouge dans Kuma | Ouvre **Dozzle** (`logs.lan`), regarde les dernières lignes du conteneur, puis `docker compose restart` dans son dossier. |
| Plus d'internet dans la maison | AdGuard est tombé. Dans la Freebox, remets **DNS 1** sur `192.168.1.254`, puis répare AdGuard. |
| `xxx.lan` ne s'ouvre pas, mais l'IP oui | Problème de DNS sur cet appareil : `nslookup xxx.lan`, DNS privé ou DNS sécurisé du navigateur à désactiver. |
| Le portable est lent ou RAM pleine | Regarde Beszel, lance `~/homelab/bin/mode-jeu.sh on`, arrête l'IA (`ia-off`). |
| L'espace disque diminue | `docker system df`, `du -sh ~/homelab/* ~/media/*`, supprime les anciennes images (`docker image prune -a`). |
| Le Wi-Fi décroche | Passe en Ethernet (adaptateur USB-Ethernet **seul**, sans hub). |
| Tu as oublié un mot de passe admin | Utilise ton gestionnaire. Sinon, Portainer et Nextcloud ont des procédures de réinitialisation dans leur documentation officielle. |

### 19.4 Liste de contrôle finale

- [ ] Mot de passe Linux long, accès SSH limité
- [ ] Double authentification activée partout où c'est possible
- [ ] Comptes de la famille créés dans Jellyfin, Navidrome, Immich, Nextcloud, Paperless
- [ ] Tous les moniteurs Uptime Kuma verts, notifications ntfy et mail testées
- [ ] Alertes Beszel actives (statut, CPU, RAM, disque, température)
- [ ] Première sauvegarde réussie **et** restauration d'un fichier testée
- [ ] Mot de passe restic noté hors du portable
- [ ] DNS de la Freebox sur AdGuard (avec DNS 2 de secours), test depuis un téléphone
- [ ] Tailscale : route approuvée, DNS configuré, test en 4G réussi
- [ ] Redémarrage complet testé
- [ ] Pare-feu actif, limite des logs Docker en place


---

# Améliorations (après les phases de base)

Fais ces phases **après** les phases 12 à 19 (ou au moins après la 17). Ordre conseillé : 22, 20, 21, 23, 24. La feuille de route complète est dans `homelab-roadmap.md`.

## 20. Pages v2 : tablette, télé, état du serveur, appareils

Les nouvelles pages `home.lan` et `admin.lan` remplacent celles de la phase 8.1. Elles viennent dans le dossier `pages-maison` (envoyé avec ce guide) :

- `home.lan` : tuiles adaptées à la tablette (zones plus grandes), **mode télé** (très gros, navigation aux flèches de la télécommande), page `guide.html` pour les parents et page `certificat.html` pour le HTTPS.
- `admin.lan` : mesures en direct du portable (processeur, mémoire, disque, température, batterie, conteneurs), état de la tour, bloc **Appareils** (lumières, prises, volets, capteurs de Home Assistant, réservé à l'admin), **interface de sauvegarde** avec bouton, historique, erreurs et journaux (phase 21), état des outils.
- Un petit service local, `homelab-api` (Python, écoute seulement sur `127.0.0.1:8095`), fournit les mesures et remplace l'ancien contrôle d'état.

### 20.1 Installer les pages et le service

Copie `pages-maison.zip` sur le portable (dans `~/Téléchargements`), puis demande à Claude Code :

```
Dézippe ~/Téléchargements/pages-maison.zip dans ~/Téléchargements/pages-maison, puis lance "bash installer-pages.sh" depuis ce dossier (sans sudo). Ensuite montre-moi : systemctl --user is-active homelab-api, le contenu de ~/homelab/caddy/pages/home/etat.json, et ls ~/homelab/caddy/pages/*. Ne lance aucune sauvegarde.
```

L'installateur garde une copie des anciennes pages dans `~/homelab/caddy/pages-ancien-<date>`.

### 20.2 Route Caddy `/api`

Pour que les pages voient les mesures, les appareils et le bouton de sauvegarde, Caddy doit relayer `/api/*` vers le service. Demande à Claude Code :

```
Dans ~/homelab/caddy/Caddyfile, dans les blocs home.lan ET admin.lan, ajoute avant le file_server une règle qui envoie /api/* vers 127.0.0.1:8095, par exemple :
    handle /api/* {
        reverse_proxy 127.0.0.1:8095
    }
Pour admin.lan, garde le basic_auth existant au-dessus (la route doit rester protégée). Ne change pas les autres blocs. Valide avec "docker exec caddy caddy validate --config /etc/caddy/Caddyfile", recharge avec "docker exec caddy caddy reload --config /etc/caddy/Caddyfile", puis teste : curl -s http://127.0.0.1:8095/api/etat | head -c 200, puis curl -s -H "Host: home.lan" http://127.0.0.1/api/appareils et curl -s -H "Host: home.lan" http://127.0.0.1/api/sauvegarde (les deux doivent répondre 403 : réservés à admin.lan).
```

Ouvre ensuite `http://admin.lan` (Ctrl+F5) : les six mesures doivent s'afficher.

### 20.3 Brancher les appareils de Home Assistant

Le bloc **Appareils** de `admin.lan` (il n'existe pas sur `home.lan`, pour que la famille ne commande rien par erreur) reste caché tant que rien n'est configuré. Il lit Home Assistant avec un jeton que **tu** crées :

1. Dans Home Assistant (`http://domotique.lan`), clique sur ton profil (en bas à gauche), onglet **Sécurité**, descends jusqu'à **Jetons d'accès longue durée**, clique sur **Créer un jeton**, nomme-le `homelab` et **copie-le** (il ne s'affiche qu'une fois).
2. Dans **ton propre terminal** (pas dans Claude Code), tape la commande ci-dessous, colle le jeton quand elle te le demande (rien ne s'affiche, c'est normal) et valide :

```bash
mkdir -p ~/.config/homelab && read -rsp 'Jeton Home Assistant : ' T && printf '%s' "$T" > ~/.config/homelab/ha-token && chmod 600 ~/.config/homelab/ha-token && unset T && echo OK
```

3. Liste les appareils à afficher dans `~/.config/homelab/appareils.json`. Les identifiants (`light.salon`…) se trouvent dans Home Assistant, Paramètres, Appareils et services, onglet Entités. Exemple :

```json
[
  {"id": "light.salon", "nom": "Salon", "piece": "Salon"},
  {"id": "switch.cafetiere", "nom": "Cafetière", "piece": "Cuisine"},
  {"id": "cover.volet_chambre", "nom": "Volet", "piece": "Chambre"},
  {"id": "sensor.temperature_salon", "nom": "Température", "piece": "Salon"}
]
```

Les lumières, prises, volets, ventilateurs et interrupteurs s'allument et s'éteignent d'un clic. Les capteurs et les thermostats affichent leur valeur. Rien d'autre ne peut être commandé depuis la page : seuls les appareils de cette liste sont acceptés. Pas besoin de redémarrer : la liste est relue à chaque fois.

### 20.4 Tablette et télé

- **Tablette** : rien à faire, la page s'adapte.
- **Télé** : ouvre `home.lan` dans le navigateur de la télé, descends avec les flèches jusqu'au bouton **Mode télé** et valide. Le choix est mémorisé. Pour forcer le mode, ajoute `?tv=1` à l'adresse (`?tv=0` pour l'enlever). Sur les télés Samsung, LG, Android TV et Fire TV, il s'active tout seul.

### 20.5 Vérifier

- [ ] `home.lan` : le salut, les tuiles vertes (pas de bloc Appareils : il est dans `admin.lan`)
- [ ] `admin.lan` : le bloc « Appareils de la maison » apparaît une fois `appareils.json` rempli
- [ ] `admin.lan` : six mesures en direct, « Tour : allumée » (ou éteinte), « Mesures en direct »
- [ ] `systemctl --user is-active homelab-api` répond `active`, et reste actif après un redémarrage (`loginctl enable-linger`)
- [ ] `http://home.lan/api/sauvegarde` et `http://home.lan/api/appareils` répondent 403 (réservés à `admin.lan`)

## 21. Interface de sauvegarde : bouton, historique, erreurs et journaux

Dans `admin.lan`, le bloc **Sauvegardes** te donne :

- un bouton **Sauvegarder maintenant** (avec une confirmation, pour éviter un clic par erreur) ;
- l'état de la dernière sauvegarde (réussie ou ratée, il y a combien de temps) et la prochaine date automatique ;
- l'onglet **Exécutions** : une ligne par sauvegarde, planifiée ou lancée à la main, avec la date, la durée, le résultat (**Réussie** ou **Échec** avec le code d'erreur) et un lien **Voir** qui ouvre son **journal complet** ;
- un **journal en direct** qui défile pendant qu'une sauvegarde tourne ;
- l'onglet **Instantanés restic** : la liste des sauvegardes présentes dans le dépôt (date, taille ajoutée, fichiers, durée).

Le bouton lance **exactement le même script que le samedi** (même contrôle de la tour, mêmes copies des bases de données, même notification ntfy). Il ne lance jamais rien tout seul. Tout le bloc est réservé à `admin.lan` (mot de passe admin).

### 21.1 Installer (à faire toi-même, avec ton mot de passe sudo)

Dans **ton propre terminal**, depuis le dossier `pages-maison` :

```bash
cd ~/pack-maison/pages-maison
```

```bash
sudo bash installer-sauvegarde-ui.sh
```

Le script ne lance aucune sauvegarde. Il fait seulement ceci :

1. installe deux petits programmes en root : `homelab-backup-suivi` (enregistre chaque exécution, **réussie ou ratée**, avec son journal, dans `/var/lib/homelab-backup/executions.json`) et `homelab-backup-historique` (liste des instantanés restic) ;
2. autorise ton utilisateur à lancer **uniquement** deux commandes précises sans mot de passe : `systemctl start --no-block homelab-backup.service` et la lecture du journal de ce service (fichier `/etc/sudoers.d/homelab-backup`, vérifié avec `visudo`) ;
3. ajoute à `homelab-backup.service` une ligne `ExecStopPost`, exécutée **après chaque exécution, même quand le script a échoué**, pour enregistrer le résultat.

Il faut aussi avoir lancé `installer-pages.sh` (phase 20.1) avec la version à jour des pages : le service `homelab-api` lit ces enregistrements.

Si la tour est allumée, le script remplit tout de suite l'onglet « Instantanés » (lecture seule). L'onglet « Exécutions » commence à se remplir à partir de la prochaine sauvegarde : l'historique d'avant l'installation n'existe pas.

### 21.2 Utiliser

1. Ouvre `http://admin.lan` (identifiant admin).
2. Clique sur **Sauvegarder maintenant** : le bouton devient jaune et te demande **Confirmer** (deuxième pression dans les 6 secondes).
3. Le bloc passe à « Sauvegarde en cours… » et le journal défile. À la fin, la ligne du haut devient verte (« Dernière sauvegarde réussie ») ou rouge (« a échoué »), et la sauvegarde apparaît dans **Exécutions**.
4. En cas d'échec, clique sur **Voir** : le journal montre la cause (le plus souvent « tour éteinte » : allume-la et relance). Tu reçois aussi une notification ntfy.

### 21.3 Vérifier sans lancer de sauvegarde

- `systemctl cat homelab-backup.service` montre la ligne `ExecStopPost=-/usr/local/sbin/homelab-backup-suivi …`.
- `sudo -l` (ton mot de passe) liste les deux commandes autorisées et rien d'autre.
- `curl -s -H "Host: home.lan" http://127.0.0.1/api/sauvegarde` répond 403 ; sans le mot de passe, `admin.lan` refuse l'accès.

### 21.4 Restaurer ou parcourir les sauvegardes (option)

La page montre l'historique et les journaux, pas le contenu des fichiers. Pour parcourir et restaurer des fichiers à la souris, ajoute **Backrest**, une interface web pour restic (port 9898). Demande à Claude Code de l'installer sur `127.0.0.1:9898`, derrière Caddy sur `sauvegardes.lan` avec le mot de passe admin, en lecture du même dépôt (le mot de passe du dépôt, tu le saisis toi-même dans l'interface). **Ne laisse pas Backrest planifier ses propres sauvegardes** : ce sont celles du script du samedi qui font foi.

## 22. MeTube : choisir le dossier, et nouveaux dossiers de médias

### 22.1 Créer les dossiers

```bash
mkdir -p ~/media/{films,series,musique,vod,cuisine,tutos,documentaires,enfants,concerts,podcasts,a-trier}
ls ~/media
```

| Dossier | À quoi il sert |
|---|---|
| `films`, `series` | Les films et les séries (déjà en place) |
| `musique` | La musique (Navidrome) |
| `vod` | Les vidéos téléchargées en vrac |
| `cuisine` | Les recettes en vidéo |
| `tutos` | Les cours et tutoriels |
| `documentaires` | Les documentaires |
| `enfants` | Les vidéos pour les enfants |
| `concerts` | Les concerts |
| `podcasts` | Les podcasts |
| `a-trier` | Ce dont tu n'es pas sûr, à ranger plus tard |

### 22.2 MeTube : la case « Dossier »

MeTube peut proposer, pour chaque téléchargement, le dossier de destination (la liste des dossiers de `~/media` s'affiche quand tu cliques dans la case). Remplace son `docker-compose.yml` :

```bash
cd ~/homelab/metube && docker compose down
cat > docker-compose.yml <<EOF
services:
  metube:
    image: ghcr.io/alexta69/metube:latest
    container_name: metube
    restart: unless-stopped
    user: "$(id -u):$(id -g)"
    ports:
      - "127.0.0.1:8083:8081"
    environment:
      DOWNLOAD_DIR: /downloads
      AUDIO_DOWNLOAD_DIR: /downloads/musique
      STATE_DIR: /state
      TEMP_DIR: /state/tmp
      CUSTOM_DIRS: "true"
      CREATE_CUSTOM_DIRS: "true"
    volumes:
      - $HOME/media:/downloads
      - ./state:/state
EOF
mkdir -p state && docker compose up -d
```

Dans `http://videos.lan`, ouvre « Options avancées » si la case **Dossier** n'est pas visible, colle un lien, **choisis le dossier** (`cuisine`, `vod`, `tutos`…), puis valide. Les audios vont dans `musique`.

Si tu oublies de choisir un dossier, le fichier arrive à la racine de `~/media`. Déplace-le alors dans `a-trier` (`mv ~/media/*.mp4 ~/media/a-trier/`).

### 22.3 Jellyfin : une bibliothèque par dossier

Jellyfin doit voir tout `~/media`. Dans `~/homelab/jellyfin/docker-compose.yml`, remplace les deux lignes `films` et `series` (et celle de `videos` si elle existe) par une seule :

```yaml
      - $HOME/media:/media:ro
```

puis `cd ~/homelab/jellyfin && docker compose up -d`. Dans Jellyfin (Tableau de bord, Bibliothèques, Ajouter une médiathèque), crée :

| Bibliothèque | Type | Dossier |
|---|---|---|
| Films | Films | `/media/films` |
| Séries | Séries | `/media/series` |
| VOD | Vidéos personnelles | `/media/vod` |
| Cuisine | Vidéos personnelles | `/media/cuisine` |
| Tutos | Vidéos personnelles | `/media/tutos` |
| Documentaires | Films | `/media/documentaires` |
| Enfants | Vidéos personnelles | `/media/enfants` |
| Concerts | Vidéos personnelles | `/media/concerts` |

La musique passe par Navidrome (`/media/musique`). Les podcasts téléchargés avec MeTube vont dans `podcasts`, que tu peux aussi ajouter comme bibliothèque Jellyfin. Pour limiter l'accès : dans Utilisateurs, choisis les bibliothèques visibles par compte (par exemple `enfants` seulement pour un compte enfant).

## 23. HTTPS et adresses IP qui redirigent vers les noms

Objectif : **tous** les noms `.lan` en `https://` avec le cadenas (films, musique, photos, cloud, docs, admin…), et `http://192.168.1.199` qui renvoie vers `home.lan`. Avec l'option A, Caddy crée automatiquement un certificat pour chaque nom `.lan` du Caddyfile, y compris ceux que tu ajouteras plus tard : il n'y a rien à faire par site. Seul le certificat racine s'installe, une fois par appareil. Deux façons de faire :

- **Option A (gratuite, recommandée pour commencer)** : Caddy signe lui-même les certificats avec sa propre autorité. Il faut installer son certificat **une fois par appareil** (page `certificat.html`).
- **Option B (payante, plus propre)** : un vrai nom de domaine (environ 8 €/an) avec des certificats Let's Encrypt par DNS. Aucun certificat à installer nulle part, télé comprise. Plus de réglages (plugin DNS de Caddy, jeton API que tu saisis toi-même) : à faire plus tard si l'option A t'agace.

### 23.1 Option A : l'autorité de Caddy

**Règle de sécurité : la redirection automatique de http vers https n'est activée qu'à la dernière étape**, quand le certificat est installé sur tous les appareils importants (tes téléphones, les parents, la tablette). Sur une télé qui ne l'accepte pas, tu gardes `http`.

Demande à Claude Code :

```
Active le HTTPS local dans Caddy, sans rien casser, en 4 étapes. Montre-moi le diff du Caddyfile avant de le recharger, et sauvegarde l'ancien en Caddyfile.avant-https.
1) Dans le bloc d'options globales (en haut du Caddyfile), mets "local_certs" et "auto_https disable_redirects". Pour chaque site *.lan, serve-le EN MÊME TEMPS en http et en https : remplace l'adresse "http://X.lan" par "X.lan, http://X.lan". Garde les basic_auth et les routes existantes. Garde le port 80 fonctionnel : http://home.lan et http://films.lan doivent continuer de répondre comme avant.
2) Valide et recharge Caddy, puis teste : curl -sk -o /dev/null -w '%{http_code}\n' https://home.lan (200) et la même chose en http.
3) Copie le certificat racine de Caddy (dans le volume de données de Caddy, pki/authorities/local/root.crt) vers ~/homelab/caddy/pages/home/ca.crt (droits 644), pour que http://home.lan/ca.crt le serve. Vérifie avec curl -s http://home.lan/ca.crt | head -3.
4) Ajoute des blocs pour l'adresse IP : "http://192.168.1.199" qui fait un redir 302 vers http://home.lan{uri}, et "https://192.168.1.199" (tls internal) qui fait un redir 302 vers https://home.lan{uri}.
Ne lance aucune sauvegarde.
```

Installe ensuite le certificat sur chaque appareil : ouvre `http://home.lan/certificat.html` et suis les étapes de l'appareil (Android, iPhone, Windows, Mac). Ouvre ensuite `https://home.lan` : le cadenas doit être fermé, sans avertissement.

### 23.2 Redirection automatique vers https (dernière étape)

Quand tes appareils et ceux des parents ont le certificat, demande à Claude Code :

```
Dans le Caddyfile, enlève la partie ", http://X.lan" ajoutée à l'étape 1 de la phase 23 (sauf pour home.lan, qui doit rester en http pour servir /ca.crt et /certificat.html), supprime "auto_https disable_redirects", garde "local_certs", puis valide et recharge. Vérifie : curl -sI http://films.lan répond 308 vers https://films.lan, et curl -s http://home.lan/ca.crt renvoie bien le certificat. Garde Caddyfile.avant-https.
```

Pour la télé, utilise `http://home.lan`, qui reste servi en http (voir 20.4).

### 23.4 Ce qui te protège vraiment (sécurité)

Le HTTPS chiffre ce qui circule dans ta maison (mots de passe, jetons) : un voisin sur ton Wi-Fi ou un appareil piraté ne peut plus les lire. À lui seul, il ne rend pas le serveur « inattaquable ». Les bonnes pratiques : pas de redirection de port vers internet (accès à distance par un VPN), un pare-feu, des services joignables seulement par le proxy, des mots de passe longs et uniques avec double authentification, des mises à jour régulières, et des sauvegardes testées.

**Attention au certificat racine.** Une fois installé sur un téléphone, il lui fait confiance pour **tout** site signé par cette autorité. La clé correspondante vit dans le volume de données de Caddy sur le portable : ne la copie nulle part, ne la mets pas dans une sauvegarde partagée, et protège le portable (mot de passe, disque chiffré si possible). L'option B (vrai domaine) évite ce point : rien à installer sur les appareils. La télé reste en `http://home.lan` : elle n'a donc pas de certificat, et `home.lan` ne contient aucune donnée sensible.

### 23.3 Passer par les noms

Pour que l'accès se fasse toujours par les noms (et donc avec https), fais écouter chaque service Docker sur `127.0.0.1` (par exemple `"127.0.0.1:8090:8090"` dans son `docker-compose.yml`), un service à la fois, en vérifiant après chaque changement que son nom `.lan` répond toujours.

## 24. Alexa et Home Assistant

À faire quand Home Assistant a déjà tes appareils (phase 13.3 et 20.3). Il y a trois façons de relier Alexa. Choisis selon ton budget :

| Option | Prix | Ce que ça donne | Remarque |
|---|---|---|---|
| **A. Home Assistant Cloud** (Nabu Casa) | environ 6,50 €/mois | « Alexa, allume le salon » en quelques clics, sans ouvrir ton réseau | La plus simple. Aide aussi à financer Home Assistant. |
| **B. Matter avec Matterbridge** | gratuit | Les appareils de Home Assistant apparaissent dans Alexa comme des appareils Matter, en local | Il faut un Echo compatible Matter. Plus long à régler. |
| **C. alexa_media_player** (HACS) | gratuit | Home Assistant fait **parler** les Echo (annonces), lit minuteurs et alarmes | Se connecte avec ton compte Amazon : plus fragile, à garder en complément. |

### Option A en bref

1. Dans Home Assistant : Paramètres, **Home Assistant Cloud**, crée le compte (mot de passe saisi par toi) et abonne-toi.
2. Dans le cloud : active **Alexa** et choisis les appareils à exposer (laisse tomber les capteurs inutiles).
3. Dans l'application **Alexa** : Skills, cherche **Home Assistant Cloud**, active-le et connecte-toi avec le compte Nabu Casa. Lance ensuite « Découvrir les appareils ».

### Option B en bref

Demande à Claude Code d'installer Matterbridge en Docker (réseau `host`) avec le plugin qui expose Home Assistant en Matter, **en lisant la documentation actuelle du projet avant de le faire**. Puis dans l'application Alexa : Appareils, Ajouter, Matter, scanne le code que Matterbridge affiche. Ne choisis que les appareils utiles.

### Ce que tu peux faire avec Alexa

- « Alexa, allume le salon », « Alexa, ferme le volet de la chambre ».
- **« Alexa, allume la tour »** : dans Home Assistant, ajoute l'intégration **Wake on LAN** avec la MAC de la tour (voir « Allumer la tour à distance » plus bas), expose l'interrupteur à Alexa.
- **Scènes** : « Alexa, mode film » (lumières basses, volet fermé). Crée la scène dans Home Assistant et expose-la.
- **Annonces** (option C) : « La sauvegarde du samedi est terminée » ou « La tour est restée éteinte, la sauvegarde n'a pas eu lieu », envoyées sur l'Echo du salon par une automatisation Home Assistant déclenchée par ntfy.
- **Routines** Alexa : « Bonne nuit » éteint tout, « Je pars » éteint les lumières et ferme les volets.
- **Liste de courses** commune avec Alexa (via une liste Nextcloud, plus tard).

### Allumer la tour à distance (Wake-on-LAN)

1. Sur la tour, relève l'adresse physique de la carte Ethernet : `ipconfig /all` (ligne « Adresse physique »).
2. Active dans le BIOS « Wake on LAN » (ou « Power on by PCI-E »), puis dans Windows, Gestionnaire de périphériques, carte réseau, onglet Gestion de l'alimentation : « Autoriser ce périphérique à sortir l'ordinateur de veille » et « Seulement autoriser un paquet magique ». Désactive aussi le démarrage rapide de Windows (Options d'alimentation).
3. Dans Home Assistant : Paramètres, Appareils et services, **Ajouter une intégration**, **Wake on LAN**, saisis la MAC. Un interrupteur « Tour » apparaît : ajoute-le dans `appareils.json` pour l'avoir sur `admin.lan`.
4. Teste d'abord à la maison, tour éteinte, avant de compter dessus à distance.

## 25. Idées pour la suite

Principe : on réutilise l'existant avant d'ajouter un service. La liste complète est dans `homelab-roadmap.md`.

- **D'abord** : test de restauration (17.6), phase 18, alerte « sauvegarde manquante » (moniteur Push d'Uptime Kuma appelé par le script), alerte de coupure de courant, sauvegarde hors de chez toi.
- **Recettes** : application **Cookbook** de Nextcloud. **Calendrier et contacts** : applications Nextcloud, synchronisées avec les téléphones.
- **Classement des documents** : Paperless apprend tout seul à étiqueter (algorithme « auto »), sans IA.
- **Livres audio, BD, livres** : bibliothèque « Livres » de Jellyfin (avec son extension). **Podcasts** : MeTube dans le dossier `podcasts`.
- **Contrôle parental** : dans AdGuard (clients par appareil, services bloqués, recherche sécurisée, horaires).
- **Confort** : page Wi-Fi invités (QR code sur `home.lan`), raccourci « Ajouter à l'écran d'accueil » sur les téléphones des parents.

### Liste de contrôle des améliorations

- [ ] Pages v2 installées, service `homelab-api` actif, route `/api` dans Caddy
- [ ] Jeton Home Assistant créé (par toi) et `appareils.json` rempli
- [ ] Bouton de sauvegarde testé (une fois, sur ta décision) et historique visible
- [ ] Dossiers `vod`, `cuisine`, `tutos`… créés, MeTube demande le dossier, bibliothèques Jellyfin créées
- [ ] HTTPS en place, certificat installé sur tes appareils et ceux des parents, redirection activée
- [ ] Alexa reliée et testée

## 26. Travailler à distance sans rien casser

À lire avant de pousser des changements quand tu n'es pas à la maison.

**Se fait à distance** : phases 20.1 à 20.3, 21, 22, 23.1 (étapes 1 à 3, avec le http conservé), alertes et surveillance.
**Se fait chez toi** : phase 18 (sécurité), phase 19 (redémarrage), 23.2 (redirection https), 23.3 (ports des services), tout ce qui touche au réseau, au DNS, à Tailscale, à la Freebox, aux mises à jour qui redémarrent la machine, et la tour (BIOS, Wake-on-LAN).

### 26.1 Avant de commencer

- Console Tailscale : **désactive l'expiration de clé** du portable.
- Après chaque étape : `docker ps` (aucun conteneur arrêté), `admin.lan` tout vert, puis 5 minutes d'observation.

### 26.2 Recharger Caddy sans risque

Pour **toute** modification du Caddyfile (20.2, 23.1…), n'utilise pas `caddy reload` directement mais le script du pack :

```bash
bash ~/pack-maison/pages-maison/recharger-caddy-sur.sh
```

Il copie le Caddyfile en `Caddyfile.avant-<date>`, le valide, recharge, teste `home.lan`, `admin.lan` et `films.lan`, et **remet l'ancienne version tout seul** si un test échoue (avec un message ntfy). Dans les prompts à Claude Code, ajoute : « modifie le Caddyfile, puis recharge uniquement avec recharger-caddy-sur.sh ».

### 26.3 Garder tout en ligne en ton absence

Demande à Claude Code, une étape à la fois :

```
1) Vérifie avec "docker ps -a --format '{{.Names}} {{.Status}}'" que chaque conteneur du homelab a "restart: unless-stopped" (docker inspect -f '{{.HostConfig.RestartPolicy.Name}}'). Liste ceux qui ne l'ont pas, corrige-les un par un, et vérifie que homelab-api.service a Restart=always. Ne redémarre rien d'autre.
```

```
2) Crée un garde-fou : un script ~/homelab/garde-fou.sh et un minuteur systemd utilisateur toutes les 2 minutes qui relance (docker start / docker restart) un conteneur du homelab arrêté ou "unhealthy", et envoie un message sur http://127.0.0.1:8089/homelab quand il en relance un. Pas de nouveau conteneur. Montre-moi le script avant de l'activer.
```

Dans Uptime Kuma, crée **un moniteur par service** avec notification ntfy au bout de 2 minutes. Installe l'application **ntfy** sur ton téléphone et abonne-la au sujet `homelab` : sinon tu ne verras aucune alerte au boulot. Pour être prévenu quand le **portable lui-même** est injoignable, ajoute un moniteur de type « battement de cœur » extérieur (Healthchecks.io, gratuit) que le portable appelle toutes les 5 minutes.

### 26.4 Tenir un journal

Demande à Claude Code de noter chaque modification dans `~/homelab/CHANGELOG.md` (date, quoi, comment annuler) et de copier les fichiers modifiés dans `~/homelab/avant-<date>/` avant chaque grosse étape.
