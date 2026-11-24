#!/usr/bin/env bash
# =====================================================================
#  01-setup-database.sh
#  Install PostgreSQL, buat user + database, import schema & data awal.
#  Aman dijalankan berulang (idempotent).
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
Penggunaan: ./01-setup-database.sh [-h]

Membaca DB_NAME, DB_USER, DB_PASSWORD dari scripts/config.env.
USAGE
}
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root
ensure_sudo
require_db_password

log_step "1/5  Install PostgreSQL"
if dpkg -s postgresql >/dev/null 2>&1; then
  log_ok "PostgreSQL sudah terpasang, dilewati."
else
  sudo apt-get update -y
  apt_install postgresql postgresql-contrib
  log_ok "PostgreSQL terpasang."
fi

log_step "2/5  Aktifkan service"
sudo systemctl enable --now postgresql
wait_until 30 pg_isready -q || die "PostgreSQL belum siap setelah 30 detik. Cek: pg_lsclusters"
log_ok "PostgreSQL siap menerima koneksi."

log_step "3/5  Buat user '${DB_USER}'"
if [[ "$(pg_query "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'")" == "1" ]]; then
  log_info "User sudah ada, password diperbarui sesuai config.env."
  pg_exec "ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
else
  pg_exec "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
  log_ok "User dibuat."
fi

log_step "4/5  Buat database '${DB_NAME}'"
if [[ "$(pg_query "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")" == "1" ]]; then
  log_ok "Database sudah ada, dilewati."
else
  pg_exec "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
  log_ok "Database dibuat."
fi

log_step "5/5  Import schema & data awal"
psql_app -f "${DB_DIR}/02_schema.sql"
psql_app -f "${DB_DIR}/03_seed.sql"
rows="$(psql_app -tAc 'SELECT count(*) FROM tasks')"
log_ok "Tabel tasks berisi ${rows} baris."

addr="$(port_bind_addr "$DB_PORT")"
if [[ "$addr" == 127.0.0.1:* ]]; then
  log_ok "PostgreSQL hanya listen di localhost (${addr})."
else
  log_warn "PostgreSQL listen di ${addr}. Pastikan tidak terbuka ke publik!"
fi
