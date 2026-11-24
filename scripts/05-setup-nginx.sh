#!/usr/bin/env bash
# =====================================================================
#  05-setup-nginx.sh
#  Install Nginx, pasang konfigurasi reverse proxy + rate limiter.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$LIB_DIR/nginx.sh"

case "${1:-}" in
  -h|--help) echo "Penggunaan: ./05-setup-nginx.sh"; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root
ensure_sudo

log_step "1/3  Install Nginx"
if has_cmd nginx; then
  log_ok "Nginx sudah terpasang."
else
  sudo apt-get update -y
  apt_install nginx
fi
sudo systemctl enable --now nginx

log_step "2/3  Pasang konfigurasi dari repo"
rc=0
nginx_sync_conf || rc=$?
case "$rc" in
  0)  log_ok "Konfigurasi dipasang & Nginx di-reload." ;;
  10) log_ok "Konfigurasi sudah sama dengan repo, tidak ada perubahan." ;;
  *)  die "Gagal memasang konfigurasi Nginx." ;;
esac

log_step "3/3  Uji lewat port 80"
if wait_until 15 app_healthy "$HEALTH_URL_NGINX"; then
  log_ok "Nginx meneruskan request ke aplikasi: ${HEALTH_URL_NGINX}"
else
  die "Request lewat Nginx gagal. Pastikan aplikasi jalan (./pm2-manage.sh status) lalu cek log Nginx."
fi
