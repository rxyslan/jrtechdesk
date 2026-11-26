#!/usr/bin/env bash
# Copia os instaladores da release mais recente do GitHub para o site de download.
# Roda a cada 10 min (jrtechdesk-site-sync.timer). Só troca a versão publicada depois
# que todos os arquivos baixaram e conferiram com o SHA-256 informado pelo GitHub.
set -euo pipefail

REPO="rxyslan/jrtechdesk"
BASE="${JRTECH_SITE_BASE:-/opt/jrtechdesk-site}"
ARQUIVOS=(
  JrTechDesk-suporte.exe
  JrTechDesk-completo.exe
  jrtechdesk-suporte.deb
  jrtechdesk-completo.deb
  jrtechdesk-suporte.pkg.tar.zst
  jrtechdesk-completo.pkg.tar.zst
  SHA256SUMS.txt
)

# Espaço que precisa sobrar no disco depois do download (o CT também roda hbbs/hbbr).
RESERVA_MB="${JRTECH_SITE_RESERVA_MB:-1024}"

# A pasta publicada tem o versao.json e todos os arquivos com o tamanho e o SHA-256
# registrados nele? (~155 MB de hash a cada execução, com prioridade baixa.)
publicacao_completa() {
  local pasta=$1 nome esperado hash
  [[ -f "$pasta/versao.json" ]] || return 1
  jq -e --arg t "$tag" '.tag == $t' "$pasta/versao.json" >/dev/null 2>&1 || return 1
  for nome in "${ARQUIVOS[@]}"; do
    esperado=$(jq -er --arg n "$nome" '.arquivos[$n].tamanho' "$pasta/versao.json" 2>/dev/null) || return 1
    [[ -f "$pasta/$nome" && ! -L "$pasta/$nome" && "$(stat -c %s "$pasta/$nome")" == "$esperado" ]] || return 1
    hash=$(jq -er --arg n "$nome" '.arquivos[$n].sha256' "$pasta/versao.json" 2>/dev/null) || return 1
    [[ "$(nice -n 19 sha256sum "$pasta/$nome" | cut -d' ' -f1)" == "$hash" ]] || return 1
  done
}

mkdir -p "$BASE/releases"
exec 9>"$BASE/.sincronizar.lock"
if ! flock -n 9; then
  echo "Já há uma sincronização em andamento."
  exit 0
fi

# Recupera o espaço de uma execução interrompida antes de consultar o GitHub.
rm -rf -- "$BASE"/releases/.baixando-* "$BASE/download.novo"
tmp=
trap 'if [[ -n "$tmp" ]]; then rm -rf -- "$tmp"; fi; rm -f -- "$BASE/download.novo"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

if ! json=$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 30 \
  -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest"); then
  echo "Falha ao consultar a release no GitHub. O timer tentará novamente." >&2
  exit 1
fi
tag=$(jq -er '.tag_name' <<<"$json")
publicada=$(jq -er '.published_at' <<<"$json")
[[ "$tag" =~ ^v[0-9A-Za-z.\-]+$ ]] || { echo "tag inesperada: $tag" >&2; exit 1; }

destino="$BASE/releases/$tag"
atual=$(readlink "$BASE/download" 2>/dev/null || true)
if [[ "$atual" == "releases/$tag" ]] && publicacao_completa "$destino"; then
  exit 0
fi
if [[ "$atual" == "releases/$tag" ]]; then
  for nome in "${ARQUIVOS[@]}" versao.json; do
    if [[ -d "$destino/$nome" && ! -L "$destino/$nome" ]]; then
      echo "$tag: $destino/$nome é um diretório; corrija à mão (nada foi baixado)." >&2
      exit 1
    fi
  done
  echo "$tag: a versão publicada está incompleta; baixando de novo." >&2
fi
if [[ -e "$BASE/download" && ! -L "$BASE/download" ]]; then
  echo "O caminho $BASE/download precisa ser um link simbólico." >&2
  exit 1
fi

