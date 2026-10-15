#!/usr/bin/env bash
# Fabrique, à partir du certificat racine de Caddy (pages/home/ca.crt), les fichiers d'installation
# servis par http://home.lan/certificat.html :
#   maison-ca.bat           Windows (certutil, magasin « Autorités de certification racines » de l'ordinateur)
#   maison-ca-mac.sh        Mac (security add-trusted-cert)
#   maison-ca-linux.sh      Linux (/usr/local/share/ca-certificates + update-ca-certificates)
#   maison-ca.mobileconfig  iPhone / iPad (profil non signé, contenant seulement le certificat)
#   ca-info.json            empreinte SHA-256 et dates, affichées sur la page
# Usage (sans sudo) : bash generer-certificat.sh   À relancer si le certificat racine change.
# Seul le certificat PUBLIC est utilisé : la clé (root.key) ne quitte jamais le volume de Caddy.
set -euo pipefail

PAGES="${PAGES:-$HOME/homelab/caddy/pages/home}"
CRT="$PAGES/ca.crt"

if [ ! -s "$CRT" ]; then
  docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > "$CRT.tmp"
  mv "$CRT.tmp" "$CRT"; chmod 644 "$CRT"
fi
openssl x509 -in "$CRT" -noout >/dev/null || { echo "$CRT n'est pas un certificat valide."; exit 1; }
if grep -q PRIVATE "$CRT"; then echo "$CRT contient une clé privée : arrêt."; exit 1; fi

