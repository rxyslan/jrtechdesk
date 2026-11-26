# Site de download do JrTechDesk

Página pública em `https://baixar.desbloqueiorepidclass.com.br`, servida pelo CT 106
(`192.168.15.250`), o mesmo servidor do hbbs/hbbr.

| Arquivo | Função |
|---|---|
| `www/` | A página (HTML, CSS, imagens). `versao.js` mostra a versão lendo `/download/versao.json`. |
| `Caddyfile` | Servidor web Caddy: HTTPS automático (Let's Encrypt), `/` = página, `/download/` = instaladores. |
| `sincronizar.sh` | Baixa os instaladores da release mais recente do GitHub, confere o SHA-256 de cada um e só então troca a versão publicada. |
| `jrtechdesk-site-sync.*` | Timer do systemd que volta a rodar `sincronizar.sh` 10 min após a última execução. |
| `instalar.sh` | Instala ou atualiza tudo no CT 106. |

## Como funciona

- Publique a release com uma tag nova. O timer consulta `releases/latest` (sem rascunhos ou
  pré-releases) e publica a versão após baixar e validar os arquivos.
- O timer faz até seis consultas por hora à API do GitHub. O limite padrão sem autenticação
  é de 60 por hora, compartilhado pelas consultas que saem do mesmo IP público.
- Os arquivos ficam em `/opt/jrtechdesk-site/releases/<tag>/`; `/opt/jrtechdesk-site/download`
  é um link para a versão atual, trocado de uma vez só depois que tudo baixou e conferiu.
  Ficam guardadas a versão atual e a anterior (~310 MB). A próxima atualização precisa de
  espaço temporário para mais uma release (~155 MB). Se faltar espaço ou algum arquivo
  falhar, o link continua apontando para a versão que já estava publicada.
- O Caddy roda no Docker (`jrtechdesk-site`, rede do host, portas 80 e 443). Os certificados
  ficam no volume `jrtechdesk-site-dados`.

## Requisitos de rede

- DNS (Locaweb): `baixar.desbloqueiorepidclass.com.br` tipo A → `200.205.43.42`.
- MikroTik: NAT TCP 80 e 443 → `192.168.15.250`. A porta 80 precisa chegar ao Caddy para o
  desafio HTTP-01 do Let's Encrypt. A porta 443 é necessária para o público abrir o site
  em HTTPS, mesmo quando o certificado já foi emitido.
- Sem hairpin NAT: de dentro da rede, testar com
  `curl --resolve baixar.desbloqueiorepidclass.com.br:443:192.168.15.250 https://baixar.desbloqueiorepidclass.com.br/`.

## Instalar ou atualizar

```sh
ssh root@192.168.15.250 'mkdir -p /root/jrtechdesk-site-src'
scp -r site/* root@192.168.15.250:/root/jrtechdesk-site-src/
ssh root@192.168.15.250 'bash /root/jrtechdesk-site-src/instalar.sh'
```

O instalador valida o Caddyfile antes de substituir o contêiner. Se o GitHub estiver
indisponível na instalação, o Caddy pode servir os arquivos já publicados enquanto o timer
tenta sincronizar novamente.

## Comandos úteis no CT 106

```sh
systemctl start jrtechdesk-site-sync.service    # sincronizar agora
journalctl -u jrtechdesk-site-sync.service -n 20
docker logs --tail 50 jrtechdesk-site
cat /opt/jrtechdesk-site/download/versao.json
```
