#!/usr/bin/env bash
# =====================================================================
#  03-setup-app.sh
#  Membuat apps/.env dari config.env, install dependency, build Tailwind.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
  -h|--help) echo "Penggunaan: ./03-setup-app.sh"; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root
require_db_password
use_node
[[ -d "$APP_DIR" ]] || die "Folder aplikasi tidak ditemukan: $APP_DIR"

env_file="${APP_DIR}/.env"

log_step "1/3  Tulis ${env_file}"
if [[ -f "$env_file" ]]; then
  cp -p "$env_file" "${env_file}.bak"
  log_info "File lama dicadangkan ke .env.bak"
fi
(
  umask 077   # file hanya bisa dibaca pemiliknya (chmod 600)
  cat > "$env_file" <<ENV
APP_NAME=${APP_DISPLAY_NAME}
NODE_ENV=production
HOST=${APP_HOST}
PORT=${APP_PORT}

DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
ENV
)
chmod 600 "$env_file"
log_ok ".env dibuat dengan izin $(stat -c '%a' "$env_file")"

log_step "2/3  Install dependency (npm install)"
cd "$APP_DIR"
npm install --no-audit --no-fund

log_step "3/3  Pastikan CSS Tailwind ter-build"
if [[ ! -f public/css/output.css ]]; then
  npm run build:css
fi
node --check server.js
log_ok "Aplikasi siap dijalankan. CSS: $(stat -c '%s' public/css/output.css) bytes"
