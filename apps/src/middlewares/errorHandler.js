function notFound(req, res) {
  if (req.originalUrl.startsWith('/api')) {
    return res.status(404).json({ error: 'Endpoint tidak ditemukan.' });
  }
  return res.status(404).render('error', {
    title: '404',
    code: 404,
    message: 'Halaman yang kamu cari tidak ditemukan.',
  });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  console.error('[error]', err.message);
  const status = err.status && err.status < 500 ? err.status : 500;
  const message = status === 500 ? 'Terjadi kesalahan pada server.' : 'Request tidak valid.';

  if (req.originalUrl.startsWith('/api')) {
    return res.status(status).json({ error: message });
  }
  return res.status(status).render('error', { title: String(status), code: status, message });
}

module.exports = { notFound, errorHandler };
