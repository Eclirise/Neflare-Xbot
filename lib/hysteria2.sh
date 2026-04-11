#!/usr/bin/env bash

readonly HYSTERIA2_BINARY_PATH="/usr/local/bin/hysteria"
readonly HYSTERIA2_CONFIG_PATH="${NEFLARE_CONFIG_DIR}/hysteria2.yaml"
readonly HYSTERIA2_SERVICE_UNIT="/etc/systemd/system/neflare-hysteria2.service"
readonly HYSTERIA2_STATE_DIR="${NEFLARE_STATE_DIR}/hysteria2"

hysteria2_asset_name() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "${arch}" in
    amd64|x86_64) printf 'hysteria-linux-amd64\n' ;;
    arm64|aarch64) printf 'hysteria-linux-arm64\n' ;;
    armhf|armv7l) printf 'hysteria-linux-arm\n' ;;
    386|i386|i686) printf 'hysteria-linux-386\n' ;;
    riscv64) printf 'hysteria-linux-riscv64\n' ;;
    s390x) printf 'hysteria-linux-s390x\n' ;;
    *) die "Unsupported architecture for Hysteria 2 binary download: ${arch}" ;;
  esac
}

hysteria2_download_url() {
  printf 'https://download.hysteria.network/app/%s/%s\n' "${HYSTERIA2_VERSION}" "$(hysteria2_asset_name)"
}

hysteria2_is_installed() {
  [[ -x "${HYSTERIA2_BINARY_PATH}" ]]
}

hysteria2_version_string() {
  if ! hysteria2_is_installed; then
    printf 'not-installed\n'
    return 0
  fi
  "${HYSTERIA2_BINARY_PATH}" version 2>/dev/null | awk -F'\t' '/^Version:/ {print $2; exit}'
}

ensure_hysteria2_installed() {
  enable_hysteria2 || return 0

  if hysteria2_is_installed; then
    info "Hysteria 2 already installed (version $(hysteria2_version_string)); skipping binary download."
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  info "Downloading Hysteria 2 ${HYSTERIA2_VERSION} from $(hysteria2_download_url)"
  curl -fsSL "$(hysteria2_download_url)" -o "${tmp}"
  install -m 0755 -o root -g root "${tmp}" "${HYSTERIA2_BINARY_PATH}"
  rm -f "${tmp}"
  success "Installed Hysteria 2 to ${HYSTERIA2_BINARY_PATH}"
}

