#!/usr/bin/env bash
# =====================================================================
#  deploy.sh - Auto deploy dari GitHub
#
#  Alur: git pull -> npm install (jika perlu) -> build CSS -> (schema DB)
#        -> sinkron Nginx -> PM2 reload -> health check
#        -> jika gagal: ROLLBACK otomatis ke commit sebelumnya.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$LIB_DIR/nginx.sh"

SKIP_PULL=false
WITH_DB=false
NO_ROLLBACK=false
FORCE=false
FAIL_REASON=""   # diisi langkah yang gagal agar pesan error jelas

usage() {
  cat <<USAGE
Penggunaan: ./deploy.sh [opsi]

  -b, --branch NAMA   branch yang di-pull (default: ${GIT_BRANCH})
      --skip-pull     jangan git pull, deploy kode yang ada sekarang
      --with-db       jalankan ulang database/02_schema.sql (aman: IF NOT EXISTS)
  -f, --force         deploy walau tidak ada commit baru
      --no-rollback   jangan rollback otomatis bila gagal
  -h, --help          bantuan

Kode keluar: 0 = sukses, 1 = gagal (dan sudah rollback bila diaktifkan)
USAGE
}

while (( $# )); do
  case "$1" in
    -b|--branch)
      [[ $# -ge 2 ]] || die "--branch butuh nama branch"
      GIT_BRANCH="$2"; shift ;;
    --skip-pull)   SKIP_PULL=true ;;
    --with-db)     WITH_DB=true ;;
    -f|--force)    FORCE=true ;;
    --no-rollback) NO_ROLLBACK=true ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Opsi tidak dikenal: $1 (lihat --help)" ;;
  esac
  shift
done

require_not_root
enable_logging deploy
START=$SECONDS

# ---------- Fungsi langkah ----------
deps_changed() {
  local rel
  rel="$(realpath --relative-to="$ROOT_DIR" "$APP_DIR")"
  git diff --name-only "$PREV_COMMIT" "$NEW_COMMIT" | grep -qE "^${rel}/package(-lock)?\.json$"
}

step_deps() {
  log_step "2/6  Dependency & CSS"
  cd "$APP_DIR"
  if [[ ! -d node_modules ]] || deps_changed; then
    log_info "package.json berubah / node_modules belum ada -> npm install"
    npm install --no-audit --no-fund
  else
    log_info "package.json tidak berubah, npm install dilewati."
  fi
  npm run build:css --silent
  log_ok "CSS Tailwind ter-build."
}

step_db() {
  log_step "3/6  Database"
  if [[ "$WITH_DB" == true ]]; then
    require_db_password
    psql_app -f "${DB_DIR}/02_schema.sql"
    log_ok "Schema dijalankan ulang."
  else
    log_info "Dilewati (pakai --with-db untuk menjalankan schema)."
  fi
}

step_nginx() {
  log_step "4/6  Nginx"
  if ! has_cmd nginx; then log_warn "Nginx belum terpasang, dilewati."; return 0; fi
  ensure_sudo
  local rc=0
  nginx_sync_conf || rc=$?
  case "$rc" in
    0)  log_ok "Konfigurasi Nginx diperbarui & di-reload." ;;
    10) log_info "Konfigurasi Nginx tidak berubah." ;;
    *)  FAIL_REASON="konfigurasi Nginx gagal diuji/diterapkan"; return 1 ;;
  esac
}

step_pm2() {
  log_step "5/6  PM2 reload"
  cd "$APP_DIR"
  pm2 startOrReload ecosystem.config.js --update-env
  pm2 save >/dev/null
  log_ok "Proses ${PM2_APP_NAME} di-reload."
}

step_health() {
  log_step "6/6  Health check (maks ${HEALTH_TIMEOUT} detik)"
  if ! wait_until "$HEALTH_TIMEOUT" app_healthy "$HEALTH_URL_APP"; then
    FAIL_REASON="aplikasi tidak sehat setelah ${HEALTH_TIMEOUT} detik (${HEALTH_URL_APP})"
    return 1
  fi
  log_ok "Aplikasi sehat: ${HEALTH_URL_APP}"
  if has_cmd nginx && port_listening 80; then
    if ! wait_until 10 app_healthy "$HEALTH_URL_NGINX"; then
      FAIL_REASON="aplikasi sehat, tetapi request lewat Nginx gagal (${HEALTH_URL_NGINX})"
      return 1
    fi
    log_ok "Lewat Nginx juga sehat: ${HEALTH_URL_NGINX}"
  fi
}

