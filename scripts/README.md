# scripts - Praktikum Minggu 2 (Shell Scripting & Automation)

Semua langkah Minggu 1 diotomatisasi dengan Bash. Letakkan folder ini di root repo,
sejajar dengan `apps/`, `database/`, dan `nginx/`.

## Persiapan
```bash
chmod +x scripts/*.sh scripts/lib/*.sh
cp scripts/config.env.example scripts/config.env
nano scripts/config.env          # isi DB_PASSWORD
```

## Script
| Script | Fungsi |
|--------|--------|
| `drop.sh` | Hapus semua hasil Minggu 1 (`--dry-run`, `--yes`, `--keep-db`, `--purge`) |
| `01-setup-database.sh` | PostgreSQL + user + database + schema |
| `02-setup-node.sh` | NVM + Node.js |
| `03-setup-app.sh` | `.env` + npm install + build Tailwind |
| `04-setup-pm2.sh` | PM2 + start + auto-start boot |
| `05-setup-nginx.sh` | Nginx reverse proxy + rate limiter |
| `setup-all.sh` | Menjalankan 01-05 berurutan (`--from N`) |
| `deploy.sh` | Auto deploy dari GitHub + health check + rollback otomatis |
| `health.sh` | Cek kesehatan server (`-q`, `-w DETIK`), kode keluar 0/1/2 |
| `pm2-manage.sh` | Pengelolaan PM2 (status, start, stop, restart, logs, ...) |
| `nginx-manage.sh` | Pengelolaan & status Nginx (status, reload, sync, logs, rate-test, ...) |
| `install-docker.sh` | (Minggu 3) Install Docker Engine + Compose plugin |
| `docker-manage.sh` | (Minggu 3) Pengelolaan stack Docker Compose |
| `docker-health.sh` | (Minggu 3) Cek apakah stack Docker berjalan & sehat (`-q`, `-w`, `-d`, `-u`) |
| `lib/common.sh`, `lib/nginx.sh` | Fungsi bersama (jangan dijalankan langsung) |

Semua script punya `-h` / `--help`. Jalankan sebagai user biasa (bukan root).
Langkah lengkap ada di modul praktikum (docx).
