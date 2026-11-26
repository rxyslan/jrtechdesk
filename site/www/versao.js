// Mostra a versão e o tamanho dos arquivos a partir de /download/versao.json,
// gerado no servidor por sincronizar.sh. Sem ele a página funciona igual.
fetch('/download/versao.json', { cache: 'no-cache' })
  .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
  .then((v) => {
    const el = document.querySelector('[data-versao]');
    if (el && typeof v?.versao === 'string' && v.versao) {
      const data = new Date(v.publicada || '');
      const publicada = Number.isFinite(data.getTime()) ? data.toLocaleDateString('pt-BR') : '';
      el.textContent = `Versão ${v.versao}` + (publicada ? ` · ${publicada}` : '');
      el.hidden = false;
    }
    // Links com a tag no caminho: pacote, SHA256SUMS.txt e código-fonte da mesma versão.
    if (typeof v?.tag === 'string' && /^v[0-9A-Za-z.-]+$/.test(v.tag)) {
      for (const a of document.querySelectorAll('[data-arquivo]')) {
        if (v.arquivos?.[a.dataset.arquivo]) {
          a.href = `/versoes/${v.tag}/${a.dataset.arquivo}`;
        }
      }
      const fonte = document.querySelector('[data-fonte]');
      if (fonte) {
        fonte.href = `https://github.com/rxyslan/jrtechdesk/tree/${v.tag}`;
        fonte.textContent = 'Código-fonte desta versão';
      }
    }
    for (const span of document.querySelectorAll('[data-tamanho]')) {
      const bytes = v?.arquivos?.[span.dataset.tamanho]?.tamanho;
      if (Number.isFinite(bytes) && bytes >= 1000000) {
        span.textContent = ` · ${Math.round(bytes / 1000000)} MB`;
        span.hidden = false;
      }
    }
  })
  .catch(() => {});
