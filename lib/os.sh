#!/usr/bin/env bash

detect_supported_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_ID="${ID:-}"
  DISTRO_VERSION_ID="${VERSION_ID:-}"
  DISTRO_CODENAME="${VERSION_CODENAME:-}"
  export DISTRO_ID DISTRO_VERSION_ID DISTRO_CODENAME

  [[ "${DISTRO_ID}" == "debian" ]] || die "Unsupported distribution '${DISTRO_ID}'. Only Debian 12 and Debian 13 are supported."
  case "${DISTRO_VERSION_ID}" in
    12|13) ;;
    *) die "Unsupported Debian version '${DISTRO_VERSION_ID}'. Only Debian 12 and Debian 13 are supported." ;;
  esac
  info "Detected supported OS: Debian ${DISTRO_VERSION_ID} (${DISTRO_CODENAME:-unknown})"
}