# ---------- Rollback ----------
rollback() {
  log_warn "ROLLBACK ke commit ${PREV_COMMIT:0:7} ..."
  git -C "$ROOT_DIR" reset --hard "$PREV_COMMIT"
  cd "$APP_DIR"
  npm install --no-audit --no-fund
  npm run build:css --silent
  if has_cmd nginx; then
    local rc=0
    nginx_sync_conf || rc=$?
  fi
  pm2 startOrReload ecosystem.config.js --update-env
  if wait_until "$HEALTH_TIMEOUT" app_healthy "$HEALTH_URL_APP"; then
    log_ok "Rollback berhasil. Aplikasi kembali berjalan di versi ${PREV_COMMIT:0:7}."
  else
    log_err "Rollback selesai tetapi aplikasi masih tidak sehat. Cek: ./pm2-manage.sh logs"
  fi
}

on_deploy_error() {
  local code=$1 line=$2 cmd=$3
  trap - ERR
  set +e
  if [[ -n "$FAIL_REASON" ]]; then
    log_err "Deploy GAGAL: ${FAIL_REASON}"
  else
    log_err "Deploy GAGAL (exit ${code}) di baris ${line}: ${cmd}"
  fi
  if [[ "$NO_ROLLBACK" == true ]]; then
    log_warn "--no-rollback aktif: tidak ada rollback."
  elif [[ "$NEW_COMMIT" == "$PREV_COMMIT" ]]; then
    log_warn "Tidak ada commit sebelumnya untuk rollback (kode tidak berubah)."
  else
    rollback
  fi
  log_info "Log lengkap: ${LOG_FILE}"
  exit 1
}

trap 'log_warn "Dibatalkan oleh pengguna."; exit 130' INT

# ---------- Pra-pemeriksaan ----------
log_step "Pra-pemeriksaan"
use_node
has_cmd pm2 || die "PM2 belum terpasang. Jalankan ./04-setup-pm2.sh"
has_cmd git || die "git belum terpasang."
[[ -f "${APP_DIR}/.env" ]] || die "apps/.env belum ada. Jalankan ./03-setup-app.sh"
git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "${ROOT_DIR} bukan repository git."

cd "$ROOT_DIR"
PREV_COMMIT="$(git rev-parse HEAD)"
NEW_COMMIT="$PREV_COMMIT"
log_ok "Node $(node -v) | commit saat ini: ${PREV_COMMIT:0:7} | branch: ${GIT_BRANCH}"

# ---------- 1. Ambil kode ----------
log_step "1/6  Ambil kode terbaru"
if [[ "$SKIP_PULL" == true ]]; then
  log_warn "--skip-pull: memakai kode yang ada."
else
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    die "Ada perubahan lokal yang belum di-commit. Commit/stash dulu atau pakai --skip-pull."
  fi
  git fetch --quiet origin
  git pull --ff-only origin "$GIT_BRANCH"
  NEW_COMMIT="$(git rev-parse HEAD)"
fi

if [[ "$NEW_COMMIT" == "$PREV_COMMIT" && "$FORCE" != true && "$SKIP_PULL" != true ]]; then
  log_ok "Sudah versi terbaru (${NEW_COMMIT:0:7}). Tidak ada yang perlu di-deploy. (Pakai --force untuk memaksa.)"
  exit 0
fi
if [[ "$NEW_COMMIT" != "$PREV_COMMIT" ]]; then
  git log --oneline "${PREV_COMMIT}..${NEW_COMMIT}"
fi

# Mulai titik rawan: error apa pun setelah ini memicu rollback otomatis
trap 'on_deploy_error $? $LINENO "$BASH_COMMAND"' ERR

step_deps
step_db
step_nginx
step_pm2
step_health

trap - ERR
log_step "Deploy sukses"
log_ok "${PREV_COMMIT:0:7} -> ${NEW_COMMIT:0:7} dalam $((SECONDS - START)) detik"
log_info "Log: ${LOG_FILE}"
