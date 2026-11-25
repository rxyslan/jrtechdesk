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

json=$(curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/latest")
tag=$(jq -r '.tag_name' <<<"$json")
publicada=$(jq -r '.published_at' <<<"$json")
[[ "$tag" =~ ^v[0-9A-Za-z.\-]+$ ]] || { echo "tag inesperada: $tag" >&2; exit 1; }

destino="$BASE/releases/$tag"
if [[ "$(readlink "$BASE/download" 2>/dev/null)" == "releases/$tag" ]]; then
  exit 0
fi

tmp="$BASE/releases/.baixando-$tag"
rm -rf "$tmp"
mkdir -p "$tmp"
arquivos_json="{}"
for nome in "${ARQUIVOS[@]}"; do
  url=$(jq -r --arg n "$nome" '.assets[] | select(.name == $n) | .browser_download_url' <<<"$json")
  digest=$(jq -r --arg n "$nome" '.assets[] | select(.name == $n) | .digest' <<<"$json")
  if [[ -z "$url" || "$digest" != sha256:* ]]; then
    echo "$tag: falta $nome ou o hash dele na release" >&2
    rm -rf "$tmp"
    exit 1
  fi
  curl -fsSL --retry 3 -o "$tmp/$nome" "$url"
  obtido=$(sha256sum "$tmp/$nome" | cut -d' ' -f1)
  if [[ "sha256:$obtido" != "$digest" ]]; then
    echo "$tag: SHA-256 de $nome não confere ($obtido, esperado $digest)" >&2
    rm -rf "$tmp"
    exit 1
  fi
  tamanho=$(stat -c %s "$tmp/$nome")
  arquivos_json=$(jq --arg n "$nome" --arg h "$obtido" --argjson t "$tamanho" \
    '. + {($n): {sha256: $h, tamanho: $t}}' <<<"$arquivos_json")
done

jq -n --arg v "${tag#v}" --arg p "$publicada" --argjson a "$arquivos_json" \
  '{versao: $v, publicada: $p, arquivos: $a}' >"$tmp/versao.json"
chmod -R a+rX "$tmp"
rm -rf "$destino"
mv "$tmp" "$destino"

# Troca atômica do link que o site serve.
ln -sfn "releases/$tag" "$BASE/download.novo"
mv -T "$BASE/download.novo" "$BASE/download"
echo "site de download agora em $tag"

# Mantém só a versão atual e a anterior.
ls -1dt "$BASE"/releases/v* | tail -n +3 | xargs -r rm -rf
