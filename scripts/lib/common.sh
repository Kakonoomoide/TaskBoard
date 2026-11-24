#!/usr/bin/env bash
# =====================================================================
#  lib/common.sh
#  Fungsi & konfigurasi yang dipakai bersama oleh SEMUA script.
#  File ini tidak dijalankan langsung; di-load dengan perintah `source`.
# =====================================================================

# Cegah file ini ter-load dua kali
if [[ -n "${_COMMON_LOADED:-}" ]]; then return 0; fi
_COMMON_LOADED=1

# ---------- Strict mode ----------
#  -E : trap ERR ikut berlaku di dalam fungsi
#  -e : berhenti saat ada perintah yang gagal
#  -u : error jika memakai variabel yang belum diisi
#  -o pipefail : pipeline dianggap gagal jika salah satu bagiannya gagal
set -Eeuo pipefail

# ---------- Lokasi penting ----------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$LIB_DIR")"
ROOT_DIR="$(dirname "$SCRIPTS_DIR")"

# ---------- Konfigurasi: muat config.env (jika ada), lalu isi default ----------
if [[ -f "$SCRIPTS_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPTS_DIR/config.env"
fi

: "${APP_DIR:=$ROOT_DIR/apps}"
: "${DB_DIR:=$ROOT_DIR/database}"
: "${NGINX_DIR:=$ROOT_DIR/nginx}"
: "${LOG_DIR:=$SCRIPTS_DIR/logs}"

: "${APP_DISPLAY_NAME:=Praktikum Minggu 1}"
: "${PM2_APP_NAME:=praktikum-app}"
: "${APP_HOST:=127.0.0.1}"
: "${APP_PORT:=3000}"

: "${NODE_VERSION:=26}"
: "${NVM_VERSION:=v0.41.0}"

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=5432}"
: "${DB_NAME:=praktikum_db}"
: "${DB_USER:=praktikum_user}"
: "${DB_PASSWORD:=}"

: "${NGINX_SITE:=praktikum}"
: "${NGINX_CONF_FILE:=praktikum.conf}"
: "${NGINX_ACCESS_LOG:=/var/log/nginx/praktikum_access.log}"
: "${NGINX_ERROR_LOG:=/var/log/nginx/praktikum_error.log}"

: "${GIT_BRANCH:=$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

: "${HEALTH_URL_APP:=http://${APP_HOST}:${APP_PORT}/api/health}"
: "${HEALTH_URL_NGINX:=http://127.0.0.1/api/health}"
: "${HEALTH_TIMEOUT:=30}"

# Ambang batas health check (persen / beban per core)
: "${MEM_WARN:=80}"
: "${MEM_CRIT:=90}"
: "${DISK_WARN:=80}"
: "${DISK_CRIT:=90}"
: "${LOAD_WARN:=1.0}"
: "${LOAD_CRIT:=2.0}"

CURRENT_USER="$(id -un)"
DRY_RUN=false
ASSUME_YES=false

# ---------- Warna & log ----------
setup_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
  else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
  fi
}
setup_colors

log_step() { printf '\n%s==> %s%s\n' "${C_BOLD}${C_BLUE}" "$*" "$C_RESET"; }
log_info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()      { log_err "$*"; exit 1; }

# ---------- Penanganan error otomatis ----------
on_error() {
  local code=$1 line=$2 cmd=$3
  log_err "Error (exit ${code}) di baris ${line}: ${cmd}"
}
set_error_trap() { trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR; }
set_error_trap

