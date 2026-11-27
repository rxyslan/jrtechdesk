---
name: JrTechDesk
description: Sistema visual do site oficial de download do JrTechDesk Suporte.
colors:
  fundo: "#070d0a"
  painel: "#0e1612"
  painel-2: "#142019"
  linha: "#1e2b25"
  linha-forte: "#6b7a73"
  texto: "#eef3f1"
  forte: "#d9e2de"
  suave: "#a2b0a9"
  verde: "#3ccb78"
  verde-hover: "#5fd892"
  verde-tinta: "#04130b"
  link: "#6edc9d"
  selo: "#fff"
typography:
  display:
    fontFamily: '"Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif'
    fontSize: "clamp(2.375rem, 5.6vw, 3.875rem)"
    fontWeight: 700
    lineHeight: 1.04
    letterSpacing: "-0.035em"
  secao:
    fontSize: "clamp(1.875rem, 3.6vw, 2.75rem)"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  bloco:
    fontSize: "1.25rem"
    fontWeight: 650
    lineHeight: 1.3
    letterSpacing: "-0.01em"
  corpo:
    fontFamily: '"Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif'
    fontSize: "1.0625rem"
    lineHeight: 1.6
  pequeno:
    fontSize: "0.9375rem"
  meta:
    fontSize: "0.8125rem"
    lineHeight: 1.5
  mono:
    fontFamily: 'ui-monospace, "Cascadia Mono", Consolas, "DejaVu Sans Mono", "Liberation Mono", monospace'
rounded:
  pilula: "9999px"
  caixa: "16px"
  campo: "10px"
  circulo: "50%"
spacing:
  e-1: "4px"
  e-2: "8px"
  e-3: "12px"
  e-4: "16px"
  e-5: "24px"
  e-6: "32px"
  e-7: "48px"
  e-8: "64px"
  e-9: "80px"
components:
  baixar-windows:
    backgroundColor: "{colors.verde}"
    textColor: "{colors.verde-tinta}"
    rounded: "{rounded.pilula}"
    padding: "12px 32px 12px 24px"
  baixar-windows-hover:
    backgroundColor: "{colors.verde-hover}"
  pacotes-linux:
    textColor: "{colors.texto}"
    rounded: "{rounded.pilula}"
    padding: "0 32px"
  pacotes-linux-hover:
    backgroundColor: "{colors.painel-2}"
  arquivo:
    textColor: "{colors.texto}"
    rounded: "{rounded.pilula}"
    padding: "8px 24px 8px 16px"
  copiar:
    backgroundColor: "{colors.painel-2}"
    textColor: "{colors.texto}"
    rounded: "{rounded.pilula}"
    padding: "0 16px"
  painel-downloads:
    backgroundColor: "{colors.painel}"
    rounded: "{rounded.caixa}"
  comando:
    backgroundColor: "{colors.fundo}"
    textColor: "{colors.texto}"
    rounded: "{rounded.campo}"
---

# Sistema visual do site JrTechDesk

## Overview

O site de download é escuro e segue as convenções das páginas de suporte remoto. A direção registrada no brief usa o RustDesk como régua de acabamento, com marca, arte e texto próprios. A interface em português do Brasil favorece quem está ao telefone com o técnico. O endereço oficial aparece antes das ações, o download para Windows recebe o maior destaque e três passos numerados orientam o atendimento. A seção Downloads reúne os pacotes por sistema e a conferência dos arquivos. A seção Privacidade mantém os resumos à vista.

Este documento registra a implementação de [`site/www/index.html`](site/www/index.html) e [`site/www/estilo.css`](site/www/estilo.css). [`PRODUCT.md`](PRODUCT.md) registra as decisões de produto. Os tokens de componentes descrevem o estado base. As variações por largura e por interação estão no texto.

## Colors

