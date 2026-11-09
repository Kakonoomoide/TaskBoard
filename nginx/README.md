# nginx - Praktikum Minggu 1

`praktikum.conf` berisi:
- Reverse proxy : port 80 (HTTP) -> 127.0.0.1:3000 (Express)
- Rate limiter  : `limit_req` (halaman 10 r/s, API 5 r/s) dan `limit_conn` (20 koneksi/IP)
- Hardening     : sembunyikan versi, security headers, batas body, timeout, blokir file tersembunyi

Pasang:
```bash
sudo cp praktikum.conf /etc/nginx/sites-available/praktikum
sudo ln -s /etc/nginx/sites-available/praktikum /etc/nginx/sites-enabled/praktikum
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```