declare -A urls hashes tamanhos
total=0
for nome in "${ARQUIVOS[@]}"; do
  if ! dados=$(jq -er --arg n "$nome" '
    [.assets[] | select(.name == $n)] | select(length == 1) | .[0]
    | select((.browser_download_url // "") | startswith("https://"))
    | select((.digest // "") | test("^sha256:[0-9a-f]{64}$"))
    | select(.size | type == "number" and . > 0 and . == floor)
    | [.browser_download_url, .digest, .size] | @tsv
  ' <<<"$json"); then
    echo "$tag: dados incompletos ou inválidos para $nome na release" >&2
    exit 1
  fi
  IFS=$'\t' read -r url digest tamanho <<<"$dados"
  urls[$nome]=$url
  hashes[$nome]=$digest
  tamanhos[$nome]=$tamanho
  total=$((total + tamanho))
done

disponivel=$(df -B1 --output=avail "$BASE/releases" | tail -n 1)
if (( disponivel < total + RESERVA_MB * 1048576 )); then
  echo "$tag: espaço insuficiente (precisa de $(( total / 1048576 )) MB + reserva de $RESERVA_MB MB). A versão publicada foi mantida." >&2
  exit 1
fi

tmp=$(mktemp -d "$BASE/releases/.baixando-$tag.XXXXXX")
arquivos_json="{}"
for nome in "${ARQUIVOS[@]}"; do
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 \
    --retry 2 --retry-max-time 120 --max-filesize "${tamanhos[$nome]}" -o "$tmp/$nome" "${urls[$nome]}"
  tamanho=$(stat -c %s "$tmp/$nome")
  if [[ "$tamanho" != "${tamanhos[$nome]}" ]]; then
    echo "$tag: tamanho de $nome não confere" >&2
    exit 1
  fi
  obtido=$(sha256sum "$tmp/$nome" | cut -d' ' -f1)
  if [[ "sha256:$obtido" != "${hashes[$nome]}" ]]; then
    echo "$tag: SHA-256 de $nome não confere ($obtido, esperado ${hashes[$nome]})" >&2
    exit 1
  fi
  arquivos_json=$(jq --arg n "$nome" --arg h "$obtido" --argjson t "$tamanho" \
    '. + {($n): {sha256: $h, tamanho: $t}}' <<<"$arquivos_json")
done

if [[ "$atual" == "releases/$tag" && -d "$destino" ]]; then
  # Reparo da versão já publicada: troca só os arquivos com problema, um a um (mv é
  # atômico), sem apagar a pasta que o site está servindo nem mexer na versão anterior.
  jq -n --arg v "${tag#v}" --arg p "$publicada" --argjson a "$arquivos_json" \
    --arg t "$tag" '{versao: $v, tag: $t, publicada: $p, arquivos: $a}' >"$tmp/versao.json"
  chmod -R a+rX "$tmp"
  for nome in "${ARQUIVOS[@]}" versao.json; do
    if [[ -L "$destino/$nome" ]] || ! cmp -s "$tmp/$nome" "$destino/$nome"; then
      mv -fT "$tmp/$nome" "$destino/$nome"
      echo "$tag: $nome reparado"
    fi
  done
  if ! publicacao_completa "$destino"; then
    echo "$tag: o reparo não deixou a versão publicada íntegra" >&2
    exit 1
  fi
  exit 0
fi

jq -n --arg v "${tag#v}" --arg p "$publicada" --argjson a "$arquivos_json" \
  --arg t "$tag" '{versao: $v, tag: $t, publicada: $p, arquivos: $a}' >"$tmp/versao.json"
chmod -R a+rX "$tmp"
ln -sT "releases/$tag" "$BASE/download.novo"
rm -rf -- "$destino"
mv -T "$tmp" "$destino"
tmp=

# Troca atômica do link que o site serve.
mv -T "$BASE/download.novo" "$BASE/download"
echo "site de download agora em $tag"

# Guarda a versão que estava publicada, inclusive quando a nova tag é mais antiga.
for pasta in "$BASE"/releases/v*; do
  nome=${pasta##*/}
  if [[ -d "$pasta" && "$nome" =~ ^v[0-9A-Za-z.\-]+$ && "$nome" != "$tag" && "releases/$nome" != "$atual" ]]; then
    rm -rf -- "$pasta"
  fi
done
