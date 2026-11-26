// Botão "Copiar" ao lado de cada comando. Sem JavaScript o comando continua selecionável.
const aviso = document.querySelector('.aviso-copia');

function selecionar(el) {
  const faixa = document.createRange();
  faixa.selectNodeContents(el);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(faixa);
}

for (const pre of document.querySelectorAll('pre[data-copiar]')) {
  const code = pre.querySelector('code');
  if (!code) continue;
  const botao = document.createElement('button');
  botao.type = 'button';
  botao.className = 'copiar';
  botao.textContent = 'Copiar';
  botao.setAttribute('aria-label', `Copiar comando: ${code.textContent}`);
  let volta;
  botao.addEventListener('click', async () => {
    let ok = false;
    try {
      await navigator.clipboard.writeText(code.textContent);
      ok = true;
    } catch {
      selecionar(code);
    }
    botao.textContent = ok ? 'Copiado' : 'Selecionado';
    if (aviso) aviso.textContent = ok ? 'Comando copiado.' : 'Comando selecionado. Use Ctrl + C para copiar.';
    clearTimeout(volta);
    volta = setTimeout(() => { botao.textContent = 'Copiar'; }, 2000);
  });
  pre.append(botao);
}
