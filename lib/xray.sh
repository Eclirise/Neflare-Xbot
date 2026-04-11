#!/usr/bin/env bash

readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly XRAY_OVERRIDE_DIR="/etc/systemd/system/xray.service.d"
readonly XRAY_OVERRIDE_PATH="${XRAY_OVERRIDE_DIR}/10-neflare-hardening.conf"
XRAY_BINARY_ROLLBACK_COPY="${XRAY_BINARY_ROLLBACK_COPY:-}"
XRAY_BINARY_TARGET_PATH="${XRAY_BINARY_TARGET_PATH:-}"

xray_install_script_url() {
  printf '%s\n' "${XRAY_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh}"
}

xray_install_script_sha256() {
  printf '%s\n' "${XRAY_INSTALL_SCRIPT_SHA256:-7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555}"
}

xray_install_verify_sha256() {
  normalize_yes_no "${XRAY_INSTALL_VERIFY_SHA256:-no}"
}

xray_binary_path() {
  command -v xray 2>/dev/null || true
}

xray_is_installed() {
  [[ -n "$(xray_binary_path)" ]]
}

xray_version_string() {
  if ! xray_is_installed; then
    printf 'not-installed\n'
    return 0
  fi
  xray version 2>/dev/null | head -n 1 | awk '{print $2}'
}

parse_xray_x25519_output() {
  python3 - "${1:-}" <<'PY'
import re
import sys

text = sys.argv[1]

def capture(label: str) -> str:
    pattern = rf"{label}\s*key\s*:?\s*([A-Za-z0-9_-]+)"
    match = re.search(pattern, text, flags=re.IGNORECASE)
    return match.group(1) if match else ""

private_key = capture("private")
public_key = capture("public")

if not private_key or not public_key:
    tokens = []
    for token in re.findall(r"[A-Za-z0-9_-]{20,}", text):
        if token not in tokens:
            tokens.append(token)
    if not private_key and len(tokens) >= 1:
        private_key = tokens[0]
    if not public_key and len(tokens) >= 2:
        public_key = tokens[1]

if not private_key or not public_key:
    raise SystemExit(1)

print(private_key)
print(public_key)
PY
}

download_xray_install_script() {
  local destination="$1"
  local script_url expected_sha actual_sha verify_mode
  script_url="$(xray_install_script_url)"
  verify_mode="$(xray_install_verify_sha256)"
  curl -fsSL "${script_url}" -o "${destination}"
  if [[ "${verify_mode}" == "yes" ]]; then
    expected_sha="$(xray_install_script_sha256)"
    actual_sha="$(sha256sum "${destination}" | awk '{print $1}')"
    [[ "${actual_sha}" == "${expected_sha}" ]] || die "Unexpected Xray install script checksum for ${script_url}."
  else
    warn "Skipping Xray install script SHA-256 verification for ${script_url} because XRAY_INSTALL_VERIFY_SHA256=no."
  fi
  chmod 0700 "${destination}"
}

install_xray_service_override() {
  snapshot_file_once "${XRAY_OVERRIDE_PATH}"
  mkdir_system_dir "${XRAY_OVERRIDE_DIR}" 0755
  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/xray.service.override.conf.tpl" "${XRAY_OVERRIDE_PATH}"
  systemctl daemon-reload
}

run_official_xray_install() {
  local script
  script="$(mktemp)"
  download_xray_install_script "${script}"
  info "Running official Xray install flow from $(xray_install_script_url)"
  bash "${script}" install -u root
  rm -f "${script}"
}

