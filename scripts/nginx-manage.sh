#!/usr/bin/env bash
# =====================================================================
#  nginx-manage.sh - Pengelolaan & status Nginx
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
source "$LIB_DIR/nginx.sh"

usage() {
  cat <<USAGE
Penggunaan: ./nginx-manage.sh <perintah> [argumen]

  status                 status service, versi, site aktif, port, uji konfigurasi
  test                   uji sintaks konfigurasi (nginx -t)
  reload                 uji lalu reload konfigurasi (tanpa putus koneksi)
  restart                uji lalu restart Nginx
  start | stop           jalankan / hentikan Nginx
  sync                   salin nginx/${NGINX_CONF_FILE} dari repo ke server, uji, reload
  enable | disable       aktifkan / nonaktifkan site '${NGINX_SITE}'
  logs [access|error] [N]   N baris terakhir (default: error, 30)
  follow [access|error]     ikuti log live (Ctrl+C untuk keluar)
  stats                  hitung jumlah request per kode HTTP (dari access log)
  top-ips [N]            N IP terbanyak mengakses (default 5)
  rate-test [N] [path]   kirim N request beruntun (default 30 ke /api/tasks), hitung kode HTTP
  menu                   menu interaktif (default jika tanpa perintah)
USAGE
}

setup_nginx() {
  require_not_root
  has_cmd nginx || die "Nginx belum terpasang. Jalankan ./05-setup-nginx.sh"
  ensure_sudo
}

log_file_for() {
  case "${1:-error}" in
    access) printf '%s' "$NGINX_ACCESS_LOG" ;;
    error)  printf '%s' "$NGINX_ERROR_LOG" ;;
    *) die "Jenis log harus 'access' atau 'error'." ;;
  esac
}

cmd_status() {
  log_step "Service"
  if systemctl is-active --quiet nginx; then log_ok "nginx: aktif"; else log_err "nginx: TIDAK aktif"; fi
  if systemctl is-enabled --quiet nginx; then log_ok "auto-start: aktif"; else log_warn "auto-start: belum aktif"; fi
  log_info "versi: $(nginx -v 2>&1)"

  log_step "Site"
  if [[ -L "$(nginx_conf_link)" ]]; then log_ok "site '${NGINX_SITE}' aktif"; else log_warn "site '${NGINX_SITE}' TIDAK aktif"; fi
  if [[ -f "$(nginx_conf_dst)" && -f "$(nginx_conf_src)" ]]; then
    if cmp -s "$(nginx_conf_src)" "$(nginx_conf_dst)"; then
      log_ok "konfigurasi server sama dengan repo"
    else
      log_warn "konfigurasi server BERBEDA dari repo (jalankan: ./nginx-manage.sh sync)"
    fi
  fi
  if [[ -e /etc/nginx/sites-enabled/default ]]; then log_warn "site 'default' masih aktif"; fi

  log_step "Port"
  if port_listening 80; then log_ok "port 80 listen ($(port_bind_addr 80))"; else log_err "port 80 tidak listen"; fi

  log_step "Uji konfigurasi"
  if sudo nginx -t >/dev/null 2>&1; then log_ok "nginx -t: sintaks OK"; else log_err "nginx -t: ERROR"; sudo nginx -t || true; fi

  log_step "Proses"
  ps -C nginx -o pid,user,etime,cmd --no-headers | head -n 5 || true
}

cmd_test() { sudo nginx -t; }

cmd_reload() {
  sudo nginx -t
  sudo systemctl reload nginx
  log_ok "Nginx di-reload."
}

cmd_restart() {
  sudo nginx -t
  sudo systemctl restart nginx
  log_ok "Nginx di-restart."
}

cmd_start() { sudo systemctl start nginx; log_ok "Nginx dijalankan."; }

cmd_stop() {
  confirm "Hentikan Nginx? Website tidak bisa diakses." || die "Dibatalkan."
  sudo systemctl stop nginx
  log_warn "Nginx dihentikan."
}

cmd_sync() {
  local rc=0
  nginx_sync_conf || rc=$?
  case "$rc" in
    0)  log_ok "Konfigurasi diperbarui dari repo & di-reload." ;;
    10) log_ok "Tidak ada perubahan: server sudah sama dengan repo." ;;
    *)  die "Sinkronisasi gagal (konfigurasi lama dikembalikan)." ;;
  esac
}

cmd_enable() {
  [[ -f "$(nginx_conf_dst)" ]] || die "Site belum ada di server. Jalankan: ./nginx-manage.sh sync"
  sudo ln -sfn "$(nginx_conf_dst)" "$(nginx_conf_link)"
  cmd_reload
}

