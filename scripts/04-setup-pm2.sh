#!/usr/bin/env bash
# =====================================================================
#  04-setup-pm2.sh
#  Install PM2, jalankan aplikasi, aktifkan auto-start saat boot.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
  -h|--help) echo "Penggunaan: ./04-setup-pm2.sh"; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root
ensure_sudo
use_node
[[ -f "${APP_DIR}/.env" ]] || die "apps/.env belum ada. Jalankan ./03-setup-app.sh dulu."

log_step "1/4  Install PM2"
if has_cmd pm2; then
  log_ok "PM2 sudah terpasang ($(pm2 -v))."
else
  npm install -g pm2
  log_ok "PM2 terpasang ($(pm2 -v))."
fi

log_step "2/4  Jalankan aplikasi"
cd "$APP_DIR"
pm2 startOrRestart ecosystem.config.js --update-env
pm2 describe "$PM2_APP_NAME" >/dev/null 2>&1 \
  || die "Proses '${PM2_APP_NAME}' tidak ada di PM2. Samakan PM2_APP_NAME dengan name di ecosystem.config.js."

log_step "3/4  Auto-start saat server reboot"
node_bin_dir="$(dirname "$(command -v node)")"
sudo env PATH="${PATH}:${node_bin_dir}" "$(command -v pm2)" startup systemd -u "$CURRENT_USER" --hp "$HOME"
pm2 save

log_step "4/4  Tunggu aplikasi sehat"
if wait_until "$HEALTH_TIMEOUT" app_healthy "$HEALTH_URL_APP"; then
  log_ok "Aplikasi sehat: ${HEALTH_URL_APP}"
else
  pm2 logs "$PM2_APP_NAME" --lines 20 --nostream || true
  die "Aplikasi tidak sehat setelah ${HEALTH_TIMEOUT} detik. Cek DB_PASSWORD dan log di atas."
fi
pm2 status
