#!/usr/bin/env bash

APT_PACKAGES=(
  ca-certificates
  curl
  dnsutils
  iproute2
  jq
  nftables
  openssh-server
  openssl
  python3
  python3-venv
  sudo
  unzip
  vnstat
)

install_base_packages() {
  info "Installing required Debian packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
  systemctl enable vnstat >/dev/null 2>&1 || true
  systemctl start vnstat >/dev/null 2>&1 || true
}

install_runtime_assets() {
  info "Installing neflare runtime assets"
  mkdir_system_dir "${NEFLARE_INSTALL_ROOT}" 0755
  mkdir_system_dir "${NEFLARE_INSTALL_ROOT}/lib" 0755
  mkdir_system_dir "${NEFLARE_BOT_INSTALL_DIR}" 0755

  local file
  while IFS= read -r -d '' file; do
    install -m 0644 -o root -g root "${file}" "${NEFLARE_INSTALL_ROOT}/lib/$(basename "${file}")"
  done < <(find "${NEFLARE_SOURCE_ROOT}/lib" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) ! -name 'neflarectl.sh' -print0)

  install -m 0755 -o root -g root "${NEFLARE_SOURCE_ROOT}/lib/neflarectl.sh" "${NEFLARE_RUNTIME_BIN_DIR}/neflarectl"

  while IFS= read -r -d '' file; do
    local rel="${file#"${NEFLARE_SOURCE_ROOT}/bot/"}"
    mkdir_system_dir "${NEFLARE_BOT_INSTALL_DIR}/$(dirname "${rel}")" 0755
    install -m 0644 -o root -g root "${file}" "${NEFLARE_BOT_INSTALL_DIR}/${rel}"
  done < <(find "${NEFLARE_SOURCE_ROOT}/bot" -type f -print0)
}
