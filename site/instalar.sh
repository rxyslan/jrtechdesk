#!/usr/bin/env bash
# Instala ou atualiza o site de download no CT 106. Rodar como root:
#   bash instalar.sh
# Pode rodar de novo a qualquer momento (atualiza a página e reinicia o Caddy).
#
# Tudo o que pode falhar é preparado antes de parar o Caddy em uso. Depois que ele para,
# qualquer erro chama voltar(), que restaura página, Caddyfile e contêiner anteriores.
# O sincronizador e as units do systemd só são trocados depois que o Caddy novo serviu
# a página nova.
set -Eeuo pipefail
cd "$(dirname "$0")"

BASE=${JRTECH_SITE_BASE:-/opt/jrtechdesk-site}
CADDY_IMAGEM="caddy:2.10.0"
CONTAINER=jrtechdesk-site
UNITS=${JRTECH_SITE_UNITS:-/etc/systemd/system}
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
manter_novo=
limpar_preparo= # só remove a página preparada se a troca nem começou
trap 'if [[ -z "$manter_novo" ]]; then rm -rf -- "$novo"; fi
  if [[ -n "$limpar_preparo" ]]; then rm -rf -- "${BASE:?}/$www_nova" "$BASE/www.novo"; fi' EXIT

# --- Preparação: nada do que está no ar muda aqui. ---
limpar_preparo=1
rm -f -- "$BASE/www.novo"
mkdir -p "$BASE/$www_nova/img"
install -m 0644 www/img/*.png "$BASE/$www_nova/img/"
install -m 0644 www/estilo.css www/versao.js www/index.html "$BASE/$www_nova/"
install -m 0644 Caddyfile "$novo/"
install -m 0755 sincronizar.sh "$novo/"
install -m 0644 jrtechdesk-site-sync.service jrtechdesk-site-sync.timer "$novo/"
hash_index=$(sha256sum "$BASE/$www_nova/index.html" | cut -d' ' -f1)
# Identificador só do contêiner novo: a checagem final só aceita resposta que venha dele,
# e não de outro processo que esteja ocupando a porta 80.
site_id=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
[[ ${#site_id} -eq 32 ]]

docker run --rm -e JRTECH_SITE_ID=validacao -v "$novo/Caddyfile":/etc/caddy/Caddyfile:ro \
  "$CADDY_IMAGEM" caddy validate --config /etc/caddy/Caddyfile

ln -sT "$www_nova" "$BASE/www.novo"
www_legado=   # www como pasta comum (instalação antiga): vira www-legado-<id>
www_anterior= # www já era link: para onde apontava
if [[ -L "$BASE/www" ]]; then
  www_anterior=$(readlink "$BASE/www")
fi
caddyfile_backup=
if [[ -f "$BASE/Caddyfile" ]]; then
  caddyfile_backup="$novo/Caddyfile.anterior"
  cp -p "$BASE/Caddyfile" "$caddyfile_backup"
fi

# Se o Docker não responder aqui, o script para antes de mexer em qualquer coisa.
cid=$(docker ps -a -q --no-trunc --filter "name=^/${CONTAINER}\$")
anterior=
novo_id=
em_recuperacao=

# --- Recuperação: cada passo é tentado mesmo se um anterior falhar. ---
voltar() {
  # Só o shell principal recupera, e uma vez só (com set -E o trap também dispara em
  # substituições de comando).
  [[ "$BASHPID" == "$$" ]] || exit 1
  [[ -z "$em_recuperacao" ]] || exit 1
  em_recuperacao=1
  trap - ERR INT TERM HUP
  set +e
  local falhou=
  echo "A instalação falhou ou foi interrompida. Voltando à instalação anterior." >&2
  # Remove só um contêiner criado por esta execução, nunca o original ($cid).
  if [[ -z "$novo_id" ]]; then
    novo_id=$(docker ps -a -q --no-trunc --filter "name=^/${CONTAINER}\$" 2>/dev/null)
    [[ "$novo_id" != "$cid" ]] || novo_id=
  fi
  if [[ -n "$novo_id" ]]; then
    docker logs --tail 20 "$novo_id" >&2 2>&1
    docker rm -f "$novo_id" >/dev/null 2>&1 || falhou=1
  fi
  if [[ -n "$www_legado" && -d "$BASE/$www_legado" ]]; then
    { [[ ! -e "$BASE/www" ]] || rm -f -- "$BASE/www"; } && mv -T "$BASE/$www_legado" "$BASE/www" || falhou=1
  elif [[ -n "$www_legado" ]]; then
    : # o mv da pasta legada não chegou a acontecer: www continua a original
  elif [[ -n "$www_anterior" ]]; then
    ln -sfnT "$www_anterior" "$BASE/www.novo" && mv -T "$BASE/www.novo" "$BASE/www" || falhou=1
  fi
  if [[ -n "$caddyfile_backup" ]]; then
    cp -p "$caddyfile_backup" "$BASE/Caddyfile.restaurando" &&
      mv -T "$BASE/Caddyfile.restaurando" "$BASE/Caddyfile" || falhou=1
  fi
  if [[ -n "$anterior" ]]; then
    # Pelo ID original: funciona tenha ou não chegado a ser renomeado ou parado.
    docker rename "$cid" "$CONTAINER" >/dev/null 2>&1
    docker start "$cid" >/dev/null || falhou=1
    [[ "$(docker ps -q --no-trunc --filter "id=$cid" --filter "name=^/${CONTAINER}\$")" == "$cid" ]] || falhou=1
  fi
  [[ -f "$BASE/www/index.html" ]] || falhou=1
  if [[ -n "$falhou" ]]; then
    manter_novo=1
    echo "ATENÇÃO: a recuperação não terminou. Backup do Caddyfile em $novo;" \
      "página nova em $BASE/$www_nova; contêiner anterior: ${anterior:-nenhum}." >&2
  else
    rm -f -- "$BASE/www.novo"
    rm -rf -- "${BASE:?}/$www_nova"
  fi
  exit 1
}
trap voltar ERR INT TERM HUP
limpar_preparo=

# --- Troca. A partir daqui, qualquer erro ou interrupção chama voltar(). ---
if [[ -n "$cid" ]]; then
  anterior="$CONTAINER-anterior-${cid:0:12}"
  docker rename "$CONTAINER" "$anterior"
  docker stop "$anterior" >/dev/null
fi
if [[ -d "$BASE/www" && ! -L "$BASE/www" ]]; then
  # Nome registrado antes do mv: se um sinal chegar no meio, voltar() olha o disco.
  www_legado="www-legado-$id_nova"
  mv -T "$BASE/www" "$BASE/$www_legado"
fi
mv -T "$BASE/www.novo" "$BASE/www"
mv -T "$novo/Caddyfile" "$BASE/Caddyfile"

novo_id=$(docker run -d --name "$CONTAINER" --restart unless-stopped --network host \
  --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
  -e JRTECH_SITE_ID="$site_id" \
  -v "$BASE":/site:ro \
  -v "$BASE/Caddyfile":/etc/caddy/Caddyfile:ro \
  -v jrtechdesk-site-dados:/data \
  -v jrtechdesk-site-config:/config \
  "$CADDY_IMAGEM")

# Aceita só: curl sem erro, status 200, identificador deste contêiner e a página nova.
servindo=
for _ in $(seq 1 15); do
  if status=$(curl -sS -o "$novo/resposta.html" -D "$novo/cabecalhos" -w '%{http_code}' \
      --max-time 3 -H "Host: $HOST_PUBLICO" http://127.0.0.1/ 2>/dev/null) &&
    [[ "$status" == 200 ]] &&
    tr -d '\r' <"$novo/cabecalhos" | grep -qi "^x-jrtechdesk-site: $site_id\$" &&
    [[ "$(sha256sum "$novo/resposta.html" | cut -d' ' -f1)" == "$hash_index" ]]; then
    servindo=1
    break
  fi
  sleep 1
done
[[ -n "$servindo" ]] || voltar
trap - ERR INT TERM HUP

# --- Caddy novo confirmado. ---
if [[ -n "$anterior" ]]; then
  docker rm "$anterior" >/dev/null || echo "Não foi possível remover o contêiner anterior: $anterior" >&2
fi
# Guarda só a página atual e a anterior.
manter_www=${www_legado:-$www_anterior}
for pasta in "$BASE"/www-*; do
  nome=${pasta##*/}
  if [[ -d "$pasta" && "$nome" != "$www_nova" && "$nome" != "$manter_www" ]]; then
    rm -rf -- "$pasta"
  fi
done

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
