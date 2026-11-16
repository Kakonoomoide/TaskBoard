#!/usr/bin/env bash
# =====================================================================
#  02-setup-node.sh
#  Install NVM lalu Node.js (versi NODE_VERSION) dan jadikan default.
# =====================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
  -h|--help) echo "Penggunaan: ./02-setup-node.sh   (versi Node dari NODE_VERSION di config.env)"; exit 0 ;;
  "") ;;
  *) die "Opsi tidak dikenal: $1" ;;
esac

require_not_root

log_step "1/3  Install NVM ${NVM_VERSION}"
if [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]]; then
  log_ok "NVM sudah terpasang, dilewati."
else
  if ! has_cmd curl; then
    ensure_sudo
    sudo apt-get update -y
    apt_install curl
  fi
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  log_ok "NVM terpasang."
fi

load_nvm || die "Gagal memuat NVM."

log_step "2/3  Install Node.js ${NODE_VERSION}"
nvm_run install "$NODE_VERSION"
nvm_run alias default "$NODE_VERSION" >/dev/null
nvm_run use "$NODE_VERSION" >/dev/null

log_step "3/3  Verifikasi"
log_ok "node $(node -v)"
log_ok "npm  $(npm -v)"