ensure_xray_installed() {
  local previous_version previous_binary
  previous_version="$(xray_version_string)"
  previous_binary="$(xray_binary_path)"
  XRAY_BINARY_TARGET_PATH="${previous_binary}"

  if xray_is_installed && ! bool_is_true "${UPGRADE_XRAY:-0}"; then
    info "Xray already installed (version ${previous_version}); skipping core upgrade."
  else
    if [[ -n "${previous_binary}" ]]; then
      snapshot_file_once "${previous_binary}"
      XRAY_BINARY_ROLLBACK_COPY="$(mktemp)"
      cp -a "${previous_binary}" "${XRAY_BINARY_ROLLBACK_COPY}"
    fi
    snapshot_file_once "${XRAY_CONFIG_PATH}"
    if ! run_official_xray_install; then
      if [[ -n "${XRAY_BINARY_ROLLBACK_COPY}" && -f "${XRAY_BINARY_ROLLBACK_COPY}" && -n "${XRAY_BINARY_TARGET_PATH}" ]]; then
        cp -a "${XRAY_BINARY_ROLLBACK_COPY}" "${XRAY_BINARY_TARGET_PATH}"
      fi
      die "Official Xray install flow failed."
    fi
  fi

  install_xray_service_override
  systemctl enable xray >/dev/null 2>&1 || true
}

ensure_xray_installed_if_needed() {
  if xray_features_enabled; then
    ensure_xray_installed
  else
    info "Xray-backed protocols are disabled; skipping Xray installation flow."
  fi
}

generate_xray_materials_if_missing() {
  enable_vless_reality || return 0

  if [[ -z "${XRAY_UUID}" ]]; then
    XRAY_UUID="$(xray uuid)"
  fi

  if [[ -z "${XRAY_PRIVATE_KEY}" || -z "${XRAY_PUBLIC_KEY}" ]]; then
    local key_output
    key_output="$(xray x25519 2>&1 || true)"
    local parsed_keys=()
    mapfile -t parsed_keys < <(parse_xray_x25519_output "${key_output}") || die "Failed to parse 'xray x25519' output: ${key_output}"
    XRAY_PRIVATE_KEY="${parsed_keys[0]:-}"
    XRAY_PUBLIC_KEY="${parsed_keys[1]:-}"
  fi

  [[ -n "${XRAY_PRIVATE_KEY}" && -n "${XRAY_PUBLIC_KEY}" ]] || die "Failed to generate REALITY X25519 keypair."

  if [[ -z "${XRAY_SHORT_IDS}" ]]; then
    XRAY_SHORT_IDS="$(printf '%s,%s,%s,%s\n' \
      "$(openssl rand -hex 8)" \
      "$(openssl rand -hex 8)" \
      "$(openssl rand -hex 8)" \
      "$(openssl rand -hex 8)")"
  fi
}

render_xray_inbounds_json() {
  local listen_addr="$1"
  python3 - \
    "${listen_addr}" \
    "${ENABLE_VLESS_REALITY}" \
    "${XRAY_LISTEN_PORT}" \
    "${XRAY_UUID}" \
    "${REALITY_DEST}" \
    "${REALITY_SERVER_NAME}" \
    "${XRAY_PRIVATE_KEY}" \
    "${XRAY_SHORT_IDS}" \
    "${ENABLE_SS2022}" \
    "${SS2022_LISTEN_PORT}" \
    "${SS2022_METHOD}" \
    "${SS2022_PASSWORD}" <<'PY'
import json
import sys

listen_addr = sys.argv[1]
enable_vless = sys.argv[2] == "yes"
xray_port = sys.argv[3]
xray_uuid = sys.argv[4]
reality_dest = sys.argv[5]
reality_server_name = sys.argv[6]
xray_private_key = sys.argv[7]
xray_short_ids = [item.strip() for item in sys.argv[8].split(",") if item.strip()]
enable_ss2022 = sys.argv[9] == "yes"
ss_port = sys.argv[10]
ss_method = sys.argv[11]
ss_password = sys.argv[12]

inbounds = []
if enable_vless:
    inbounds.append(
        {
            "listen": listen_addr,
            "port": int(xray_port),
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": xray_uuid,
                        "flow": "xtls-rprx-vision",
                        "email": "default@neflare",
                    }
                ],
                "decryption": "none",
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": False,
                    "dest": reality_dest,
                    "xver": 0,
                    "serverNames": [item.strip() for item in reality_server_name.split(",") if item.strip()],
                    "privateKey": xray_private_key,
                    "shortIds": xray_short_ids,
                },
                "rawSettings": {
                    "acceptProxyProtocol": False,
                    "header": {
                        "type": "none",
                    },
                },
            },
            "sniffing": {
                "enabled": False,
            },
        }
    )

