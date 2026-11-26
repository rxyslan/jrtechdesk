// Botão "Copiar" ao lado de cada comando. Sem JavaScript o comando continua selecionável.
const aviso = document.querySelector('.aviso-copia');

function selecionar(el) {
  const faixa = document.createRange();
  faixa.selectNodeContents(el);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(faixa);
}

function anunciar(texto) {
  if (!aviso) return;
  aviso.textContent = '';
  setTimeout(() => { aviso.textContent = texto; }, 100);
}

for (const pre of document.querySelectorAll('pre[data-copiar]')) {
  const code = pre.querySelector('code');
  if (!code) continue;
  const estado = document.createElement('span');
  estado.className = 'estado-copia';
  estado.setAttribute('aria-hidden', 'true');
  const botao = document.createElement('button');
  botao.type = 'button';
  botao.className = 'copiar';
  botao.textContent = 'Copiar';
  botao.setAttribute('aria-label', pre.dataset.copiar ? `Copiar ${pre.dataset.copiar}` : `Copiar comando: ${code.textContent}`);
  let volta;
  botao.addEventListener('click', async () => {
    let ok = false;
    try {
      await navigator.clipboard.writeText(code.textContent);
      ok = true;
    } catch {
      selecionar(code);
    }
    estado.textContent = ok ? 'Copiado' : 'Selecionado: use Ctrl + C';
    anunciar(ok ? 'Copiado.' : 'Texto selecionado. Use Ctrl + C para copiar.');
    clearTimeout(volta);
    volta = setTimeout(() => { estado.textContent = ''; }, ok ? 2000 : 6000);
  });
  pre.append(estado, botao);
}
