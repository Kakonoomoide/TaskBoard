// Konfigurasi PM2 -> jalankan dengan: pm2 start ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'praktikum-app',
      script: './server.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      time: true, // tambahkan timestamp di log
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
