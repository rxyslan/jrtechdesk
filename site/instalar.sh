#!/usr/bin/env bash
# Instala ou atualiza o site de download no CT 106. Rodar como root, de dentro da pasta site/:
#   bash instalar.sh
# Pode rodar de novo a qualquer momento (atualiza a página e reinicia o Caddy).
set -euo pipefail
cd "$(dirname "$0")"

BASE=/opt/jrtechdesk-site
CADDY_IMAGEM="caddy:2.10.0"

command -v jq >/dev/null && command -v curl >/dev/null || {
  apt-get update -qq
  apt-get install -y -qq jq curl
}

mkdir -p "$BASE/releases"
rm -rf "$BASE/www.novo"
cp -r www "$BASE/www.novo"
rm -rf "$BASE/www"
mv "$BASE/www.novo" "$BASE/www"
install -m 0644 Caddyfile "$BASE/Caddyfile"
install -m 0755 sincronizar.sh "$BASE/sincronizar.sh"
install -m 0644 jrtechdesk-site-sync.service jrtechdesk-site-sync.timer /etc/systemd/system/
chmod -R a+rX "$BASE"

systemctl daemon-reload
systemctl enable --now jrtechdesk-site-sync.timer
systemctl start jrtechdesk-site-sync.service

docker rm -f jrtechdesk-site >/dev/null 2>&1 || true
docker run -d --name jrtechdesk-site --restart unless-stopped --network host \
  -v "$BASE":/site:ro \
  -v "$BASE/Caddyfile":/etc/caddy/Caddyfile:ro \
  -v jrtechdesk-site-dados:/data \
  -v jrtechdesk-site-config:/config \
  "$CADDY_IMAGEM"

echo "Site instalado. Versão publicada: $(jq -r .versao "$BASE/download/versao.json")"
