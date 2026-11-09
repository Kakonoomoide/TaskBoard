// Logika halaman Status Server (views/status.ejs)
(function () {
  'use strict';

  const { api, showToast, formatDate } = window.App;
  const REFRESH_MS = 10000;

  const $ = function (id) { return document.getElementById(id); };

  function formatUptime(totalSeconds) {
    const h = Math.floor(totalSeconds / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    return h + ' jam ' + m + ' menit ' + s + ' detik';
  }

  function setBadge(ok) {
    const badge = $('st-badge');
    badge.textContent = ok ? 'Semua sistem normal' : 'Ada masalah (database tidak terhubung)';
    badge.className = 'rounded-full px-3 py-1 text-sm font-semibold ' +
      (ok ? 'bg-emerald-100 text-emerald-800' : 'bg-rose-100 text-rose-800');
  }

  function render(data) {
    const dbOk = Boolean(data.database && data.database.connected);
    setBadge(dbOk);

    $('st-app').textContent = data.app;
    $('st-node').textContent = data.node;
    $('st-env').textContent = data.env;
    $('st-uptime').textContent = formatUptime(data.uptime_seconds);
    $('st-db').textContent = dbOk ? 'Terhubung (' + data.database.name + ')' : 'Tidak terhubung';
    $('st-time').textContent = dbOk ? formatDate(data.database.server_time) : '-';
    $('st-host').textContent = data.host;
    $('st-client').textContent = data.client_ip;
    $('st-proxy').textContent = data.via_nginx
      ? 'Ya - request melewati Nginx'
      : 'Tidak - kamu mengakses langsung ke aplikasi (port 3000)';
  }

  async function loadStatus() {
    try {
      render(await api('/api/health'));
    } catch (err) {
      if (err.body && err.body.database) {
        render(err.body); // 503: server hidup tetapi database mati
      } else {
        $('st-badge').textContent = 'Gagal menghubungi server';
        $('st-badge').className = 'rounded-full bg-rose-100 px-3 py-1 text-sm font-semibold text-rose-800';
        showToast(err.message, 'error');
      }
    }
  }

  $('btn-refresh').addEventListener('click', loadStatus);
  loadStatus();
  setInterval(loadStatus, REFRESH_MS);
})();
