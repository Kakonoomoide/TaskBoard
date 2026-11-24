#!/usr/bin/env bash
# =====================================================================
#  pm2-manage.sh - Pengelolaan aplikasi di PM2
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
Penggunaan: ./pm2-manage.sh <perintah> [argumen]

  status            ringkasan proses + status auto-start
  start             jalankan aplikasi (dari ecosystem.config.js)
  stop              hentikan aplikasi (tetap terdaftar)
  restart           restart aplikasi
  reload            reload aplikasi tanpa downtime (zero-downtime jika memungkinkan)
  logs [N]          tampilkan N baris log terakhir (default 50)
  follow            ikuti log secara live (Ctrl+C untuk keluar)
  info              detail lengkap proses
  save              simpan daftar proses (dipakai saat server reboot)
  startup           daftarkan PM2 sebagai service systemd (auto-start)
  flush             kosongkan file log
  delete            hapus proses dari PM2 (minta konfirmasi)
  menu              menu interaktif (default jika tanpa perintah)

Contoh:
  ./pm2-manage.sh status
  ./pm2-manage.sh logs 100
USAGE
}

setup_pm2() {
  require_not_root
  use_node
  has_cmd pm2 || die "PM2 belum terpasang. Jalankan ./04-setup-pm2.sh"
}

proc_exists() { pm2 describe "$PM2_APP_NAME" >/dev/null 2>&1; }

need_proc() {
  proc_exists || die "Proses '${PM2_APP_NAME}' belum terdaftar. Jalankan: ./pm2-manage.sh start"
}

cmd_status() {
  pm2 status
  if systemctl is-enabled --quiet "pm2-${CURRENT_USER}" 2>/dev/null; then
    log_ok "Auto-start saat boot: AKTIF"
  else
    log_warn "Auto-start saat boot: BELUM aktif (./pm2-manage.sh startup)"
  fi
}

cmd_start() {
  if proc_exists; then
    pm2 start "$PM2_APP_NAME"
  else
    (cd "$APP_DIR" && pm2 start ecosystem.config.js)
  fi
  pm2 save >/dev/null
  log_ok "Aplikasi berjalan."
}

cmd_stop()    { need_proc; pm2 stop "$PM2_APP_NAME"; pm2 save >/dev/null; log_ok "Aplikasi dihentikan."; }
cmd_restart() { need_proc; pm2 restart "$PM2_APP_NAME" --update-env; log_ok "Aplikasi di-restart."; }
cmd_reload()  { need_proc; pm2 reload "$PM2_APP_NAME" --update-env; log_ok "Aplikasi di-reload."; }

cmd_logs() {
  local n="${1:-50}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "Jumlah baris harus angka."
  need_proc
  pm2 logs "$PM2_APP_NAME" --lines "$n" --nostream
}

cmd_follow() { need_proc; pm2 logs "$PM2_APP_NAME" --lines 20; }
cmd_info()   { need_proc; pm2 describe "$PM2_APP_NAME"; }
cmd_save()   { pm2 save; }

cmd_startup() {
  ensure_sudo
  local node_bin_dir
  node_bin_dir="$(dirname "$(command -v node)")"
  sudo env PATH="${PATH}:${node_bin_dir}" "$(command -v pm2)" startup systemd -u "$CURRENT_USER" --hp "$HOME"
  pm2 save
  log_ok "PM2 terdaftar sebagai service systemd (pm2-${CURRENT_USER})."
}

cmd_flush() { pm2 flush; log_ok "Log dikosongkan."; }

cmd_delete() {
  need_proc
  confirm "Hapus proses '${PM2_APP_NAME}' dari PM2?" || die "Dibatalkan."
  pm2 delete "$PM2_APP_NAME"
  pm2 save --force >/dev/null
  log_ok "Proses dihapus."
}

cmd_menu() {
  local opt
  PS3=$'\nPilih nomor: '
  select opt in "Status" "Start" "Stop" "Restart" "Reload" "Log 50 baris" "Info" "Save" "Keluar"; do
    case "$opt" in
      "Status")       ( cmd_status )   || true ;;
      "Start")        ( cmd_start )    || true ;;
      "Stop")         ( cmd_stop )     || true ;;
      "Restart")      ( cmd_restart )  || true ;;
      "Reload")       ( cmd_reload )   || true ;;
      "Log 50 baris") ( cmd_logs 50 )  || true ;;
      "Info")         ( cmd_info )     || true ;;
      "Save")         ( cmd_save )     || true ;;
      "Keluar")       break ;;
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
  setup_pm2
  case "$cmd" in
    status)  cmd_status ;;
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    reload)  cmd_reload ;;
    logs)    cmd_logs "$@" ;;
    follow)  cmd_follow ;;
    info)    cmd_info ;;
    save)    cmd_save ;;
    startup) cmd_startup ;;
    flush)   cmd_flush ;;
    delete)  cmd_delete ;;
    menu)    cmd_menu ;;
    *) usage; die "Perintah tidak dikenal: ${cmd}" ;;
  esac
}

main "$@"
