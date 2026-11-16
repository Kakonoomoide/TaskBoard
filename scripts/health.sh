#!/usr/bin/env bash
# =====================================================================
#  health.sh - Cek kesehatan server & aplikasi
#
#  Memeriksa: sistem (load, memori, disk), service (PostgreSQL, Nginx, PM2),
#  port, dan endpoint HTTP. Cocok dijalankan manual maupun lewat cron.
#
#  Kode keluar:  0 = semua OK   1 = ada WARNING   2 = ada yang GAGAL
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

QUIET=false
WATCH=0

usage() {
  cat <<USAGE
Penggunaan: ./health.sh [opsi]

  -q, --quiet         hanya tampilkan masalah + 1 baris ringkasan (cocok untuk cron)
  -w, --watch DETIK   ulangi pemeriksaan tiap DETIK detik (Ctrl+C untuk berhenti)
  -h, --help          bantuan

Contoh cron (tiap 5 menit, simpan ke log):
  */5 * * * * ${SCRIPTS_DIR}/health.sh -q >> ${LOG_DIR}/health.log 2>&1
USAGE
}

while (( $# )); do
  case "$1" in
    -q|--quiet) QUIET=true ;;
    -w|--watch)
      [[ $# -ge 2 ]] || die "--watch butuh jumlah detik"
      WATCH="$2"; shift
      [[ "$WATCH" =~ ^[0-9]+$ ]] && (( WATCH > 0 )) || die "--watch harus angka > 0"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opsi tidak dikenal: $1 (lihat --help)" ;;
  esac
  shift
done

has_cmd curl || die "curl diperlukan: sudo apt install -y curl"

# ---------- Pelaporan ----------
OK_N=0; WARN_N=0; FAIL_N=0
LAST_BODY=""

report() {
  local level=$1 label=$2 detail=${3:-} tag=""
  case "$level" in
    ok)   OK_N=$((OK_N + 1));     tag="${C_GREEN}[ OK ]${C_RESET}" ;;
    warn) WARN_N=$((WARN_N + 1)); tag="${C_YELLOW}[WARN]${C_RESET}" ;;
    fail) FAIL_N=$((FAIL_N + 1)); tag="${C_RED}[FAIL]${C_RESET}" ;;
  esac
  if [[ "$level" != ok || "$QUIET" != true ]]; then
    printf '  %s %-24s %s\n' "$tag" "$label" "$detail"
  fi
}

info_line() {
  if [[ "$QUIET" != true ]]; then printf '  %s %-24s %s\n' "${C_BLUE}[INFO]${C_RESET}" "$1" "$2"; fi
}

section() {
  if [[ "$QUIET" != true ]]; then printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; fi
}

# Bandingkan angka bulat dengan ambang warn & crit -> ok | warn | fail
level_for() {
  local v=$1 w=$2 c=$3
  if (( v >= c )); then echo fail
  elif (( v >= w )); then echo warn
  else echo ok
  fi
}

# ---------- Pemeriksaan ----------
check_system() {
  section "Sistem"
  local os load1 cores ratio lvl mem disk
  os="$( (. /etc/os-release && printf '%s' "$PRETTY_NAME") 2>/dev/null || echo unknown)"
  info_line "Host" "$(hostname)"
  info_line "OS" "$os"
  info_line "Uptime" "$(uptime -p 2>/dev/null || echo '-')"

  read -r load1 _ < /proc/loadavg
  cores="$(nproc)"
  lvl="$(awk -v l="$load1" -v c="$cores" -v w="$LOAD_WARN" -v k="$LOAD_CRIT" \
    'BEGIN { r = l / c; if (r >= k) print "fail"; else if (r >= w) print "warn"; else print "ok" }')"
  report "$lvl" "Load average" "${load1} (${cores} core)"

  mem="$(free | awk '/^Mem:/ {printf "%d", ($2 - $7) * 100 / $2}')"
  report "$(level_for "$mem" "$MEM_WARN" "$MEM_CRIT")" "Memori terpakai" "${mem}%"

  disk="$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')"
  report "$(level_for "$disk" "$DISK_WARN" "$DISK_CRIT")" "Disk / terpakai" "${disk}%"
}

