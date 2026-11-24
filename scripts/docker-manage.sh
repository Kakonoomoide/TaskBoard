#!/usr/bin/env bash
# =====================================================================
#  docker-manage.sh - Pengelolaan stack Docker Compose (db + app + nginx)
#  Compose file: docker/compose.yaml   |   Konfigurasi: docker/.env
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DOCKER_DIR="${DOCKER_DIR:-$ROOT_DIR/docker}"

usage() {
  cat <<USAGE
Penggunaan: ./docker-manage.sh <perintah> [argumen]

  status              status container, pemakaian resource, dan health check
  up                  build image lalu jalankan semua service (background)
  down                hentikan & hapus container (DATA DATABASE AMAN)
  reset               down + hapus volume database (DATA HILANG, minta konfirmasi)
  restart [service]   restart semua / satu service (db | app | nginx)
  rebuild [service]   build ulang image tanpa cache lalu jalankan ulang
  logs [service] [N]  N baris log terakhir (default semua service, 50 baris)
  follow [service]    ikuti log secara live (Ctrl+C untuk keluar)
  shell <service>     masuk ke shell di dalam container
  psql                masuk ke psql di container db
  health              cek /api/health lewat Nginx
  images              daftar image & volume milik project ini
  clean               hapus container berhenti & image dangling (minta konfirmasi)

Contoh:
  ./docker-manage.sh up
  ./docker-manage.sh logs app 100
  ./docker-manage.sh shell app
USAGE
}

setup_docker() {
  require_not_root
  has_cmd docker || die "Docker belum terpasang. Jalankan ./install-docker.sh"
  docker info >/dev/null 2>&1 \
    || die "Tidak bisa mengakses Docker. Login SSH ulang atau jalankan: newgrp docker"
  [[ -f "$DOCKER_DIR/compose.yaml" ]] || die "File tidak ditemukan: $DOCKER_DIR/compose.yaml"
}

need_env() {
  [[ -f "$DOCKER_DIR/.env" ]] \
    || die "docker/.env belum ada. Jalankan: cp ${DOCKER_DIR}/.env.example ${DOCKER_DIR}/.env lalu isi DB_PASSWORD"
}

# Jalankan docker compose dengan file & folder proyek yang benar
dc() { docker compose --project-directory "$DOCKER_DIR" -f "$DOCKER_DIR/compose.yaml" "$@"; }

http_port() {
  local port=80
  if [[ -f "$DOCKER_DIR/.env" ]]; then
    port="$(grep -E '^HTTP_PORT=' "$DOCKER_DIR/.env" | tail -n1 | cut -d= -f2 | tr -d '"' || true)"
  fi
  printf '%s' "${port:-80}"
}
health_url() { printf 'http://127.0.0.1:%s/api/health' "$(http_port)"; }

cmd_status() {
  local ids
  log_step "Container"
  dc ps
  ids="$(dc ps -q)"
  if [[ -n "$ids" ]]; then
    log_step "Resource"
    # shellcheck disable=SC2086
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $ids
  fi
  log_step "Health"
  cmd_health || true
}

cmd_up() {
  need_env
  dc up -d --build
  log_info "Menunggu aplikasi sehat..."
  if wait_until 60 app_healthy "$(health_url)"; then
    log_ok "Stack berjalan: $(health_url)"
  else
    log_warn "Belum sehat setelah 60 detik. Cek: ./docker-manage.sh logs"
  fi
  dc ps
}

cmd_down() { dc down; log_ok "Container dihapus. Volume database tetap ada."; }

cmd_reset() {
  confirm "Hapus container DAN volume database? Semua data hilang." || die "Dibatalkan."
  dc down --volumes
  log_ok "Container & volume dihapus."
}

cmd_restart() { dc restart "$@"; }

cmd_rebuild() {
  need_env
  dc build --no-cache "$@"
  dc up -d "$@"
}

cmd_logs() {
  local service="${1:-}" n="${2:-50}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "Jumlah baris harus angka."
  if [[ -n "$service" ]]; then dc logs --tail "$n" --no-color "$service"; else dc logs --tail "$n" --no-color; fi
}

cmd_follow() {
  local service="${1:-}"
  if [[ -n "$service" ]]; then dc logs -f --tail 20 "$service"; else dc logs -f --tail 20; fi
}

cmd_shell() {
  [[ $# -ge 1 ]] || die "Sebutkan service: db | app | nginx"
  dc exec "$1" sh
}

cmd_psql() { dc exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'; }

cmd_health() {
  local url body
  url="$(health_url)"
  body="$(curl -fsS --max-time 5 "$url" 2>/dev/null)" || { log_err "Tidak sehat / tidak merespons: $url"; return 1; }
  printf '%s\n' "$body"
  if [[ "$body" == *'"status":"ok"'* ]]; then log_ok "Sehat: $url"; else log_err "Respons tidak sehat"; return 1; fi
  if [[ "$body" == *'"via_nginx":true'* ]]; then log_ok "Request melewati Nginx (container)"; fi
}

cmd_images() {
  log_step "Image project"
  docker image ls --filter "reference=praktikum-app" --filter "reference=postgres" --filter "reference=nginx"
  log_step "Volume project"
  docker volume ls --filter "label=com.docker.compose.project=praktikum"
}

cmd_clean() {
  confirm "Hapus container yang berhenti dan image dangling?" || die "Dibatalkan."
  docker system prune -f
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    ""|-h|--help|help) usage; return 0 ;;
  esac
  setup_docker
  case "$cmd" in
    status)  cmd_status ;;
    up)      cmd_up ;;
    down)    cmd_down ;;
    reset)   cmd_reset ;;
    restart) cmd_restart "$@" ;;
    rebuild) cmd_rebuild "$@" ;;
    logs)    cmd_logs "$@" ;;
    follow)  cmd_follow "$@" ;;
    shell)   cmd_shell "$@" ;;
    psql)    cmd_psql ;;
    health)  cmd_health ;;
    images)  cmd_images ;;
    clean)   cmd_clean ;;
    *) usage; die "Perintah tidak dikenal: ${cmd}" ;;
  esac
}

main "$@"
