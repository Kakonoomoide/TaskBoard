# apps - Praktikum Minggu 1

Aplikasi Task Board: Express + EJS + Tailwind CSS + PostgreSQL.

## Struktur
- `server.js`            : entry point Express
- `src/controllers`      : handler request (tanpa logika tampilan)
- `src/models`           : query ke PostgreSQL
- `src/routes`           : routing halaman & API
- `views/`               : template EJS (markup saja)
- `public/js`            : SEMUA fungsi JavaScript untuk halaman EJS
- `src/styles/input.css` : sumber Tailwind -> dibuild ke `public/css/output.css`
- `ecosystem.config.js`  : konfigurasi PM2

## Menjalankan (singkat)
```bash
cp .env.example .env      # lalu isi DB_PASSWORD
npm install               # otomatis membuild Tailwind (postinstall)
node server.js            # uji coba
pm2 start ecosystem.config.js
```

Aplikasi listen di 127.0.0.1:3000. Akses publik lewat Nginx (port 80).
Langkah lengkap ada di modul praktikum (docx).
