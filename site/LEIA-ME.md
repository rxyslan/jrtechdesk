# Site de download do JrTechDesk

Página pública em `https://baixar.desbloqueiorepidclass.com.br`, servida pelo CT 106
(`192.168.15.250`), o mesmo servidor do hbbs/hbbr. O CT 106 responde só em HTTP (porta 80);
o HTTPS fica no Caddy de borda que já recebe as portas 80/443 públicas da rede.

| Arquivo | Função |
|---|---|
| `www/` | A página (HTML, CSS, imagens). `versao.js` mostra a versão lendo `/download/versao.json`. |
| `Caddyfile` | Caddy do CT 106, só HTTP: `/` = página, `/download/` = versão atual, `/versoes/<tag>/` = mesma coisa com a tag no caminho. |
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
- O Caddy roda no Docker (`jrtechdesk-site`, rede do host, porta 80).
- A sincronização só começa se sobrar pelo menos 1 GB livre depois do download
  (`JRTECH_SITE_RESERVA_MB`), para não apertar o disco do hbbs/hbbr.
- Se a pasta publicada perder algum arquivo, a próxima execução percebe e baixa de novo.
- A página troca os links dos técnicos e do código-fonte para a tag publicada
  (`/versoes/<tag>/...` e `tree/<tag>` no GitHub), então o pacote e o SHA256SUMS.txt
  são sempre da mesma versão.

## Requisitos de rede

- DNS (Locaweb): `baixar.desbloqueiorepidclass.com.br` tipo A → `200.205.43.42`.
- As portas 80/443 públicas continuam no Caddy de borda (atende outros domínios; não mexer
  no NAT). Nele, acrescentar:

  ```
  baixar.desbloqueiorepidclass.com.br {
      reverse_proxy 192.168.15.250:80
  }
  ```

  O Caddy de borda emite o certificado e redireciona HTTP → HTTPS sozinho.
- Teste de dentro da rede, direto no CT 106:
  `curl -H 'Host: baixar.desbloqueiorepidclass.com.br' http://192.168.15.250/`.

## Instalar ou atualizar

```sh
ssh root@192.168.15.250 'mkdir -p /root/jrtechdesk-site-src'
scp -r site/* root@192.168.15.250:/root/jrtechdesk-site-src/
ssh root@192.168.15.250 'bash /root/jrtechdesk-site-src/instalar.sh'
```

O instalador valida o Caddyfile antes de substituir o contêiner e só remove o contêiner
anterior depois que o novo responde à página em `http://127.0.0.1/`; se não responder,
volta ao anterior. Se o GitHub estiver
indisponível na instalação, o Caddy pode servir os arquivos já publicados enquanto o timer
tenta sincronizar novamente.

## Comandos úteis no CT 106

```sh
systemctl start jrtechdesk-site-sync.service    # sincronizar agora
journalctl -u jrtechdesk-site-sync.service -n 20
docker logs --tail 50 jrtechdesk-site
cat /opt/jrtechdesk-site/download/versao.json
```