O grafite tingido de verde domina a página. `fundo` é a base e também preenche os blocos de comando. `painel` agrupa os passos e as linhas de download. `painel-2` diferencia a faixa do endereço oficial, o botão Copiar e alguns estados de hover. `linha` separa áreas de conteúdo. `linha-forte` contorna controles e marca a sequência dos passos. `texto` dá destaque a títulos e ações, `forte` aparece na faixa e nos ícones informativos, e `suave` é usado em descrições, navegação e metadados.

O verde preenchido com `verde-tinta` é reservado ao botão principal de download, com `verde-hover` ao passar o ponteiro. O CSS também usa `verde` nos ícones de download, no hover dos arquivos, no foco, na seleção de texto, no cursor de texto, no retorno de cópia e na borda do aviso para toque. `link` é o verde mais claro dos links de texto e do hover dos tópicos de privacidade. O branco de `selo` serve de fundo apenas para o ícone da marca no cabeçalho e no rodapé.

## Typography

Inter variável (pesos de 100 a 900, subconjunto latino) é hospedada no próprio site como [WOFF2](site/www/fontes/inter-latin.woff2), sob [SIL OFL 1.1](site/www/fontes/OFL.txt). O HTML faz preload e a fonte usa `font-display: swap`. Os fallbacks de sistema estão na escala tipográfica. O título principal e os títulos de seção são fluidos, com entreletras apertadas. Títulos de bloco usam peso 650 e o corpo usa entrelinha de 1,6. A introdução do hero usa `1.25rem` com entrelinha de 1,5, reduzida para `1.125rem` até 640 px.

O título principal tem medida de até `17ch`, a introdução do hero de até `44ch` e os textos corridos que usam `--medida` de até `65ch`. Os metadados e os números dos passos usam algarismos tabulares. Comandos, atalhos de teclado e nomes de arquivos usam a pilha monoespaçada. O SHA-256 abreviado do hero acompanha os demais metadados em Inter. O hash completo aparece no bloco monoespaçado de conferência.

## Layout

- O contêiner tem largura máxima de 1152 px, incluindo margens internas laterais de 24 px, reduzidas para 16 px até 640 px. O espaçamento parte de múltiplos de 4 px. Downloads e Privacidade têm 80 px de respiro acima e abaixo, reduzidos a 64 px até 640 px.
- O hero centraliza título, introdução, ações e metadados. Os três passos aparecem em colunas, com círculos numerados ligados por um traço horizontal. Segurança e ajuda também formam três colunas. Downloads usa linhas separadas por bordas, com sistema e requisitos à esquerda e ações à direita. A conferência dos arquivos usa duas colunas.
- Até 900 px, passos, avisos, linhas de download e conferência passam para uma coluna. Nos passos, o traço passa a ser vertical e o texto se alinha à esquerda junto à numeração. Os avisos passam a ter divisórias horizontais.
- Até 640 px, a navegação ocupa sua própria linha, a faixa do endereço oficial se alinha à esquerda e as duas ações do hero ocupam a largura disponível. Os metadados empilham sem separadores, os links de arquivo ocupam a linha inteira e o botão Copiar fica abaixo do comando, no canto direito. O aviso “Está no celular?” aparece entre a introdução e as ações quando `hover: none` e `pointer: coarse` se aplicam, independentemente da largura.

## Elevation & Depth

Tons de superfície e bordas de 1 px separam os blocos. O painel de passos e a lista de downloads compartilham a única sombra declarada em `--sombra`, um filete claro interno e uma sombra externa difusa (`0 1px 0 rgb(255 255 255 / 0.03) inset, 0 24px 48px -24px rgb(0 0 0 / 0.6)`). O painel de conferência usa apenas o contorno sobre o fundo da página.

## Shapes

Pílulas dão forma aos botões do hero, aos links de arquivo, à navegação e ao botão Copiar. Até 640 px os links de arquivo usam o raio das caixas para acomodar a quebra do nome. Caixas de 16 px agrupam conteúdo, e blocos de comando usam 10 px. Os marcadores dos passos são círculos de 40 px. Ícones de interface usam traço sem preenchimento, com pontas e junções arredondadas. O [ícone do app](site/www/img/app.png) aparece em base branca arredondada no cabeçalho e no rodapé. Ele e o [favicon da página](site/www/img/favicon.png) já constam no histórico do site desde `c6b8c7004`.

