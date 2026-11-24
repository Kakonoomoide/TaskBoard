#!/usr/bin/env bash
# =====================================================================
#  drop.sh
#  Menghapus semua yang dikerjakan di Minggu 1 -> server kembali bersih.
#
#  Level 1 (default): hapus app di PM2, site Nginx, database + user,
#                     dan artefak aplikasi (.env, node_modules, output.css).
#  Level 2 (--purge): + hapus PM2 service, NVM/Node.js, dan uninstall
#                     paket Nginx & PostgreSQL (BERBAHAYA).
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$LIB_DIR/nginx.sh"

PURGE=false
KEEP_DB=false

# Pesan selesai: pada --dry-run jangan mengaku sudah menghapus
log_done() {
  if [[ "$DRY_RUN" == true ]]; then log_info "(dry-run) $*"; else log_ok "$*"; fi
}

usage() {
  cat <<USAGE
Penggunaan: ./drop.sh [opsi]

  -n, --dry-run   tampilkan apa yang AKAN dilakukan, tanpa mengubah apa pun
  -y, --yes       lewati konfirmasi (hati-hati)
      --keep-db   jangan hapus database & user
      --purge     hapus juga PM2 service, NVM/Node.js, paket Nginx & PostgreSQL
  -h, --help      bantuan

Contoh:
  ./drop.sh --dry-run        # lihat dulu rencananya
  ./drop.sh                  # drop level 1 (minta konfirmasi)
  ./drop.sh --purge          # reset total
USAGE
}

while (( $# )); do
  case "$1" in
    -n|--dry-run) DRY_RUN=true ;;
    -y|--yes)     ASSUME_YES=true ;;
    --keep-db)    KEEP_DB=true ;;
    --purge)      PURGE=true ;;
    -h|--help)    usage; exit 0 ;;
    *) die "Opsi tidak dikenal: $1 (lihat --help)" ;;
  esac
  shift
done

require_not_root
ensure_sudo
enable_logging drop

# ---------- Langkah-langkah ----------
drop_pm2() {
  log_step "1. PM2: hapus proses '${PM2_APP_NAME}'"
  load_nvm || true
  nvm_run use "$NODE_VERSION" >/dev/null 2>&1 || true
  if ! has_cmd pm2; then log_info "PM2 tidak ada, dilewati."; return 0; fi
  if pm2 describe "$PM2_APP_NAME" >/dev/null 2>&1; then
    run pm2 delete "$PM2_APP_NAME"
    run pm2 save --force
    log_done "Proses PM2 dihapus."
  else
    log_info "Proses '${PM2_APP_NAME}' tidak terdaftar, dilewati."
  fi
}

drop_nginx() {
  log_step "2. Nginx: hapus site '${NGINX_SITE}'"
  if ! has_cmd nginx; then log_info "Nginx tidak ada, dilewati."; return 0; fi
  run sudo rm -f "$(nginx_conf_link)" "$(nginx_conf_dst)"
  if [[ -f /etc/nginx/sites-available/default ]]; then
    run sudo ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    log_info "Site default Nginx dikembalikan."
  fi
  run sudo nginx -t
  run sudo systemctl reload nginx
  log_done "Konfigurasi Nginx praktikum dihapus."
}

drop_database() {
  log_step "3. PostgreSQL: hapus database '${DB_NAME}' dan user '${DB_USER}'"
  if [[ "$KEEP_DB" == true ]]; then log_info "--keep-db: dilewati."; return 0; fi
  if ! has_cmd psql || ! systemctl is-active --quiet postgresql; then
    log_info "PostgreSQL tidak aktif, dilewati."
    return 0
  fi
  pg_exec "DO \$\$ BEGIN PERFORM pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid(); END \$\$;"
  pg_exec "DROP DATABASE IF EXISTS ${DB_NAME};"
  pg_exec "DROP ROLE IF EXISTS ${DB_USER};"
  log_done "Database dan user dihapus."
}

drop_app() {
  log_step "4. Aplikasi: hapus .env, node_modules, output.css"
  if [[ -z "$APP_DIR" || "$APP_DIR" == "/" || ! -d "$APP_DIR" ]]; then
    log_warn "Folder aplikasi tidak valid (${APP_DIR}), dilewati."
    return 0
  fi
  local target
  for target in "${APP_DIR}/node_modules" "${APP_DIR}/.env" "${APP_DIR}"/.env.bak* "${APP_DIR}/public/css/output.css"; do
    if [[ -e "$target" ]]; then run rm -rf -- "$target"; fi
  done
  log_done "Artefak aplikasi dihapus (kode di repo tetap aman)."
}

drop_purge() {
  log_step "5. PURGE: hapus PM2 service, NVM/Node.js, paket Nginx & PostgreSQL"
  run sudo systemctl disable --now "pm2-${CURRENT_USER}" 2>/dev/null || true
  run sudo rm -f "/etc/systemd/system/pm2-${CURRENT_USER}.service"
  run sudo systemctl daemon-reload
  run rm -rf "${HOME}/.pm2"

  run rm -rf "${NVM_DIR:-$HOME/.nvm}"
  if [[ -f "${HOME}/.bashrc" ]]; then
    run sed -i.bak '/NVM_DIR/d' "${HOME}/.bashrc"
  fi

  run sudo systemctl disable --now nginx 2>/dev/null || true
  run sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y nginx nginx-common 'postgresql*' || log_warn "Sebagian paket tidak terpasang (aman diabaikan)."
  run sudo apt-get autoremove -y
  run sudo rm -rf /var/lib/postgresql /etc/postgresql /var/log/nginx
  log_done "Purge selesai."
}

# ---------- Rencana & konfirmasi ----------
log_step "Rencana drop"
cat <<PLAN
  1. PM2     : hapus proses ${PM2_APP_NAME}
  2. Nginx   : hapus site ${NGINX_SITE}, kembalikan site default
  3. Database: DROP DATABASE ${DB_NAME}; DROP ROLE ${DB_USER}   $( [[ "$KEEP_DB" == true ]] && echo "(DILEWATI: --keep-db)" )
  4. Aplikasi: hapus ${APP_DIR}/{.env,node_modules,public/css/output.css}
PLAN
if [[ "$PURGE" == true ]]; then
  echo "  5. PURGE   : hapus PM2 service, NVM/Node.js, uninstall Nginx & PostgreSQL + datanya"
fi
if [[ "$DRY_RUN" == true ]]; then
  log_warn "Mode DRY-RUN: tidak ada yang diubah."
else
  log_warn "Data yang dihapus TIDAK bisa dikembalikan."
  confirm_phrase "DROP" || die "Dibatalkan."
fi

drop_pm2
drop_nginx
drop_database
drop_app
if [[ "$PURGE" == true ]]; then drop_purge; fi

log_step "Selesai"
cat <<NEXT
Verifikasi hasil drop:
  curl -I http://localhost                 # Nginx default (200), bukan Task Board
  pm2 status                               # tidak ada ${PM2_APP_NAME}
  psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME}   # harus gagal (user/database sudah tidak ada)

Bangun ulang dengan:  ./setup-all.sh
NEXT
