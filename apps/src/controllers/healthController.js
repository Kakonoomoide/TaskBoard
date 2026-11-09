const pool = require('../config/db');

exports.check = async (req, res) => {
  const base = {
    app: process.env.APP_NAME || 'Praktikum Minggu 1',
    node: process.version,
    env: process.env.NODE_ENV || 'development',
    uptime_seconds: Math.round(process.uptime()),
    host: req.get('host'),
    client_ip: req.ip,
    // Nginx menambahkan header X-Real-IP -> penanda request lewat reverse proxy
    via_nginx: Boolean(req.get('x-real-ip')),
  };

  try {
    const { rows } = await pool.query('SELECT NOW() AS server_time, current_database() AS db_name');
    return res.json({
      status: 'ok',
      ...base,
      database: { connected: true, name: rows[0].db_name, server_time: rows[0].server_time },
    });
  } catch (err) {
    console.error('[health] Database error:', err.message);
    return res.status(503).json({
      status: 'error',
      ...base,
      database: { connected: false, name: null, server_time: null },
    });
  }
};
