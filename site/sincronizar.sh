#!/usr/bin/env bash
# Copia os instaladores da release mais recente do GitHub para o site de download.
# Roda a cada 10 min (jrtechdesk-site-sync.timer). Só troca a versão publicada depois
# que todos os arquivos baixaram e conferiram com o SHA-256 informado pelo GitHub e o
# .exe conferiu também com o manifesto assinado pela chave de atualização da Jrtech.
# O domínio público distribui apenas a edição Suporte.
set -euo pipefail

REPO="rxyslan/jrtechdesk"
BASE="${JRTECH_SITE_BASE:-/opt/jrtechdesk-site}"
PACOTES=(
  JrTechDesk-suporte.exe
  jrtechdesk-suporte.deb
  jrtechdesk-suporte.pkg.tar.zst
)
MANIFESTO=jrtechdesk-suporte-update.json
# Baixados da release; o SHA256SUMS.txt publicado é gerado aqui, só com os PACOTES.
ARQUIVOS=("${PACOTES[@]}" "$MANIFESTO" "$MANIFESTO.sig")
PUBLICADOS=("${ARQUIVOS[@]}" SHA256SUMS.txt)
# Da época em que o site espelhava também o Completo: saem das pastas publicadas.
LEGADOS=(
  JrTechDesk-completo.exe
  jrtechdesk-completo.deb
  jrtechdesk-completo.pkg.tar.zst
  jrtechdesk-update.json
  jrtechdesk-update.json.sig
)

remover_legados() {
  local pasta nome
  for pasta in "$BASE"/releases/v*; do
    [[ -d "$pasta" && ! -L "$pasta" ]] || continue
    for nome in "${LEGADOS[@]}"; do
      if [[ -f "$pasta/$nome" && ! -L "$pasta/$nome" ]]; then
        rm -f -- "$pasta/$nome"
        echo "${pasta##*/}: $nome (Completo) removido"
      fi
    done
  done
}

# Chave pública de atualização (a mesma de src/update_metadata.rs, em DER/SPKI).
CHAVE_ATUALIZACAO="MCowBQYDK2VwAyEAxFG1sLnhRUmed9Nkp+TPBUVo+dAF9vSII0V6/0s5S90="
CONTEXTO_ASSINATURA=$'RustDesk update metadata v1\n'

# O manifesto do Suporte é assinado pela chave da Jrtech e lista o .exe desta tag
# com o mesmo tamanho e SHA-256 do arquivo baixado?
manifesto_confere() {
  local pasta=$1 chave
  chave=$(mktemp)
  printf -- '-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n' "$CHAVE_ATUALIZACAO" >"$chave"
  if ! { printf '%s' "$CONTEXTO_ASSINATURA"; cat "$pasta/$MANIFESTO"; } >"$pasta/.assinado" \
    || ! jq -er '.signature' "$pasta/$MANIFESTO.sig" | base64 -d >"$pasta/.assinatura" 2>/dev/null \
    || ! openssl pkeyutl -verify -pubin -inkey "$chave" -rawin -in "$pasta/.assinado" \
      -sigfile "$pasta/.assinatura" >/dev/null 2>&1; then
    rm -f -- "$chave" "$pasta/.assinado" "$pasta/.assinatura"
    return 1
  fi
  rm -f -- "$chave" "$pasta/.assinado" "$pasta/.assinatura"
  jq -e --arg t "$tag" --arg h "$(sha256sum "$pasta/JrTechDesk-suporte.exe" | cut -d' ' -f1)" \
    --argjson s "$(stat -c %s "$pasta/JrTechDesk-suporte.exe")" '
    .package_id == "jrtechdesk-suporte" and .release_id == $t
    and ([.artifacts[] | select(.file_name == "JrTechDesk-suporte.exe"
      and .sha256 == $h and .size == $s)] | length == 1)
  ' "$pasta/$MANIFESTO" >/dev/null
}

# Espaço que precisa sobrar no disco depois do download (o CT também roda hbbs/hbbr).
RESERVA_MB="${JRTECH_SITE_RESERVA_MB:-1024}"

# A pasta publicada tem o versao.json e todos os arquivos com o tamanho e o SHA-256
# registrados nele? (~155 MB de hash a cada execução, com prioridade baixa.)
publicacao_completa() {
  local pasta=$1 nome esperado hash
  [[ -f "$pasta/versao.json" ]] || return 1
  jq -e --arg t "$tag" '.tag == $t' "$pasta/versao.json" >/dev/null 2>&1 || return 1
  for nome in "${PUBLICADOS[@]}"; do
    esperado=$(jq -er --arg n "$nome" '.arquivos[$n].tamanho' "$pasta/versao.json" 2>/dev/null) || return 1
    [[ -f "$pasta/$nome" && ! -L "$pasta/$nome" && "$(stat -c %s "$pasta/$nome")" == "$esperado" ]] || return 1
    hash=$(jq -er --arg n "$nome" '.arquivos[$n].sha256' "$pasta/versao.json" 2>/dev/null) || return 1
    [[ "$(nice -n 19 sha256sum "$pasta/$nome" | cut -d' ' -f1)" == "$hash" ]] || return 1
  done
}

for comando in curl jq openssl sha256sum; do
  command -v "$comando" >/dev/null || { echo "falta o comando $comando" >&2; exit 1; }
done

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
  remover_legados
  exit 0
fi
if [[ "$atual" == "releases/$tag" ]]; then
  for nome in "${PUBLICADOS[@]}" versao.json; do
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

if ! manifesto_confere "$tmp"; then
  echo "$tag: o JrTechDesk-suporte.exe não confere com o manifesto assinado. A versão publicada foi mantida." >&2
  exit 1
fi
(cd "$tmp" && sha256sum -- "${PACOTES[@]}") >"$tmp/SHA256SUMS.txt"
arquivos_json=$(jq --arg h "$(sha256sum "$tmp/SHA256SUMS.txt" | cut -d' ' -f1)" \
  --argjson t "$(stat -c %s "$tmp/SHA256SUMS.txt")" \
  '. + {"SHA256SUMS.txt": {sha256: $h, tamanho: $t}}' <<<"$arquivos_json")

if [[ "$atual" == "releases/$tag" && -d "$destino" ]]; then
  # Reparo da versão já publicada: troca só os arquivos com problema, um a um (mv é
  # atômico), sem apagar a pasta que o site está servindo nem mexer na versão anterior.
  jq -n --arg v "${tag#v}" --arg p "$publicada" --argjson a "$arquivos_json" \
    --arg t "$tag" '{versao: $v, tag: $t, publicada: $p, arquivos: $a}' >"$tmp/versao.json"
  chmod -R a+rX "$tmp"
  for nome in "${PUBLICADOS[@]}" versao.json; do
    if [[ -L "$destino/$nome" ]] || ! cmp -s "$tmp/$nome" "$destino/$nome"; then
      mv -fT "$tmp/$nome" "$destino/$nome"
      echo "$tag: $nome reparado"
    fi
  done
  if ! publicacao_completa "$destino"; then
    echo "$tag: o reparo não deixou a versão publicada íntegra" >&2
    exit 1
  fi
  remover_legados
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
remover_legados

# Guarda a versão que estava publicada, inclusive quando a nova tag é mais antiga.
for pasta in "$BASE"/releases/v*; do
  nome=${pasta##*/}
  if [[ -d "$pasta" && "$nome" =~ ^v[0-9A-Za-z.\-]+$ && "$nome" != "$tag" && "releases/$nome" != "$atual" ]]; then
    rm -rf -- "$pasta"
  fi
done
