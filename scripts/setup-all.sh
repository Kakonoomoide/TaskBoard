#!/usr/bin/env bash
# =====================================================================
#  setup-all.sh
#  Menjalankan seluruh setup Minggu 1 secara berurutan (01 s/d 05),
#  lalu health check. Hasil sama seperti mengerjakan modul minggu 1.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

STEPS=(
  01-setup-database.sh
  02-setup-node.sh
  03-setup-app.sh
  04-setup-pm2.sh
  05-setup-nginx.sh
)
FROM=1

usage() {
  cat <<USAGE
Penggunaan: ./setup-all.sh [--from N]

  --from N   mulai dari langkah ke-N (1-${#STEPS[@]}), berguna jika langkah sebelumnya sudah selesai
  -h         bantuan
USAGE
}

while (( $# )); do
  case "$1" in
    --from)
      [[ $# -ge 2 ]] || die "--from butuh angka"
      FROM="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opsi tidak dikenal: $1" ;;
  esac
  shift
done

[[ "$FROM" =~ ^[0-9]+$ ]] && (( FROM >= 1 && FROM <= ${#STEPS[@]} )) \
  || die "--from harus angka 1-${#STEPS[@]}"

require_not_root
ensure_sudo
require_db_password

enable_logging setup-all
total_start=$SECONDS

for ((i = FROM - 1; i < ${#STEPS[@]}; i++)); do
  step="${STEPS[$i]}"
  log_step "[$((i + 1))/${#STEPS[@]}] ${step}"
  step_start=$SECONDS
  bash "${SCRIPTS_DIR}/${step}"
  log_ok "${step} selesai ($((SECONDS - step_start)) detik)"
done

log_step "Health check akhir"
bash "${SCRIPTS_DIR}/health.sh" || true

log_ok "Setup selesai dalam $((SECONDS - total_start)) detik. Log: ${LOG_FILE}"
