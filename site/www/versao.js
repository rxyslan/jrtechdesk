// Mostra a versão e o tamanho dos arquivos a partir de /download/versao.json,
// gerado no servidor por sincronizar.sh. Sem ele a página funciona igual.
fetch('/download/versao.json', { cache: 'no-cache' })
  .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
  .then((v) => {
    const el = document.querySelector('[data-versao]');
    if (el && v.versao) {
      const data = v.publicada ? new Date(v.publicada).toLocaleDateString('pt-BR') : '';
      el.textContent = `Versão ${v.versao}` + (data ? ` · ${data}` : '');
      el.hidden = false;
    }
    for (const span of document.querySelectorAll('[data-tamanho]')) {
      const arq = (v.arquivos || {})[span.dataset.tamanho];
      if (arq && arq.tamanho) {
        span.textContent = `${Math.round(arq.tamanho / 1048576)} MB`;
      }
    }
  })
  .catch(() => {});
