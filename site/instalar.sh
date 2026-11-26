#!/usr/bin/env bash
# Instala ou atualiza o site de download no CT 106. Rodar como root:
#   bash instalar.sh
# Pode rodar de novo a qualquer momento (atualiza a página e reinicia o Caddy).
#
# A página (www) e o Caddyfile mudam juntos: se o Caddy novo não servir a página, os dois
# voltam ao que estava antes, junto com o contêiner anterior. O sincronizador e as units do
# systemd só são trocados depois que o Caddy novo respondeu.
set -euo pipefail
cd "$(dirname "$0")"

BASE=/opt/jrtechdesk-site
CADDY_IMAGEM="caddy:2.10.0"
CONTAINER=jrtechdesk-site
UNITS=/etc/systemd/system
HOST_PUBLICO=baixar.desbloqueiorepidclass.com.br

umask 022
mkdir -p "$BASE/releases"
exec 9>"$BASE/.instalar.lock"
flock -n 9 || { echo "Já há uma instalação em andamento." >&2; exit 1; }

command -v jq >/dev/null && command -v curl >/dev/null || {
  apt-get update -qq
  apt-get install -y -qq jq curl
}

id_nova=$(date +%Y%m%d%H%M%S)-$$
www_nova="www-$id_nova"
novo=$(mktemp -d "$BASE/.instalando.XXXXXX")
trap 'rm -rf -- "$novo"' EXIT

mkdir -p "$BASE/$www_nova/img"
install -m 0644 www/img/*.png "$BASE/$www_nova/img/"
install -m 0644 www/estilo.css www/versao.js www/index.html "$BASE/$www_nova/"
install -m 0644 Caddyfile "$novo/"
install -m 0755 sincronizar.sh "$novo/"
install -m 0644 jrtechdesk-site-sync.service jrtechdesk-site-sync.timer "$novo/"

docker run --rm -e JRTECH_SITE_ID=validacao -v "$novo/Caddyfile":/etc/caddy/Caddyfile:ro \
  "$CADDY_IMAGEM" caddy validate --config /etc/caddy/Caddyfile

# Primeira instalação com www como pasta comum: vira uma pasta versionada para o
# link simbólico poder ser trocado de uma vez.
if [[ -d "$BASE/www" && ! -L "$BASE/www" ]]; then
  mv -T "$BASE/www" "$BASE/www-anterior-$id_nova"
  ln -sT "www-anterior-$id_nova" "$BASE/www"
fi
www_anterior=$(readlink "$BASE/www" 2>/dev/null || true)
caddyfile_anterior=
if [[ -f "$BASE/Caddyfile" ]]; then
  caddyfile_anterior="$novo/Caddyfile.anterior"
  cp -p "$BASE/Caddyfile" "$caddyfile_anterior"
fi

anterior=
if cid=$(docker container inspect --format '{{.Id}}' "$CONTAINER" 2>/dev/null); then
  anterior="$CONTAINER-anterior-${cid:0:12}"
  docker rename "$CONTAINER" "$anterior"
  if ! docker stop "$anterior"; then
    docker rename "$anterior" "$CONTAINER"
    exit 1
  fi
fi

voltar() {
  echo "O novo Caddy não serviu a página. Voltando à instalação anterior." >&2
  docker logs --tail 20 "$CONTAINER" >&2 2>/dev/null || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  if [[ -n "$www_anterior" ]]; then
    ln -sfnT "$www_anterior" "$BASE/www.novo" && mv -T "$BASE/www.novo" "$BASE/www"
  fi
  if [[ -n "$caddyfile_anterior" ]]; then
    mv -T "$caddyfile_anterior" "$BASE/Caddyfile"
  fi
  rm -rf -- "${BASE:?}/$www_nova"
  if [[ -n "$anterior" ]]; then
    docker rename "$anterior" "$CONTAINER"
    docker start "$CONTAINER"
  fi
  exit 1
}

ln -sfnT "$www_nova" "$BASE/www.novo" && mv -T "$BASE/www.novo" "$BASE/www"
mv -T "$novo/Caddyfile" "$BASE/Caddyfile"

# Identificador só deste contêiner: a checagem abaixo só aceita resposta que venha dele,
# e não de outro processo que esteja ocupando a porta 80.
site_id=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
docker run -d --name "$CONTAINER" --restart unless-stopped --network host \
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
  -e JRTECH_SITE_ID="$site_id" \
  -v "$BASE":/site:ro \
  -v "$BASE/Caddyfile":/etc/caddy/Caddyfile:ro \
  -v jrtechdesk-site-dados:/data \
  -v jrtechdesk-site-config:/config \
  "$CADDY_IMAGEM" >/dev/null || voltar

servindo=
for _ in $(seq 1 15); do
  cabecalhos=$(curl -sS -o /dev/null -D - --max-time 3 -H "Host: $HOST_PUBLICO" \
    http://127.0.0.1/ 2>/dev/null | tr -d '\r' || true)
  if grep -q '^HTTP/[0-9.]* 200' <<<"$cabecalhos" &&
    grep -qi "^x-jrtechdesk-site: $site_id\$" <<<"$cabecalhos"; then
    servindo=1
    break
  fi
  sleep 1
done
[[ -n "$servindo" ]] || voltar

if [[ -n "$anterior" ]]; then
  docker rm "$anterior" >/dev/null || echo "Não foi possível remover o contêiner anterior: $anterior" >&2
fi
# Guarda só a página atual e a anterior.
for pasta in "$BASE"/www-*; do
  nome=${pasta##*/}
  if [[ -d "$pasta" && "$nome" != "$www_nova" && "$nome" != "$www_anterior" ]]; then
    rm -rf -- "$pasta"
  fi
done

# Caddy novo confirmado: agora o sincronizador e as units.
mv -T "$novo/sincronizar.sh" "$BASE/sincronizar.sh"
for unit in jrtechdesk-site-sync.service jrtechdesk-site-sync.timer; do
  mv -T "$novo/$unit" "$UNITS/$unit"
done
systemctl daemon-reload
systemctl enable --now jrtechdesk-site-sync.timer
if ! systemctl start jrtechdesk-site-sync.service; then
  echo "Caddy iniciado, mas a sincronização falhou. O timer tentará novamente." >&2
  exit 1
fi
versao=$(jq -er '.versao' "$BASE/download/versao.json")
echo "Site instalado. Versão publicada: $versao"
