#!/usr/bin/env bash
# =====================================================================
#  docker-health.sh - Cek apakah stack Docker Compose sudah berjalan & sehat
#
#  Memeriksa: Docker daemon, status & healthcheck tiap container, jumlah restart,
#  port yang dibuka ke server, endpoint HTTP, volume, serta disk & memori.
#  Default untuk stack minggu 3 (folder docker/). Bisa dipakai untuk stack lain
#  lewat opsi -d dan -u.
#
#  Kode keluar:  0 = semua OK   1 = ada WARNING   2 = ada yang GAGAL
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DOCKER_DIR="${DOCKER_DIR:-$ROOT_DIR/docker}"
URL=""
QUIET=false
WATCH=0

usage() {
  cat <<USAGE
Penggunaan: ./docker-health.sh [opsi]

  -d, --dir FOLDER    folder yang berisi compose.yaml (default: docker/)
  -u, --url URL       alamat yang dicek (default: http://127.0.0.1:HTTP_PORT/api/health)
  -q, --quiet         hanya tampilkan masalah + 1 baris ringkasan
  -w, --watch DETIK   ulangi pemeriksaan tiap DETIK detik (Ctrl+C untuk berhenti)
  -h, --help          bantuan

Contoh:
  ./docker-health.sh                                   # stack minggu 3
  ./docker-health.sh -d ../wordpress -u http://127.0.0.1/wp-login.php   # stack WordPress
USAGE
}

while (( $# )); do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || die "--dir butuh nama folder"
      DOCKER_DIR="$(cd "$2" 2>/dev/null && pwd)" || die "Folder tidak ditemukan: $2"
      shift ;;
    -u|--url)
      [[ $# -ge 2 ]] || die "--url butuh alamat"
      URL="$2"; shift ;;
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

has_cmd docker || die "Docker belum terpasang. Jalankan ./install-docker.sh"
has_cmd curl || die "curl diperlukan: sudo apt install -y curl"
[[ -f "$DOCKER_DIR/compose.yaml" ]] || die "File tidak ditemukan: $DOCKER_DIR/compose.yaml"

dc() { docker compose --project-directory "$DOCKER_DIR" -f "$DOCKER_DIR/compose.yaml" "$@"; }

# Baca nilai dari file .env di folder compose
env_get() {
  local key=$1 default=${2:-} val=""
  if [[ -f "$DOCKER_DIR/.env" ]]; then
    val="$(grep -E "^${key}=" "$DOCKER_DIR/.env" | tail -n1 | cut -d= -f2- | tr -d '"' || true)"
  fi
  printf '%s' "${val:-$default}"
}

HTTP_PORT="$(env_get HTTP_PORT 80)"
[[ -n "$URL" ]] || URL="http://127.0.0.1:${HTTP_PORT}/api/health"

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

level_for() {
  local v=$1 w=$2 c=$3
  if (( v >= c )); then echo fail
  elif (( v >= w )); then echo warn
  else echo ok
  fi
}

# ---------- Pemeriksaan ----------
check_docker() {
  section "Docker"
  if docker info >/dev/null 2>&1; then
    report ok "Docker daemon" "berjalan, versi $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
  else
    report fail "Docker daemon" "tidak bisa diakses (login ulang / newgrp docker / sudo systemctl start docker)"
    return 1
  fi
  if docker compose version >/dev/null 2>&1; then
    report ok "Docker Compose" "$(docker compose version --short 2>/dev/null || echo terpasang)"
  else
    report fail "Docker Compose" "plugin compose tidak ditemukan"
  fi
}

check_containers() {
  section "Container ($(basename "$DOCKER_DIR"))"
  local service id line status health restarts services
  services="$(dc config --services 2>/dev/null || true)"
  if [[ -z "$services" ]]; then
    report fail "Compose" "tidak bisa membaca compose.yaml (cek docker compose config)"
    return 0
  fi

  PROJECT=""
  while read -r service; do
    [[ -n "$service" ]] || continue
    id="$(dc ps -q "$service" 2>/dev/null | head -n1 || true)"
    if [[ -z "$id" ]]; then
      report fail "$service" "container tidak ada (belum dijalankan? coba: docker compose up -d)"
      continue
    fi
    line="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}} {{.RestartCount}}' "$id" 2>/dev/null || true)"
    read -r status health restarts <<<"$line"
    [[ -n "$PROJECT" ]] || PROJECT="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2>/dev/null || true)"

    if [[ "$status" != "running" ]]; then
      report fail "$service" "status ${status:-tidak diketahui}"
    elif [[ "$health" == "unhealthy" ]]; then
      report fail "$service" "running tetapi UNHEALTHY (docker compose logs $service)"
    elif [[ "$health" == "starting" ]]; then
      report warn "$service" "running, healthcheck masih starting"
    elif (( ${restarts:-0} > 3 )); then
      report warn "$service" "running tetapi sudah restart ${restarts}x (cek log)"
    elif [[ "$health" == "healthy" ]]; then
      report ok "$service" "running, healthy (restart ${restarts:-0}x)"
    else
      report ok "$service" "running (tanpa healthcheck, restart ${restarts:-0}x)"
    fi
  done <<<"$services"
}

check_ports() {
  section "Port"
  local id exposed internal_re='^(5432|3306|6379|27017)/'
  if port_listening "$HTTP_PORT"; then
    report ok "Port ${HTTP_PORT}" "listen di server ($(port_bind_addr "$HTTP_PORT"))"
  else
    report fail "Port ${HTTP_PORT}" "tidak ada yang listen"
  fi

  # Database/cache tidak boleh dipublikasikan ke server
  local leak=false
  while read -r id; do
    [[ -n "$id" ]] || continue
    exposed="$(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{if $b}}{{$p}} {{end}}{{end}}' "$id" 2>/dev/null || true)"
    for p in $exposed; do
      if [[ "$p" =~ $internal_re ]]; then
        leak=true
        report warn "Port database" "container $(docker inspect -f '{{.Name}}' "$id" | tr -d '/') membuka ${p} ke server"
      fi
    done
  done <<<"$(dc ps -q 2>/dev/null || true)"
  if [[ "$leak" == false ]]; then report ok "Port internal" "database/cache tidak dibuka ke server"; fi
}

check_http() {
  section "Endpoint HTTP"
  local resp tail code secs
  resp="$(curl -s --max-time 5 -w $'\n%{http_code} %{time_total}' "$URL" 2>/dev/null || true)"
  tail="${resp##*$'\n'}"
  LAST_BODY="${resp%$'\n'*}"
  code="${tail%% *}"
  secs="${tail##* }"

  if [[ "$URL" == */api/health ]]; then
    if [[ "$code" == "200" && "$LAST_BODY" == *'"status":"ok"'* ]]; then
      report ok "Aplikasi sehat" "HTTP 200, status ok (${secs}s)"
    elif [[ "$code" == "200" ]]; then
      report warn "Aplikasi sehat" "HTTP 200 tetapi status tidak ok"
    else
      report fail "Aplikasi sehat" "HTTP ${code} <- ${URL}"
    fi
    if [[ "$LAST_BODY" == *'"connected":true'* ]]; then report ok "Database" "aplikasi terhubung ke database"; fi
    if [[ "$LAST_BODY" == *'"via_nginx":true'* ]]; then report ok "Reverse proxy" "request melewati Nginx container"; fi
  else
    if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]; then
      report ok "Web merespons" "HTTP ${code} (${secs}s)"
    else
      report fail "Web merespons" "HTTP ${code} <- ${URL}"
    fi
  fi
  if awk -v t="${secs:-0}" 'BEGIN { exit !(t > 1.5) }'; then report warn "Waktu respons" "lambat (${secs}s)"; fi
}

check_storage() {
  section "Volume & Resource"
  local count mem disk
  if [[ -n "${PROJECT:-}" ]]; then
    count="$(docker volume ls -q --filter "label=com.docker.compose.project=${PROJECT}" | wc -l)"
    if (( count > 0 )); then report ok "Volume data" "${count} volume untuk project ${PROJECT}"; else info_line "Volume data" "tidak ada volume (stack tanpa data persisten)"; fi
  fi
  mem="$(free | awk '/^Mem:/ {printf "%d", ($2 - $7) * 100 / $2}')"
  report "$(level_for "$mem" "$MEM_WARN" "$MEM_CRIT")" "Memori terpakai" "${mem}%"
  disk="$(df -P /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}' || true)"
  [[ -n "$disk" ]] || disk="$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')"
  report "$(level_for "$disk" "$DISK_WARN" "$DISK_CRIT")" "Disk Docker terpakai" "${disk}%"
}

run_checks() {
  OK_N=0; WARN_N=0; FAIL_N=0
  if [[ "$QUIET" != true ]]; then
    printf '%s=== Docker Health Report | %s ===%s\n' "$C_BOLD" "$(date '+%F %T')" "$C_RESET"
  fi
  if check_docker; then
    check_containers
    check_ports
    check_http
    check_storage
  fi

  local status="OK"
  EXIT_CODE=0
  if (( FAIL_N > 0 )); then status="CRITICAL"; EXIT_CODE=2
  elif (( WARN_N > 0 )); then status="WARNING"; EXIT_CODE=1
  fi
  printf '\n%s %s%s%s | ok=%d warn=%d fail=%d\n' \
    "$(date '+%F %T')" "$C_BOLD" "$status" "$C_RESET" "$OK_N" "$WARN_N" "$FAIL_N"
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