EMPREINTE="$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 | cut -d= -f2)"
SUJET="$(openssl x509 -in "$CRT" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= *//p')"
FIN="$(date -d "$(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2)" +%Y-%m-%d)"
PEM="$(openssl x509 -in "$CRT")"                       # forme propre, sans texte autour
DER64="$(openssl x509 -in "$CRT" -outform der | base64 -w0)"
H="$(printf '%s' "$EMPREINTE" | tr -d ':' | tr 'A-F' 'a-f')"
uuid() { local x; x="$(printf '%s%s' "$1" "$H" | sha256sum | cut -c1-32)"; echo "${x:0:8}-${x:8:4}-${x:12:4}-${x:16:4}-${x:20:12}" | tr 'a-f' 'A-F'; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- Windows (.bat, fins de ligne CRLF)
{
cat <<EOF
@echo off
REM ==========================================================================
REM  Installe le certificat de la maison ("$SUJET")
REM  dans les "Autorités de certification racines de confiance" de CET ORDINATEUR.
REM
REM  Ce que fait ce fichier, et rien d'autre :
REM   1. vérifie qu'il est lancé en administrateur (clic droit, "Exécuter en tant qu'administrateur") ;
REM   2. écrit le certificat ci-dessous dans un fichier temporaire ;
REM   3. l'ajoute au magasin "Root" avec la commande Windows certutil ;
REM   4. supprime le fichier temporaire.
REM  Le certificat ne sert qu'aux adresses .lan de la maison.
REM  Empreinte SHA-256 attendue (à comparer avec la page certificat.html) :
REM   $EMPREINTE
REM  Pour le retirer plus tard : certmgr.msc, ou en administrateur :
REM   certutil -delstore Root "$SUJET"
REM ==========================================================================
net session >nul 2>&1
if errorlevel 1 (
  echo Ce fichier doit etre lance en administrateur :
  echo clic droit sur maison-ca.bat, puis "Executer en tant qu'administrateur".
  pause
  exit /b 1
)
set "F=%TEMP%\\maison-ca.crt"
> "%F%" (
EOF
printf '%s\n' "$PEM" | sed 's/^/  echo /'
cat <<'EOF'
)
certutil -addstore -f Root "%F%"
set "R=%ERRORLEVEL%"
del "%F%" >nul 2>&1
echo.
if "%R%"=="0" (
  echo Certificat installe. Ferme puis rouvre le navigateur.
) else (
  echo Echec de l'installation, code %R%.
)
pause
EOF
} | sed 's/$/\r/' > "$TMP/maison-ca.bat"

# ---------------------------------------------------------------- Mac
cat > "$TMP/maison-ca-mac.sh" <<EOF
#!/bin/bash
# Installe le certificat de la maison ("$SUJET") comme autorité de confiance du Mac.
# Ce que fait ce script, et rien d'autre :
#   1. écrit le certificat ci-dessous dans un fichier temporaire ;
#   2. l'ajoute au trousseau Système avec la confiance « racine » (security add-trusted-cert) ;
#   3. supprime le fichier temporaire.
# Lancement (Terminal) :  sudo bash ~/Downloads/maison-ca-mac.sh   (ton mot de passe du Mac est demandé)
# Empreinte SHA-256 attendue : $EMPREINTE
# Pour le retirer : Trousseau d'accès, trousseau « Système », supprimer « $SUJET ».
set -e
[ "\$(id -u)" -eq 0 ] || { echo "Lance-le avec sudo : sudo bash \$0"; exit 1; }
F="\$(mktemp -t maison-ca).crt"
cat > "\$F" <<'CERT'
$PEM
CERT
security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "\$F"
rm -f "\$F"
echo "Certificat installé. Ferme puis rouvre le navigateur."
EOF

# ---------------------------------------------------------------- Linux
cat > "$TMP/maison-ca-linux.sh" <<EOF
#!/bin/sh
# Installe le certificat de la maison ("$SUJET") dans les autorités du système (Debian, Ubuntu…).
# Ce que fait ce script, et rien d'autre :
#   1. copie le certificat ci-dessous dans /usr/local/share/ca-certificates/maison-ca.crt ;
#   2. lance update-ca-certificates.
# Lancement :  sudo sh ~/Téléchargements/maison-ca-linux.sh
# Empreinte SHA-256 attendue : $EMPREINTE
# Firefox et Chrome sous Linux ont parfois leur propre magasin : si le cadenas manque,
# importe ca.crt dans leurs réglages (Certificats > Autorités).
# Pour le retirer : sudo rm /usr/local/share/ca-certificates/maison-ca.crt && sudo update-ca-certificates --fresh
set -e
[ "\$(id -u)" -eq 0 ] || { echo "Lance-le avec sudo : sudo sh \$0"; exit 1; }
mkdir -p /usr/local/share/ca-certificates
cat > /usr/local/share/ca-certificates/maison-ca.crt <<'CERT'
$PEM
CERT
chmod 644 /usr/local/share/ca-certificates/maison-ca.crt
update-ca-certificates
echo "Certificat installé. Ferme puis rouvre le navigateur."
EOF

# ---------------------------------------------------------------- iPhone / iPad
cat > "$TMP/maison-ca.mobileconfig" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.security.root</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>lan.maison.ca.certificat</string>
      <key>PayloadUUID</key><string>$(uuid cert)</string>
      <key>PayloadDisplayName</key><string>$SUJET</string>
      <key>PayloadCertificateFileName</key><string>maison-ca.cer</string>
      <key>PayloadContent</key><data>$DER64</data>
    </dict>
  </array>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>lan.maison.ca</string>
  <key>PayloadUUID</key><string>$(uuid profil)</string>
  <key>PayloadDisplayName</key><string>Cadenas de la maison</string>
  <key>PayloadDescription</key><string>Certificat des adresses .lan de la maison. Empreinte SHA-256 : $EMPREINTE</string>
  <key>PayloadOrganization</key><string>Maison</string>
  <key>PayloadRemovalDisallowed</key><false/>
</dict>
</plist>
EOF

# ---------------------------------------------------------------- empreinte pour la page
printf '{"sha256": "%s", "nom": "%s", "expire": "%s"}\n' "$EMPREINTE" "$SUJET" "$FIN" > "$TMP/ca-info.json"

for f in maison-ca.bat maison-ca-mac.sh maison-ca-linux.sh maison-ca.mobileconfig ca-info.json; do
  install -m 644 "$TMP/$f" "$PAGES/$f"
done
echo "Fichiers écrits dans $PAGES (empreinte $EMPREINTE)."
