const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express = require('express');
const pool = require('./src/config/db');
const pageRoutes = require('./src/routes/pageRoutes');
const apiRoutes = require('./src/routes/apiRoutes');
const { notFound, errorHandler } = require('./src/middlewares/errorHandler');

const app = express();
const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '127.0.0.1';

// Aplikasi berjalan di belakang Nginx -> percaya header X-Forwarded-*
app.set('trust proxy', 1);
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.disable('x-powered-by');

// Variabel global yang bisa dipakai semua view EJS
app.locals.appName = process.env.APP_NAME || 'Praktikum Minggu 1';

app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: false, limit: '10kb' }));
app.use(express.static(path.join(__dirname, 'public')));

app.use('/api', apiRoutes);
app.use('/', pageRoutes);
app.use(notFound);
app.use(errorHandler);

const server = app.listen(PORT, HOST, () => {
  console.log(`[server] Berjalan di http://${HOST}:${PORT} (${process.env.NODE_ENV || 'development'})`);
});

// Graceful shutdown (PM2 mengirim SIGINT saat restart/stop)
function shutdown(signal) {
  console.log(`[server] ${signal} diterima, menutup server...`);
  server.close(async () => {
    await pool.end().catch(() => {});
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
