// Fungsi umum yang dipakai semua halaman EJS.
(function () {
  'use strict';

  const TOAST_STYLE = {
    success: 'bg-emerald-600',
    error: 'bg-rose-600',
    info: 'bg-slate-800',
  };

  function showToast(message, type) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const el = document.createElement('div');
    el.className =
      'rounded-lg px-4 py-3 text-sm font-medium text-white shadow-lg transition-opacity duration-300 ' +
      (TOAST_STYLE[type] || TOAST_STYLE.info);
    el.textContent = message;
    container.appendChild(el);

    setTimeout(function () {
      el.classList.add('opacity-0');
      setTimeout(function () { el.remove(); }, 300);
    }, 3000);
  }

  // Pembungkus fetch: otomatis JSON + penanganan error (termasuk 429 dari Nginx)
  async function api(url, options) {
    const res = await fetch(url, Object.assign({ headers: { 'Content-Type': 'application/json' } }, options));

    let body = null;
    try { body = await res.json(); } catch (_) { /* respons bukan JSON */ }

    if (!res.ok) {
      const message =
        res.status === 429
          ? 'Terlalu banyak request (rate limit Nginx). Tunggu sebentar lalu coba lagi.'
          : (body && body.error) || 'Request gagal (' + res.status + ').';
      const err = new Error(message);
      err.status = res.status;
      err.body = body;
      throw err;
    }
    return body;
  }

  function formatDate(iso) {
    return new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso));
  }

  function highlightNav() {
    document.querySelectorAll('[data-nav]').forEach(function (link) {
      if (link.getAttribute('href') === window.location.pathname) {
        link.classList.remove('text-slate-600');
        link.classList.add('bg-indigo-50', 'text-indigo-700');
      }
    });
  }

  window.App = { showToast: showToast, api: api, formatDate: formatDate };
  document.addEventListener('DOMContentLoaded', highlightNav);
})();
