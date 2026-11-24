#!/usr/bin/env bash
# =====================================================================
#  lib/nginx.sh - fungsi pengelolaan konfigurasi Nginx
# =====================================================================
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

nginx_conf_src()  { printf '%s/%s' "$NGINX_DIR" "$NGINX_CONF_FILE"; }
nginx_conf_dst()  { printf '/etc/nginx/sites-available/%s' "$NGINX_SITE"; }
nginx_conf_link() { printf '/etc/nginx/sites-enabled/%s' "$NGINX_SITE"; }

# Salin konfigurasi dari repo ke /etc/nginx, uji, lalu reload.
# Kode keluar:  0 = konfigurasi diperbarui & di-reload
#              10 = tidak ada perubahan
#               1 = gagal (konfigurasi lama dikembalikan)
nginx_sync_conf() {
  local src dst link bak=""
  src="$(nginx_conf_src)"; dst="$(nginx_conf_dst)"; link="$(nginx_conf_link)"

  [[ -f "$src" ]] || { log_err "File konfigurasi tidak ada: $src"; return 1; }

  if [[ -f "$dst" && -L "$link" ]] && cmp -s "$src" "$dst"; then
    return 10
  fi

  if [[ -f "$dst" ]]; then
    bak="$(mktemp)"
    sudo cp -p "$dst" "$bak"
  fi

  sudo cp "$src" "$dst"
  sudo ln -sfn "$dst" "$link"
  sudo rm -f /etc/nginx/sites-enabled/default

  if sudo nginx -t >/dev/null 2>&1; then
    sudo systemctl reload nginx
    if [[ -n "$bak" ]]; then rm -f "$bak"; fi
    return 0
  fi

  log_err "nginx -t gagal. Mengembalikan konfigurasi sebelumnya..."
  sudo nginx -t || true
  if [[ -n "$bak" ]]; then
    sudo cp -p "$bak" "$dst"
    rm -f "$bak"
  else
    sudo rm -f "$link" "$dst"
  fi
  return 1
}
