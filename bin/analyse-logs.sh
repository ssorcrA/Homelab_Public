#!/bin/bash
# Usage : analyse-logs.sh <nom_du_conteneur> [lignes]
C="${1:?Nom du conteneur (ex: immich_server)}"
N="${2:-200}"
(cd ~/homelab/ia && docker compose up -d ollama) >/dev/null
sleep 8
docker logs --tail "$N" "$C" 2>&1 | docker exec -i ollama ollama run llama3.2:3b \
  "Voici les dernières lignes de logs d'un service. Dis en français, en 10 lignes maximum, s'il y a une erreur, laquelle, et quoi vérifier en premier."
(cd ~/homelab/ia && docker compose down) >/dev/null