# Ringkasan proses PM2: "online restarts=0 mem=60MB cpu=0%" / "missing" / "error"
pm2_summary() {
  pm2 jlist 2>/dev/null | node -e '
    let s = "";
    process.stdin.on("data", d => s += d).on("end", () => {
      try {
        const line = s.split("\n").reverse().find(l => /^\[(\{|\])/.test(l.trim()));
        const list = JSON.parse(line);
        const p = list.find(x => x.name === process.argv[1]);
        if (!p) { console.log("missing"); return; }
        const mb = Math.round(p.monit.memory / 1048576);
        console.log(`${p.pm2_env.status} restarts=${p.pm2_env.restart_time} mem=${mb}MB cpu=${p.monit.cpu}%`);
      } catch (e) { console.log("error"); }
    });
  ' "$PM2_APP_NAME"
}

check_services() {
  section "Service"
  local sum out

  if has_cmd pg_isready && pg_isready -q -h "$DB_HOST" -p "$DB_PORT"; then
    report ok "PostgreSQL" "menerima koneksi (${DB_HOST}:${DB_PORT})"
  else
    report fail "PostgreSQL" "tidak merespons di ${DB_HOST}:${DB_PORT}"
  fi

  if [[ -n "$DB_PASSWORD" ]] && has_cmd psql; then
    if out="$(psql_app -tAc 'SELECT count(*) FROM tasks' 2>&1)"; then
      report ok "Login database" "${DB_USER}@${DB_NAME}, tasks=${out}"
    else
      report fail "Login database" "gagal login sebagai ${DB_USER}"
    fi
  else
    info_line "Login database" "dilewati (DB_PASSWORD kosong / psql tidak ada)"
  fi

  if systemctl is-active --quiet nginx 2>/dev/null; then
    report ok "Nginx" "service aktif"
  else
    report fail "Nginx" "service tidak aktif"
  fi
  if [[ -L "/etc/nginx/sites-enabled/${NGINX_SITE}" ]]; then
    report ok "Site Nginx" "${NGINX_SITE} aktif"
  else
    report warn "Site Nginx" "${NGINX_SITE} belum diaktifkan"
  fi

  load_nvm || true
  nvm_run use "$NODE_VERSION" >/dev/null 2>&1 || true
  if has_cmd pm2 && has_cmd node; then
    sum="$(pm2_summary)"
    case "${sum%% *}" in
      online)  report ok "PM2: ${PM2_APP_NAME}" "$sum" ;;
      missing) report fail "PM2: ${PM2_APP_NAME}" "tidak terdaftar di PM2" ;;
      error)   report fail "PM2: ${PM2_APP_NAME}" "gagal membaca status PM2" ;;
      *)       report fail "PM2: ${PM2_APP_NAME}" "$sum" ;;
    esac
    if systemctl is-enabled --quiet "pm2-${CURRENT_USER}" 2>/dev/null; then
      report ok "PM2 auto-start" "aktif (pm2-${CURRENT_USER})"
    else
      report warn "PM2 auto-start" "belum aktif (jalankan ./pm2-manage.sh startup)"
    fi
  else
    report fail "PM2" "pm2 / node tidak ditemukan"
  fi
}

check_ports() {
  section "Port"
  local entry port label addr
  local exposed_re='^(0\.0\.0\.0|\*|\[::\])'
  for entry in "80:Nginx (publik)" "${APP_PORT}:Aplikasi (lokal)" "${DB_PORT}:PostgreSQL (lokal)"; do
    port="${entry%%:*}"
    label="${entry#*:}"
    if ! port_listening "$port"; then
      report fail "Port ${port}" "${label} tidak listen"
      continue
    fi
    addr="$(port_bind_addr "$port")"
    if [[ "$port" != "80" && "$addr" =~ $exposed_re ]]; then
      report warn "Port ${port}" "${label} listen di ${addr} (terbuka ke publik!)"
    else
      report ok "Port ${port}" "${label} - ${addr}"
    fi
  done
}

# check_url <label> <url> : isi LAST_BODY, laporkan kode HTTP & waktu respons
check_url() {
  local label=$1 url=$2 resp tail code secs
  resp="$(curl -s --max-time 5 -w $'\n%{http_code} %{time_total}' "$url" 2>/dev/null || true)"
  tail="${resp##*$'\n'}"
  LAST_BODY="${resp%$'\n'*}"
  code="${tail%% *}"
  secs="${tail##* }"
  if [[ "$code" == "200" ]]; then
    if awk -v t="$secs" 'BEGIN { exit !(t > 1.0) }'; then
      report warn "$label" "HTTP 200 tapi lambat (${secs}s)"
    else
      report ok "$label" "HTTP 200 (${secs}s)"
    fi
  else
    report fail "$label" "HTTP ${code} <- ${url}"
  fi
}

check_http() {
  section "Endpoint HTTP"
  check_url "App langsung (:${APP_PORT})" "$HEALTH_URL_APP"
  check_url "Lewat Nginx (:80)" "$HEALTH_URL_NGINX"
  if [[ "$LAST_BODY" == *'"via_nginx":true'* ]]; then
    report ok "Reverse proxy" "request tercatat melewati Nginx"
  elif [[ -n "$LAST_BODY" ]]; then
    report warn "Reverse proxy" "respons tidak lewat Nginx"
  fi
}

run_checks() {
  OK_N=0; WARN_N=0; FAIL_N=0
  if [[ "$QUIET" != true ]]; then
    printf '%s=== Server Health Report | %s ===%s\n' "$C_BOLD" "$(date '+%F %T')" "$C_RESET"
  fi
  check_system
  check_services
  check_ports
  check_http

  local status="OK"
  EXIT_CODE=0
  if (( FAIL_N > 0 )); then status="CRITICAL"; EXIT_CODE=2
  elif (( WARN_N > 0 )); then status="WARNING"; EXIT_CODE=1
  fi
  printf '\n%s %s%s%s | ok=%d warn=%d fail=%d\n' \
    "$(date '+%F %T')" "${C_BOLD}" "$status" "${C_RESET}" "$OK_N" "$WARN_N" "$FAIL_N"
}

EXIT_CODE=0
if (( WATCH > 0 )); then
  while true; do
    clear
    run_checks
    printf '\nRefresh tiap %ss. Tekan Ctrl+C untuk berhenti.\n' "$WATCH"
    sleep "$WATCH"
  done
else
  run_checks
fi
exit "$EXIT_CODE"