# ---------- Utilitas umum ----------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Jalankan perintah, atau hanya cetak jika --dry-run
run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s[DRY-RUN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# Tanya y/N
confirm() {
  local ans
  if [[ "$ASSUME_YES" == true ]]; then return 0; fi
  if [[ ! -t 0 ]]; then die "Butuh input interaktif. Gunakan --yes untuk melewati konfirmasi."; fi
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Minta pengguna mengetik kata tertentu (untuk aksi berbahaya)
confirm_phrase() {
  local phrase=$1 ans
  if [[ "$ASSUME_YES" == true ]]; then return 0; fi
  if [[ ! -t 0 ]]; then die "Butuh input interaktif. Gunakan --yes untuk melewati konfirmasi."; fi
  read -r -p "Ketik '${phrase}' untuk melanjutkan: " ans
  [[ "$ans" == "$phrase" ]]
}

# Ulangi perintah tiap 1 detik sampai berhasil atau waktu habis
#   wait_until <detik> <perintah...>
wait_until() {
  local timeout=$1 i
  shift
  for ((i = 0; i < timeout; i++)); do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}

require_not_root() {
  if [[ $EUID -eq 0 ]]; then
    die "Jangan jalankan sebagai root. Pakai user biasa; script memakai sudo bila perlu."
  fi
}

ensure_sudo() {
  has_cmd sudo || die "Perintah sudo tidak ditemukan."
  if ! sudo -n true 2>/dev/null; then
    log_info "Perlu hak sudo. Masukkan password user ${CURRENT_USER}."
    sudo -v || die "Gagal mendapatkan hak sudo."
  fi
}

# Password dipakai di SQL dan file .env, jadi karakternya dibatasi agar aman
require_db_password() {
  local re='^[A-Za-z0-9_.@%+=-]{8,64}$'
  [[ -n "$DB_PASSWORD" ]] || die "DB_PASSWORD kosong. Isi di ${SCRIPTS_DIR}/config.env"
  [[ "$DB_PASSWORD" =~ $re ]] || die "DB_PASSWORD tidak valid. Gunakan 8-64 karakter: huruf, angka, dan _ . @ % + = -"
}

# Catat seluruh output ke file log sekaligus tetap tampil di layar
enable_logging() {
  local name=$1
  mkdir -p "$LOG_DIR"
  LOG_FILE="${LOG_DIR}/${name}-$(date +%Y%m%d).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  setup_colors   # stdout bukan terminal lagi -> warna dimatikan
  printf '\n===== %s | %s | user=%s =====\n' "$name" "$(date '+%F %T')" "$CURRENT_USER"
}

# ---------- Node.js (NVM) ----------
# nvm.sh tidak kompatibel dengan `set -eu` dan trap ERR, jadi dimatikan sementara
_nvm_guard_begin() { trap - ERR; set +eu; }
_nvm_guard_end()   { set -eu; set_error_trap; }

load_nvm() {
  local rc
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  [[ -s "$NVM_DIR/nvm.sh" ]] || return 1
  _nvm_guard_begin
  # shellcheck disable=SC1091
  source "$NVM_DIR/nvm.sh"
  rc=$?
  _nvm_guard_end
  return "$rc"
}

nvm_run() {
  local rc
  _nvm_guard_begin
  nvm "$@"
  rc=$?
  _nvm_guard_end
  return "$rc"
}

# Pastikan node & npm tersedia (versi sesuai NODE_VERSION)
use_node() {
  if load_nvm; then
    nvm_run use "$NODE_VERSION" >/dev/null \
      || die "Node.js ${NODE_VERSION} belum terpasang. Jalankan ./02-setup-node.sh"
  fi
  has_cmd node || die "Node.js tidak ditemukan. Jalankan ./02-setup-node.sh"
}

# ---------- PostgreSQL ----------
# Jalankan SQL (dari argumen) sebagai superuser postgres. Selalu dijalankan.
pg_query() {
  printf '%s\n' "$1" | ( cd / && sudo -u postgres psql -v ON_ERROR_STOP=1 -qtA )
}
# Sama seperti pg_query, tetapi hanya dicetak saat --dry-run
pg_exec() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s[DRY-RUN]%s psql (postgres): %s\n' "$C_YELLOW" "$C_RESET" "$1"
  else
    pg_query "$1"
  fi
}
# psql sebagai user aplikasi (password lewat env hanya untuk perintah ini)
psql_app() {
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q "$@"
}

# ---------- Jaringan ----------
port_listening() { [[ -n "$(ss -H -tln "sport = :$1")" ]]; }
port_bind_addr() { ss -H -tln "sport = :$1" | awk 'NR==1 {print $4}'; }

# true jika endpoint /api/health menjawab 200 dengan "status":"ok"
app_healthy() { curl -fsS --max-time 5 "$1" 2>/dev/null | grep -q '"status":"ok"'; }

apt_install() {
  run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}
