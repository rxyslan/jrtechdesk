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
    for (const span of document.querySelectorAll('[data-tamanho]')) {
      const bytes = v?.arquivos?.[span.dataset.tamanho]?.tamanho;
      if (Number.isFinite(bytes) && bytes >= 1000000) {
        span.textContent = ` · ${Math.round(bytes / 1000000)} MB`;
        span.hidden = false;
      }
    }
  })
  .catch(() => {});
