# Site de download do JrTechDesk

Página pública em `https://baixar.desbloqueiorepidclass.com.br`, servida pelo CT 106
(`192.168.15.250`), o mesmo servidor do hbbs/hbbr.

| Arquivo | Função |
|---|---|
| `www/` | A página (HTML, CSS, imagens). `versao.js` mostra a versão lendo `/download/versao.json`. |
| `Caddyfile` | Servidor web Caddy: HTTPS automático (Let's Encrypt), `/` = página, `/download/` = instaladores. |
| `sincronizar.sh` | Baixa os instaladores da release mais recente do GitHub, confere o SHA-256 de cada um e só então troca a versão publicada. |
| `jrtechdesk-site-sync.*` | Timer do systemd que roda `sincronizar.sh` a cada 10 min. |
| `instalar.sh` | Instala ou atualiza tudo no CT 106. |

## Como funciona

- Publicar uma release no GitHub basta: em até 10 min o site passa a entregar a versão nova.
  Rascunhos e pré-releases não entram (a API `releases/latest` ignora os dois).
- Os arquivos ficam em `/opt/jrtechdesk-site/releases/<tag>/`; `/opt/jrtechdesk-site/download`
  é um link para a versão atual, trocado de uma vez só depois que tudo baixou e conferiu.
  Ficam guardadas a versão atual e a anterior (~310 MB).
- O Caddy roda no Docker (`jrtechdesk-site`, rede do host, portas 80 e 443). Os certificados
  ficam no volume `jrtechdesk-site-dados`.

## Requisitos de rede

- DNS (Locaweb): `baixar.desbloqueiorepidclass.com.br` tipo A → `200.205.43.42`.
- MikroTik: NAT TCP 80 e 443 → `192.168.15.250`. Sem isso o Let's Encrypt não emite o certificado.
- Sem hairpin NAT: de dentro da rede, testar com
  `curl --resolve baixar.desbloqueiorepidclass.com.br:443:192.168.15.250 https://baixar.desbloqueiorepidclass.com.br/`.

## Instalar ou atualizar

```sh
scp -r site root@192.168.15.250:/root/jrtechdesk-site-src
ssh root@192.168.15.250 'bash /root/jrtechdesk-site-src/instalar.sh'
```

## Comandos úteis no CT 106

```sh
systemctl start jrtechdesk-site-sync.service    # sincronizar agora
journalctl -u jrtechdesk-site-sync.service -n 20
docker logs --tail 50 jrtechdesk-site
cat /opt/jrtechdesk-site/download/versao.json
```