if enable_ss2022:
    inbounds.append(
        {
            "listen": listen_addr,
            "port": int(ss_port),
            "protocol": "shadowsocks",
            "settings": {
                "method": ss_method,
                "password": ss_password,
                "network": "tcp,udp",
            },
            "sniffing": {
                "enabled": False,
            },
        }
    )

print(json.dumps(inbounds, indent=2))
PY
}

render_xray_config_file() {
  local destination="$1"
  local listen_addr inbounds_json
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    listen_addr="::"
  else
    listen_addr="0.0.0.0"
  fi
  inbounds_json="$(render_xray_inbounds_json "${listen_addr}")"
  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/xray-config.json.tpl" "${destination}" \
    "XRAY_INBOUNDS_JSON=${inbounds_json}"
}

validate_xray_config_file() {
  local path="$1"
  xray run -test -c "${path}"
}

restart_xray_with_rollback() {
  local previous_config="$1"
  if systemctl restart xray; then
    return 0
  fi
  warn "Xray restart failed; restoring previous configuration"
  if [[ -s "${previous_config}" ]]; then
    cp -a "${previous_config}" "${XRAY_CONFIG_PATH}"
  else
    rm -f "${XRAY_CONFIG_PATH}"
  fi
  if [[ -n "${XRAY_BINARY_ROLLBACK_COPY}" && -f "${XRAY_BINARY_ROLLBACK_COPY}" && -n "${XRAY_BINARY_TARGET_PATH}" ]]; then
    cp -a "${XRAY_BINARY_ROLLBACK_COPY}" "${XRAY_BINARY_TARGET_PATH}"
  fi
  systemctl restart xray || true
  die "Xray restart failed and previous configuration was restored."
}

apply_xray_config() {
  local rendered="$1"
  snapshot_file_once "${XRAY_CONFIG_PATH}"
  local previous
  previous="$(mktemp)"
  if [[ -f "${XRAY_CONFIG_PATH}" ]]; then
    cp -a "${XRAY_CONFIG_PATH}" "${previous}"
  else
    : > "${previous}"
  fi

  install_file_atomic "${rendered}" "${XRAY_CONFIG_PATH}" 0600 root root
  if ! validate_xray_config_file "${XRAY_CONFIG_PATH}"; then
    warn "Xray config validation failed; restoring previous configuration"
    if [[ -s "${previous}" ]]; then
      cp -a "${previous}" "${XRAY_CONFIG_PATH}"
    else
      rm -f "${XRAY_CONFIG_PATH}"
    fi
    if [[ -n "${XRAY_BINARY_ROLLBACK_COPY}" && -f "${XRAY_BINARY_ROLLBACK_COPY}" && -n "${XRAY_BINARY_TARGET_PATH}" ]]; then
      cp -a "${XRAY_BINARY_ROLLBACK_COPY}" "${XRAY_BINARY_TARGET_PATH}"
    fi
    rm -f "${previous}"
    die "Xray configuration validation failed."
  fi
  restart_xray_with_rollback "${previous}"
  rm -f "${previous}"
  success "Xray configuration applied successfully"
}

disable_xray_runtime() {
  systemctl disable --now xray >/dev/null 2>&1 || true
  info "No Xray-backed protocols are enabled; xray service is left installed but disabled."
}

configure_xray_runtime() {
  if ! xray_features_enabled; then
    disable_xray_runtime
    return 0
  fi
  generate_xray_materials_if_missing
  local rendered
  rendered="$(mktemp)"
  render_xray_config_file "${rendered}"
  apply_xray_config "${rendered}"
  rm -f "${rendered}"
}

first_short_id() {
  awk -F, '{print $1}' <<<"${XRAY_SHORT_IDS}"
}
