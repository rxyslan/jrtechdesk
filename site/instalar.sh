#!/usr/bin/env bash
# Instala ou atualiza o site de download no CT 106. Rodar como root:
#   bash instalar.sh
# Pode rodar de novo a qualquer momento (atualiza a página e reinicia o Caddy).
set -euo pipefail
cd "$(dirname "$0")"

BASE=/opt/jrtechdesk-site
CADDY_IMAGEM="caddy:2.10.0"
CONTAINER=jrtechdesk-site
UNITS=/etc/systemd/system

umask 022
mkdir -p "$BASE/releases"
exec 9>"$BASE/.instalar.lock"
flock -n 9 || { echo "Já há uma instalação em andamento." >&2; exit 1; }

command -v jq >/dev/null && command -v curl >/dev/null || {
  apt-get update -qq
  apt-get install -y -qq jq curl
}

novo=$(mktemp -d "$BASE/.instalando.XXXXXX")
units_novas=
trap 'rm -rf -- "$novo"; if [[ -n "$units_novas" ]]; then rm -rf -- "$units_novas"; fi' EXIT
units_novas=$(mktemp -d "$UNITS/.jrtechdesk-site.XXXXXX")

mkdir -p "$novo/www/img" "$BASE/www/img"
install -m 0644 www/img/*.png "$novo/www/img/"
install -m 0644 www/estilo.css www/versao.js www/index.html "$novo/www/"
install -m 0644 Caddyfile "$novo/"
install -m 0755 sincronizar.sh "$novo/"
install -m 0644 jrtechdesk-site-sync.service jrtechdesk-site-sync.timer "$units_novas/"

docker run --rm -v "$novo/Caddyfile":/etc/caddy/Caddyfile:ro \
  "$CADDY_IMAGEM" caddy validate --config /etc/caddy/Caddyfile

# Cada substituição é atômica. Uma sincronização em curso termina com o script que já abriu.
for arquivo in www/img/*.png www/estilo.css www/versao.js www/index.html sincronizar.sh; do
  mv -T "$novo/$arquivo" "$BASE/$arquivo"
done
for unit in jrtechdesk-site-sync.service jrtechdesk-site-sync.timer; do
  mv -T "$units_novas/$unit" "$UNITS/$unit"
done

anterior=
if id=$(docker container inspect --format '{{.Id}}' "$CONTAINER" 2>/dev/null); then
  cp -p "$BASE/Caddyfile" "$novo/Caddyfile.anterior"
  anterior="$CONTAINER-anterior-${id:0:12}"
  docker rename "$CONTAINER" "$anterior"
  if ! docker stop "$anterior"; then
    docker rename "$anterior" "$CONTAINER"
    exit 1
  fi
fi
if ! mv -T "$novo/Caddyfile" "$BASE/Caddyfile" ||
  ! docker run -d --name "$CONTAINER" --restart unless-stopped --network host \
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
  -v "$BASE":/site:ro \
  -v "$BASE/Caddyfile":/etc/caddy/Caddyfile:ro \
  -v jrtechdesk-site-dados:/data \
  -v jrtechdesk-site-config:/config \
  "$CADDY_IMAGEM"; then
  if [[ -n "$anterior" ]]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    mv -T "$novo/Caddyfile.anterior" "$BASE/Caddyfile"
    docker rename "$anterior" "$CONTAINER"
    docker start "$CONTAINER"
  fi
  exit 1
fi
# Só descarta o contêiner anterior depois que o novo servir a página de verdade.
servindo=
for _ in $(seq 1 15); do
  if curl -fsS --max-time 3 -H 'Host: baixar.desbloqueiorepidclass.com.br' http://127.0.0.1/ 2>/dev/null |
    grep -q 'JrTechDesk'; then
    servindo=1
    break
  fi
  sleep 1
done
if [[ -z "$servindo" ]]; then
  echo "O novo Caddy não respondeu em http://127.0.0.1/. Voltando ao anterior." >&2
  docker logs --tail 20 "$CONTAINER" >&2 || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  if [[ -n "$anterior" ]]; then
    mv -T "$novo/Caddyfile.anterior" "$BASE/Caddyfile"
    docker rename "$anterior" "$CONTAINER"
    docker start "$CONTAINER"
  fi
  exit 1
fi
if [[ -n "$anterior" ]]; then
  docker rm "$anterior" || echo "Não foi possível remover o contêiner anterior: $anterior" >&2
fi

systemctl daemon-reload
systemctl enable --now jrtechdesk-site-sync.timer
if ! systemctl start jrtechdesk-site-sync.service; then
  echo "Caddy iniciado, mas a sincronização falhou. O timer tentará novamente." >&2
  exit 1
fi
versao=$(jq -er '.versao' "$BASE/download/versao.json")
echo "Site instalado. Versão publicada: $versao"