yaml_bool() {
  if [[ "$(normalize_yes_no "${1:-no}")" == "yes" ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

ensure_hysteria2_state_dirs() {
  mkdir_root_only "${HYSTERIA2_STATE_DIR}"
  if enable_hysteria2 && [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
    mkdir_root_only "${HYSTERIA2_ACME_DIR}"
  fi
}

render_hysteria2_config_file() {
  local destination="$1"
  local listen_value
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    listen_value=":${HYSTERIA2_LISTEN_PORT}"
  else
    listen_value="0.0.0.0:${HYSTERIA2_LISTEN_PORT}"
  fi

  {
    printf 'listen: %s\n' "$(json_quote "${listen_value}")"
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
      printf 'acme:\n'
      printf '  domains:\n'
      printf '    - %s\n' "$(json_quote "${HYSTERIA2_DOMAIN}")"
      printf '  email: %s\n' "$(json_quote "${HYSTERIA2_ACME_EMAIL}")"
      printf '  dir: %s\n' "$(json_quote "${HYSTERIA2_ACME_DIR}")"
      printf '  type: %s\n' "$(json_quote "${HYSTERIA2_ACME_CHALLENGE_TYPE}")"
      printf '  http:\n'
      printf '    altPort: %s\n' "${HYSTERIA2_ACME_HTTP_PORT}"
    else
      printf 'tls:\n'
      printf '  cert: %s\n' "$(json_quote "${HYSTERIA2_TLS_CERT_FILE}")"
      printf '  key: %s\n' "$(json_quote "${HYSTERIA2_TLS_KEY_FILE}")"
    fi
    printf 'auth:\n'
    printf '  type: password\n'
    printf '  password: %s\n' "$(json_quote "${HYSTERIA2_AUTH_PASSWORD}")"
    if [[ "${HYSTERIA2_MASQUERADE_TYPE}" == "proxy" ]]; then
      printf 'masquerade:\n'
      printf '  type: proxy\n'
      printf '  proxy:\n'
      printf '    url: %s\n' "$(json_quote "${HYSTERIA2_MASQUERADE_URL}")"
      printf '    rewriteHost: %s\n' "$(yaml_bool "${HYSTERIA2_MASQUERADE_REWRITE_HOST}")"
      printf '    insecure: %s\n' "$(yaml_bool "${HYSTERIA2_MASQUERADE_INSECURE}")"
    fi
  } > "${destination}"
}

validate_hysteria2_config_file() {
  local path="$1"
  [[ -s "${path}" ]] || die "Hysteria 2 config file is empty: ${path}"
  if [[ "${HYSTERIA2_TLS_MODE}" == "file" ]]; then
    [[ -r "${HYSTERIA2_TLS_CERT_FILE}" ]] || die "Hysteria 2 certificate file is not readable: ${HYSTERIA2_TLS_CERT_FILE}"
    [[ -r "${HYSTERIA2_TLS_KEY_FILE}" ]] || die "Hysteria 2 key file is not readable: ${HYSTERIA2_TLS_KEY_FILE}"
  fi
  if [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
    [[ "${HYSTERIA2_ACME_DIR}" == /* ]] || die "HYSTERIA2_ACME_DIR must be an absolute path."
  fi
}

install_hysteria2_service_unit() {
  snapshot_file_once "${HYSTERIA2_SERVICE_UNIT}"
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-hysteria2.service" "${HYSTERIA2_SERVICE_UNIT}" 0644 root root
  systemctl daemon-reload
}

restore_hysteria2_runtime() {
  local was_enabled="$1"
  rollback_paths "${HYSTERIA2_CONFIG_PATH}" "${HYSTERIA2_SERVICE_UNIT}"
  systemctl daemon-reload
  if [[ "${was_enabled}" == "yes" ]]; then
    systemctl enable --now neflare-hysteria2 >/dev/null 2>&1 || true
  else
    systemctl disable --now neflare-hysteria2 >/dev/null 2>&1 || true
  fi
}

apply_hysteria2_config() {
  local rendered="$1"
  local was_enabled="no"
  if systemctl is-enabled --quiet neflare-hysteria2 2>/dev/null; then
    was_enabled="yes"
  fi

  snapshot_file_once "${HYSTERIA2_CONFIG_PATH}"
  install_hysteria2_service_unit
  validate_hysteria2_config_file "${rendered}"
  install_file_atomic "${rendered}" "${HYSTERIA2_CONFIG_PATH}" 0600 root root

  systemctl enable neflare-hysteria2 >/dev/null 2>&1 || true
  if ! systemctl restart neflare-hysteria2; then
    warn "Hysteria 2 restart failed; restoring previous configuration"
    restore_hysteria2_runtime "${was_enabled}"
    die "Hysteria 2 restart failed and previous configuration was restored."
  fi
  success "Hysteria 2 configuration applied successfully"
}

disable_hysteria2_runtime() {
  systemctl disable --now neflare-hysteria2 >/dev/null 2>&1 || true
  info "Hysteria 2 is disabled; any existing service instance has been stopped."
}

configure_hysteria2_runtime() {
  if ! enable_hysteria2; then
    disable_hysteria2_runtime
    return 0
  fi

  ensure_hysteria2_installed
  ensure_hysteria2_state_dirs
  local rendered
  rendered="$(mktemp)"
  render_hysteria2_config_file "${rendered}"
  apply_hysteria2_config "${rendered}"
  rm -f "${rendered}"
}
