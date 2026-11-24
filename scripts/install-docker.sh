#!/usr/bin/env bash
# =====================================================================
#  install-docker.sh
#  Install Docker Engine + Compose plugin dari repository resmi Docker
#  (Ubuntu 22.04 / 24.04 / 26.04). Aman dijalankan berulang.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
  -h|--help) echo "Penggunaan: ./install-docker.sh   (tanpa opsi)"; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root
ensure_sudo

OS_ID="$(. /etc/os-release && echo "$ID")"
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
[[ "$OS_ID" == "ubuntu" ]] || die "Script ini hanya untuk Ubuntu (terdeteksi: ${OS_ID})."

log_step "1/6  Hapus paket Docker tidak resmi (jika ada)"
if dpkg -s docker-ce >/dev/null 2>&1; then
  log_ok "docker-ce sudah terpasang, dilewati."
else
  for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log_info "Menghapus ${pkg}"
      sudo apt-get remove -y "$pkg"
    fi
  done
fi

log_step "2/6  Tambah GPG key Docker"
sudo apt-get update -y
apt_install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

log_step "3/6  Tambah repository Docker (${CODENAME})"
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<SOURCES
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES
sudo apt-get update -y

log_step "4/6  Install Docker Engine & Compose"
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

log_step "5/6  Izinkan user '${CURRENT_USER}' memakai docker tanpa sudo"
if id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx docker; then
  log_ok "User sudah ada di grup docker."
else
  sudo usermod -aG docker "$CURRENT_USER"
  log_ok "User ditambahkan ke grup docker."
  NEED_RELOGIN=true
fi

log_step "6/6  Verifikasi"
sudo docker --version
sudo docker compose version
sudo docker run --rm hello-world >/dev/null && log_ok "hello-world berjalan: Docker berfungsi."

if [[ "${NEED_RELOGIN:-false}" == true ]]; then
  log_warn "Keluar lalu login SSH lagi (atau jalankan: newgrp docker) agar grup docker berlaku."
fi
log_warn "Anggota grup docker setara hak root di server. Jangan beri ke user yang tidak dipercaya."
