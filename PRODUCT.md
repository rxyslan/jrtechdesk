# Product

<!-- impeccable:product-schema 1 -->

Escopo: o site de download do JrTechDesk (`site/`). O resto deste repositório é o cliente
(fork do RustDesk) e não é descrito aqui.

## Platform

web

## Users

- **Cliente da Jrtech que vai receber atendimento remoto.** Empresa que usa ponto eletrônico
  ou sistema de gestão de pessoas da Jrtech, com alguém leigo na frente do computador (em
  geral Windows), ao telefone com o técnico. Chega pela página com o link que o técnico manda
  no WhatsApp durante a ligação. O trabalho: baixar o JrTechDesk Suporte, abrir, ditar o ID e
  a senha, e saber se pode confiar no que está fazendo.
- **Técnicos da Jrtech.** Usam a mesma página para baixar o Suporte e os pacotes Linux
  (Ubuntu/Debian e Arch), copiar comandos e conferir SHA-256.

## Product Purpose

Ser o único lugar oficial de onde o cliente baixa o JrTechDesk Suporte e entende, em poucos
segundos e sem jargão, o que fazer e o que o técnico poderá fazer no computador dele. Sucesso:
o cliente baixa o arquivo certo e passa ID e senha ao técnico sem travar, e sabe a quem não
passar.

## Positioning

É o suporte remoto da própria Jrtech, a empresa que já atende o ponto eletrônico e a gestão
de pessoas do cliente, rodando em servidores próprios da Jrtech, e não uma ferramenta genérica
de acesso remoto. O site existe para o atendimento já combinado com a Jrtech.

## Operating Context

- O cliente está numa ligação ou conversa de WhatsApp com o técnico, que o guia passo a passo.
- O endereço oficial é `https://baixar.desbloqueiorepidclass.com.br`, servido pelo CT 106 atrás
  do Caddy de borda. O site ainda não é divulgado amplamente; será quando o certificado de
  assinatura de código (Certum) sair.
- O `.exe` ainda não é assinado: o navegador e o SmartScreen podem avisar. A página manda parar
  e avisar o técnico ou procurar o suporte; nunca ensina a contornar o aviso.

## Capabilities and Constraints

- HTML/CSS/JS estáticos, sem build. CSP `default-src 'self'`: nada inline (sem `style=`, sem
  script inline) e nada de outros domínios (fontes, imagens e scripts ficam no próprio site).
  O `instalar.sh` copia os arquivos listados de `site/www`.
- `versao.js` preenche versão, data, tamanho e SHA-256 e troca os links para
  `/versoes/<tag>/` pelos atributos `data-arquivo`, `data-tamanho`, `data-versao`,
  `data-sha256`, `data-sha256-completo`, `data-hash-bloco` e `data-fonte`. `copiar.js` põe o
  botão Copiar em `pre[data-copiar]` e anuncia em `.aviso-copia`. A página precisa funcionar
  sem JavaScript, pelos links fixos `/download/<arquivo>`.
- O domínio público distribui só a edição Suporte (Windows `.exe`, `.deb`, `.pkg.tar.zst`).
- A seção Privacidade tem texto com efeito legal (LGPD): o texto completo só muda com
  revisão contra o código; os resumos visíveis precisam ser fiéis a ele.
- Indefinidos: razão social e CNPJ (adiados até o certificado), canal oficial de contato e de
  pedidos LGPD, prazo de retenção dos registros.

## Brand Commitments

- Nome do produto: JrTechDesk. Empresa: Jrtech, com o logo "JrTech — Sistemas e Gestão de
  pessoas" (`/home/rayslan/jrtechdesk/assets/logo-og.png`, `logo-jr-tech.jpg`) e o ícone do
  app (silhueta verde, `site/www/img/app.png`).
- O site é 100% em modo escuro (decisão do dono, 2026-11-26).
- Português do Brasil, linguagem direta e sem marketing vazio.
- Direção visual: o padrão da categoria de páginas de download de acesso remoto, executado
  com o máximo de cuidado (escolha do dono em 2026-11-27, numa rodada com alternativas
  ousadas). Régua de acabamento: o site do RustDesk (rustdesk.com), sem copiar marca, arte
  ou texto.

## Evidence on Hand

- Logo da Jrtech e ícone do app (caminhos acima).
- Print real do programa: o dono vai enviar, com ID e senha borrados. Até chegar, nenhuma
  captura ou maquete do app pode ser apresentada como real.
- Não existem depoimentos, números de clientes, selos, certificações ou prêmios: não inventar.

## Product Principles

1. O cliente leigo ao telefone vem primeiro: um botão certo, três passos, nada que compita.
2. Confiança vem de fatos verificáveis (endereço oficial, versão, SHA-256, o que o técnico pode
   fazer), nunca de selos ou promessas.
3. Transparência sem letra miúda: o que mais pesa para o titular fica à vista.
4. Funciona sem JavaScript e sem nada de fora do próprio servidor.

## Accessibility & Inclusion

WCAG 2.2 AA. Público leigo e muitas vezes no celular durante a ligação: alvos de toque de
44 px, texto legível com zoom de 200% e a 320 px, foco visível e respeito a movimento reduzido.