## Components

### Navegação e chamadas de download

- A faixa superior apresenta o endereço oficial com ícone e texto, com pontos de quebra no domínio. Abaixo, a marca leva ao início e a navegação leva por âncoras a Receber suporte, Downloads e Privacidade. Um link de salto para o conteúdo aparece ao receber foco. Os links da navegação têm altura mínima de 44 px e, no hover, ganham fundo de painel e texto mais claro.
- “Baixar para Windows” é um link de download com ícone e dois níveis de texto. “Pacotes para Linux” é um link de contorno para a linha do Ubuntu e Debian, início das opções Linux. As ações têm altura mínima de 64 px no layout base. Até 640 px, a secundária baixa para 52 px. O botão principal clareia no hover e se desloca 1 px para baixo quando pressionado. O secundário ganha fundo de painel e clareia a borda no hover.
- A lista reúne Windows, Ubuntu e Debian e Arch Linux em um único painel. Os links de arquivo têm altura mínima de 48 px, ícone verde e contorno que fica verde no hover. Cada link reúne a ação “Baixar” e o nome técnico, com quebra permitida. Versão, tamanho e hashes são exibidos quando [`versao.js`](site/www/versao.js) recebe os dados correspondentes. A exibição dos hashes exige também uma tag válida. Os links fixos de `/download/` são o padrão no HTML.

### Conferência e cópia

O painel de conferência põe a explicação junto dos comandos para Linux e PowerShell. Os comandos são selecionáveis e quebram em linhas. [`copiar.js`](site/www/copiar.js) insere botões de pelo menos 44 × 80 px em `pre[data-copiar]`. O retorno aparece junto do comando e é anunciado numa região de status. Se a área de transferência falhar, o script seleciona o texto e orienta a cópia manual.

### Privacidade

Os tópicos usam `details` e `summary` com título e resumo sempre visíveis. O texto completo aparece ao expandir. A seta gira 180° na abertura, e seta e título mudam para a cor de link no hover. Cada resumo tem altura mínima de 56 px. “Para que serve o acesso” permanece visível como texto estático. O CSS de impressão tenta exibir o conteúdo completo e oculta as setas.

### Foco e movimento

Links, botões e resumos recebem contorno de foco visível de 2 px, verde e afastado 3 px. No download principal ele usa a cor `texto` e afastamento de 4 px. As transições de cor (160 ms) e transformação (120 ms) em download principal, links de arquivo, Copiar e navegação, e a rotação animada da seta (200 ms), são declaradas apenas com `prefers-reduced-motion: no-preference`. Todas usam `--saida`, `cubic-bezier(0.22, 1, 0.36, 1)`.

## Do's and Don'ts

- Mantenha o endereço oficial visível antes do download e o botão verde preenchido como ação principal. Preserve o secundário em contorno e os avisos em superfícies de leitura.
- Preserve os resumos de Privacidade junto aos títulos e sua fidelidade ao texto completo. Qualquer mudança no texto completo exige revisão contra o código, conforme `PRODUCT.md`.
- Use recursos hospedados no próprio site e mantenha os downloads e comandos utilizáveis sem JavaScript. Preserve o foco visível e considere a preferência por movimento reduzido nas transições.
- Trate como pendente o print real do app com ID e senha borrados. O HTML indica a posição e a proporção 16:9 em um comentário. Depoimentos, selos de confiança, certificações, prêmios e números de clientes carecem de evidência no material de produto.
- `PRODUCT.md` deixa em aberto a razão social, o CNPJ, o canal oficial de contato e de pedidos LGPD e o prazo de retenção dos registros. WCAG 2.2 AA, leitura a 320 px e zoom de 200% são requisitos de produto. A validação desses requisitos e da impressão segue pendente nesta revisão. As capturas locais consultadas antecedem a mudança de posição do aviso para toque, cuja ordem foi conferida no HTML atual.
