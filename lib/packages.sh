#!/usr/bin/env bash

APT_PACKAGES=(
  ca-certificates
  curl
  dnsutils
  git
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

readonly DOCKER_DAEMON_DIR="/etc/docker"
readonly DOCKER_DAEMON_CONFIG="${DOCKER_DAEMON_DIR}/daemon.json"

apt_package_has_candidate() {
  local package="$1"
  local candidate=""
  candidate="$(apt-cache policy "${package}" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

ensure_optional_docker_cli_installed() {
  if [[ "${ENABLE_DOCKER_TESTS:-no}" != "yes" ]]; then
    return 0
  fi
  if docker_cli_path >/dev/null 2>&1; then
    return 0
  fi

  if apt_package_has_candidate docker-cli; then
    info "Docker daemon is present without a docker CLI; installing docker-cli."
    apt-get install -y --no-install-recommends docker-cli
  elif dpkg-query -W -f='${Status}' docker.io 2>/dev/null | grep -Fq 'ok installed'; then
    warn "docker.io is installed but docker CLI is still missing; attempting a docker.io reinstall."
    apt-get install -y --no-install-recommends --reinstall docker.io
  fi

  docker_cli_path >/dev/null 2>&1 || die "Docker CLI is missing after package installation. Install a package that provides /usr/bin/docker (for Debian 13 this is docker-cli)."
}

bootstrap_python3_if_missing() {
  if command_exists python3; then
    return 0
  fi
  info "python3 not found; installing a bootstrap python3 package before configuration parsing."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends python3
}

install_base_packages() {
  info "Installing required Debian packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  local packages=("${APT_PACKAGES[@]}")
  if [[ "${ENABLE_DOCKER_TESTS:-no}" == "yes" ]] && ! command_exists dockerd; then
    packages+=(docker.io)
  fi
  if [[ "${ENABLE_DOCKER_TESTS:-no}" == "yes" ]] && ! docker_cli_path >/dev/null 2>&1 && apt_package_has_candidate docker-cli; then
    packages+=(docker-cli)
  fi
  apt-get install -y --no-install-recommends "${packages[@]}"
  ensure_optional_docker_cli_installed
  systemctl enable vnstat >/dev/null 2>&1 || true
  systemctl start vnstat >/dev/null 2>&1 || true
}

install_runtime_assets() {
  info "Installing neflare runtime assets"
  mkdir_system_dir "${NEFLARE_INSTALL_ROOT}" 0755
  mkdir_system_dir "${NEFLARE_INSTALL_ROOT}/lib" 0755
  mkdir_system_dir "${NEFLARE_BOT_INSTALL_DIR}" 0755

  copy_tree_contents "${NEFLARE_SOURCE_ROOT}/templates" "${NEFLARE_INSTALL_ROOT}/templates"
  copy_tree_contents "${NEFLARE_SOURCE_ROOT}/systemd" "${NEFLARE_INSTALL_ROOT}/systemd"

  local file
  while IFS= read -r -d '' file; do
    install -m 0644 -o root -g root "${file}" "${NEFLARE_INSTALL_ROOT}/lib/$(basename "${file}")"
  done < <(find "${NEFLARE_SOURCE_ROOT}/lib" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) ! -name 'neflarectl.sh' -print0)

  install -m 0755 -o root -g root "${NEFLARE_SOURCE_ROOT}/lib/neflarectl.sh" "${NEFLARE_RUNTIME_BIN_DIR}/neflarectl"

  while IFS= read -r -d '' file; do
    local rel="${file#"${NEFLARE_SOURCE_ROOT}/bot/"}"
    [[ "${rel}" == __pycache__/* ]] && continue
    [[ "${rel}" == *.pyc ]] && continue
    mkdir_system_dir "${NEFLARE_BOT_INSTALL_DIR}/$(dirname "${rel}")" 0755
    install -m 0644 -o root -g root "${file}" "${NEFLARE_BOT_INSTALL_DIR}/${rel}"
  done < <(find "${NEFLARE_SOURCE_ROOT}/bot" -type f -print0)
}

render_docker_daemon_config() {
  local destination="$1"
  python3 - "${DOCKER_DAEMON_CONFIG}" > "${destination}" <<'PY'
import json
import os
import sys

path = sys.argv[1]
payload = {}
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
if not isinstance(payload, dict):
    raise SystemExit("Docker daemon.json must contain a JSON object")
payload["bridge"] = "none"
payload["iptables"] = False
payload["ip6tables"] = False
json.dump(payload, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
PY
}

configure_optional_docker_tests_runtime() {
  if [[ "${ENABLE_DOCKER_TESTS:-no}" != "yes" ]]; then
    info "Disposable Docker-backed network tests are disabled; leaving any existing Docker runtime untouched."
    return 0
  fi

  info "Configuring Docker for disposable network tests"
  mkdir_system_dir "${DOCKER_DAEMON_DIR}" 0755
  snapshot_file_once "${DOCKER_DAEMON_CONFIG}"
  systemctl stop docker >/dev/null 2>&1 || true
  systemctl stop docker.socket >/dev/null 2>&1 || true
  local rendered
  rendered="$(mktemp)"
  render_docker_daemon_config "${rendered}"
  install_file_atomic "${rendered}" "${DOCKER_DAEMON_CONFIG}" 0644 root root
  rm -f "${rendered}"

  systemctl enable docker >/dev/null 2>&1 || true
  systemctl restart docker
  wait_for_docker_daemon 60 || die "Docker was installed/configured for disposable tests, but the daemon did not become reachable within 60 seconds."
}