cmd_disable() {
  confirm "Nonaktifkan site '${NGINX_SITE}'?" || die "Dibatalkan."
  sudo rm -f "$(nginx_conf_link)"
  cmd_reload
  log_warn "Site '${NGINX_SITE}' dinonaktifkan."
}

cmd_logs() {
  local file n="${2:-30}"
  file="$(log_file_for "${1:-error}")"
  [[ "$n" =~ ^[0-9]+$ ]] || die "Jumlah baris harus angka."
  sudo tail -n "$n" "$file"
}

cmd_follow() { sudo tail -f "$(log_file_for "${1:-error}")"; }

cmd_stats() {
  [[ -f "$NGINX_ACCESS_LOG" ]] || die "Access log belum ada: $NGINX_ACCESS_LOG"
  log_info "Jumlah request per kode HTTP:"
  sudo awk '{print $9}' "$NGINX_ACCESS_LOG" | sort | uniq -c | sort -rn
  local total limited
  total="$(sudo wc -l < "$NGINX_ACCESS_LOG")"
  limited="$(sudo awk '$9 == 429' "$NGINX_ACCESS_LOG" | wc -l)"
  log_info "Total ${total} request, ${limited} ditolak rate limiter (429)."
}

cmd_top_ips() {
  local n="${1:-5}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "Jumlah harus angka."
  [[ -f "$NGINX_ACCESS_LOG" ]] || die "Access log belum ada: $NGINX_ACCESS_LOG"
  log_info "${n} IP terbanyak:"
  sudo awk '{print $1}' "$NGINX_ACCESS_LOG" | sort | uniq -c | sort -rn | head -n "$n"
}

cmd_rate_test() {
  local n="${1:-30}" path="${2:-/api/tasks}" url i code
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 500 )) || die "N harus angka 1-500."
  url="http://127.0.0.1${path}"
  declare -A count=()

  log_info "Mengirim ${n} request ke ${url} ..."
  for ((i = 1; i <= n; i++)); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
    count[$code]=$(( ${count[$code]:-0} + 1 ))
    printf '%s ' "$code"
  done
  printf '\n\nRingkasan:\n'
  for code in "${!count[@]}"; do
    printf '  HTTP %s : %d request\n' "$code" "${count[$code]}"
  done | sort

  if (( ${count[429]:-0} > 0 )); then
    log_ok "Rate limiter bekerja: ${count[429]} request ditolak (429)."
  else
    log_warn "Tidak ada 429. Naikkan N atau cek limit_req di konfigurasi."
  fi
}

cmd_menu() {
  local opt
  PS3=$'\nPilih nomor: '
  select opt in "Status" "Test konfigurasi" "Reload" "Restart" "Sync dari repo" "Log error (30)" "Log access (30)" "Statistik kode HTTP" "Top IP" "Uji rate limiter" "Keluar"; do
    case "$opt" in
      "Status")              ( cmd_status )          || true ;;
      "Test konfigurasi")    ( cmd_test )            || true ;;
      "Reload")              ( cmd_reload )          || true ;;
      "Restart")             ( cmd_restart )         || true ;;
      "Sync dari repo")      ( cmd_sync )            || true ;;
      "Log error (30)")      ( cmd_logs error 30 )   || true ;;
      "Log access (30)")     ( cmd_logs access 30 )  || true ;;
      "Statistik kode HTTP") ( cmd_stats )           || true ;;
      "Top IP")              ( cmd_top_ips 5 )       || true ;;
      "Uji rate limiter")    ( cmd_rate_test 30 )    || true ;;
      "Keluar")              break ;;
      *) echo "Pilihan tidak valid." ;;
    esac
  done
}

main() {
  local cmd="${1:-menu}"
  shift || true
  case "$cmd" in
    -h|--help|help) usage; return 0 ;;
  esac
  setup_nginx
  case "$cmd" in
    status)    cmd_status ;;
    test)      cmd_test ;;
    reload)    cmd_reload ;;
    restart)   cmd_restart ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    sync)      cmd_sync ;;
    enable)    cmd_enable ;;
    disable)   cmd_disable ;;
    logs)      cmd_logs "$@" ;;
    follow)    cmd_follow "$@" ;;
    stats)     cmd_stats ;;
    top-ips)   cmd_top_ips "$@" ;;
    rate-test) cmd_rate_test "$@" ;;
    menu)      cmd_menu ;;
    *) usage; die "Perintah tidak dikenal: ${cmd}" ;;
  esac
}

main "$@"
