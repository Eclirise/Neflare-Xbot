#!/usr/bin/env bash

set_default_config() {
  NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
  UPGRADE_XRAY="${UPGRADE_XRAY:-0}"
  VERIFY_ONLY="${VERIFY_ONLY:-0}"
  CONFIG_INPUT_FILE="${CONFIG_INPUT_FILE:-}"
  if declare -F lang_normalize >/dev/null 2>&1; then
    UI_LANG="$(lang_normalize "${UI_LANG:-}")"
  else
    UI_LANG="${UI_LANG:-en}"
  fi

  ADMIN_USER="${ADMIN_USER:-}"
  ADMIN_PUBLIC_KEY="${ADMIN_PUBLIC_KEY:-}"
  ADMIN_PUBLIC_KEY_FILE="${ADMIN_PUBLIC_KEY_FILE:-}"
  ADMIN_NOPASSWD_SUDO="${ADMIN_NOPASSWD_SUDO:-yes}"
  SSH_PORT="${SSH_PORT:-}"
  SSH_CUTOVER_CONFIRMED="${SSH_CUTOVER_CONFIRMED:-no}"
  ENABLE_IPV6="$(normalize_yes_no "${ENABLE_IPV6:-yes}")"
  ALLOW_IPV6_DISABLE_FROM_IPV6="$(normalize_yes_no "${ALLOW_IPV6_DISABLE_FROM_IPV6:-no}")"
  ENABLE_BOT="$(normalize_yes_no "${ENABLE_BOT:-yes}")"
  ENABLE_DOCKER_TESTS="$(normalize_yes_no "${ENABLE_DOCKER_TESTS:-yes}")"
  BOT_LOG_RETENTION_DAYS="${BOT_LOG_RETENTION_DAYS:-14}"
  BOT_LOG_MAX_BYTES="${BOT_LOG_MAX_BYTES:-65536}"
  REPO_SYNC_URL="${REPO_SYNC_URL:-https://github.com/Eclirise/Neflare-Xbot.git}"
  REPO_SYNC_BRANCH="${REPO_SYNC_BRANCH:-main}"
  REPO_SYNC_DIR="${REPO_SYNC_DIR:-/opt/Neflare-Xbot}"
  BOT_TOKEN="${BOT_TOKEN:-}"
  CHAT_ID="${CHAT_ID:-}"
  REPORT_TIME="${REPORT_TIME:-08:00}"
  REPORT_TZ="${REPORT_TZ:-Asia/Shanghai}"
  QUOTA_MONTHLY_CAP_GB="${QUOTA_MONTHLY_CAP_GB:-0}"
  QUOTA_RESET_DAY_UTC="${QUOTA_RESET_DAY_UTC:-1}"
  REALITY_CANDIDATES="${REALITY_CANDIDATES:-}"
  REALITY_AUTO_RECOMMEND="$(normalize_yes_no "${REALITY_AUTO_RECOMMEND:-yes}")"
  REALITY_SELECTED_DOMAIN="${REALITY_SELECTED_DOMAIN:-}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
  REALITY_DEST="${REALITY_DEST:-}"
  SERVER_PUBLIC_ENDPOINT="${SERVER_PUBLIC_ENDPOINT:-}"
  NETWORK_INTERFACE="${NETWORK_INTERFACE:-}"
  XRAY_LISTEN_PORT="${XRAY_LISTEN_PORT:-443}"
  ALLOW_NONSTANDARD_REALITY_PORT="$(normalize_yes_no "${ALLOW_NONSTANDARD_REALITY_PORT:-no}")"
  ALLOW_DISCOURAGED_REALITY_TARGET="$(normalize_yes_no "${ALLOW_DISCOURAGED_REALITY_TARGET:-no}")"
  XRAY_UUID="${XRAY_UUID:-}"
  XRAY_PRIVATE_KEY="${XRAY_PRIVATE_KEY:-}"
  XRAY_PUBLIC_KEY="${XRAY_PUBLIC_KEY:-}"
  XRAY_SHORT_IDS="${XRAY_SHORT_IDS:-}"
  TEMP_ADMIN_ALLOW_V4="${TEMP_ADMIN_ALLOW_V4:-}"
  TEMP_ADMIN_ALLOW_V6="${TEMP_ADMIN_ALLOW_V6:-}"
  CREATED_ADMIN_USER="${CREATED_ADMIN_USER:-no}"
}

normalize_reality_candidates() {
  python3 - "${1:-}" <<'PY'
import sys
import urllib.parse

seen = set()
items = []
for raw in sys.argv[1].split(","):
    candidate = raw.strip()
    if not candidate:
        continue
    if "://" in candidate:
        candidate = urllib.parse.urlparse(candidate).hostname or ""
    else:
        candidate = candidate.split("/", 1)[0]
    candidate = candidate.strip().rstrip(".").lower()
    if candidate and candidate not in seen:
        seen.add(candidate)
        items.append(candidate)
print(",".join(items))
PY
}

count_reality_candidates() {
  python3 - "${1:-}" <<'PY'
import sys
items = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
print(len(items))
PY
}

load_user_config_file() {
  local path="$1"
  [[ -n "${path}" ]] || return 0
  [[ -f "${path}" ]] || die "Config file not found: ${path}"
  info "Loading installer configuration from ${path}"
  source_env_file "${path}"
}

load_installed_config_if_present() {
  if [[ -f "${NEFLARE_CONFIG_FILE}" ]]; then
    info "Loading existing installed configuration from ${NEFLARE_CONFIG_FILE}"
    source_env_file "${NEFLARE_CONFIG_FILE}"
  fi
}

detect_default_timezone() {
  local tz=""
  if command_exists timedatectl; then
    tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  fi
  if [[ -z "${tz}" && -f /etc/timezone ]]; then
    tz="$(trim "$(cat /etc/timezone)")"
  fi
  printf '%s\n' "${tz:-UTC}"
}

validate_timezone() {
  local zone="$1"
  python3 - "${zone}" <<'PY'
import sys
from zoneinfo import ZoneInfo
ZoneInfo(sys.argv[1])
PY
}

guess_default_admin_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi
  if [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
    printf '%s\n' "${USER}"
    return 0
  fi
  printf 'admin\n'
}

guess_public_key_from_system() {
  local candidate=""
  if [[ -n "${ADMIN_PUBLIC_KEY_FILE:-}" && -f "${ADMIN_PUBLIC_KEY_FILE}" ]]; then
    candidate="$(head -n 1 "${ADMIN_PUBLIC_KEY_FILE}")"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" && -f "/home/${SUDO_USER}/.ssh/authorized_keys" ]]; then
    candidate="$(head -n 1 "/home/${SUDO_USER}/.ssh/authorized_keys")"
  elif [[ -f /root/.ssh/authorized_keys ]]; then
    candidate="$(head -n 1 /root/.ssh/authorized_keys)"
  fi
  printf '%s\n' "${candidate}"
}

validate_ssh_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1024 && port <= 65535 )) || return 1
  (( port != 443 )) || return 1
}

validate_tcp_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 )) || return 1
}

validate_public_key() {
  local key="$1"
  [[ -n "${key}" ]] || return 1
  ssh-keygen -l -f <(printf '%s\n' "${key}") >/dev/null 2>&1
}

prompt_install_config() {
  local default_admin default_tz key_default ssh_default reality_prompt report_time_default xray_port_default
  default_admin="$(guess_default_admin_user)"
  default_tz="$(detect_default_timezone)"
  key_default="$(guess_public_key_from_system)"
  report_time_default="${REPORT_TIME:-08:00}"

  ADMIN_USER="$(read_prompt "$(i18n_text prompt_admin_user)" "${ADMIN_USER:-${default_admin}}" yes)"
  if [[ -z "${ADMIN_PUBLIC_KEY}" ]]; then
    ADMIN_PUBLIC_KEY="$(read_prompt "$(i18n_text prompt_admin_key)" "${key_default}" yes)"
  fi

  if [[ -z "${SSH_PORT}" ]]; then
    ssh_default="$(generate_random_high_port)"
  else
    ssh_default="${SSH_PORT}"
  fi
  SSH_PORT="$(read_prompt "$(i18n_text prompt_ssh_port)" "${ssh_default}" yes)"
  ENABLE_IPV6="$(normalize_yes_no "$(read_prompt "$(i18n_text prompt_enable_ipv6)" "${ENABLE_IPV6:-yes}" yes)")"
  xray_port_default="${XRAY_LISTEN_PORT:-443}"
  XRAY_LISTEN_PORT="$(read_prompt "$(i18n_text prompt_xray_port)" "${xray_port_default}" yes)"
  if [[ "${XRAY_LISTEN_PORT}" != "443" ]]; then
    warn "$(i18n_text warn_non443)"
    confirm_or_die "$(i18n_text confirm_non443 "${XRAY_LISTEN_PORT}")"
    ALLOW_NONSTANDARD_REALITY_PORT="yes"
  fi

  reality_prompt="$(i18n_text prompt_reality_candidates)"
  REALITY_CANDIDATES="$(read_prompt "${reality_prompt}" "${REALITY_CANDIDATES}" yes)"
  REALITY_AUTO_RECOMMEND="$(normalize_yes_no "$(read_prompt "$(i18n_text prompt_auto_select)" "${REALITY_AUTO_RECOMMEND:-yes}" yes)")"

  ENABLE_DOCKER_TESTS="$(normalize_yes_no "$(read_prompt "$(i18n_text prompt_enable_docker_tests)" "${ENABLE_DOCKER_TESTS:-yes}" yes)")"
  ENABLE_BOT="$(normalize_yes_no "$(read_prompt "$(i18n_text prompt_enable_bot)" "${ENABLE_BOT:-yes}" yes)")"
  if [[ "${ENABLE_BOT}" == "yes" ]]; then
    BOT_TOKEN="$(read_prompt "$(i18n_text prompt_bot_token)" "${BOT_TOKEN}" no yes)"
    CHAT_ID="$(read_prompt "$(i18n_text prompt_chat_id)" "${CHAT_ID}" no)"
    REPORT_TIME="$(read_prompt "$(i18n_text prompt_report_time)" "${report_time_default}" yes)"
    REPORT_TZ="$(read_prompt "$(i18n_text prompt_report_tz)" "${REPORT_TZ:-${default_tz}}" yes)"
    QUOTA_MONTHLY_CAP_GB="$(read_prompt "$(i18n_text prompt_quota_cap)" "${QUOTA_MONTHLY_CAP_GB}" yes)"
    QUOTA_RESET_DAY_UTC="$(read_prompt "$(i18n_text prompt_quota_reset)" "${QUOTA_RESET_DAY_UTC}" yes)"
  else
    REPORT_TZ="${REPORT_TZ:-${default_tz}}"
  fi

  SERVER_PUBLIC_ENDPOINT="$(read_prompt "$(i18n_text prompt_server_endpoint)" "${SERVER_PUBLIC_ENDPOINT}" no)"
}

validate_runtime_config() {
  validate_ssh_port "${SSH_PORT}" || die "Invalid SSH port '${SSH_PORT}'. Use 1024-65535 and not 443."
  validate_tcp_port "${XRAY_LISTEN_PORT}" || die "Invalid XRAY_LISTEN_PORT '${XRAY_LISTEN_PORT}'. Use 1-65535."
  [[ "${XRAY_LISTEN_PORT}" != "${SSH_PORT}" ]] || die "XRAY_LISTEN_PORT must not equal SSH_PORT."
  validate_public_key "${ADMIN_PUBLIC_KEY}" || die "Invalid SSH public key provided for admin user."
  [[ "${ENABLE_IPV6}" == "yes" || "${ENABLE_IPV6}" == "no" ]] || die "ENABLE_IPV6 must be yes or no."
  [[ "${ENABLE_BOT}" == "yes" || "${ENABLE_BOT}" == "no" ]] || die "ENABLE_BOT must be yes or no."
  [[ "${ENABLE_DOCKER_TESTS}" == "yes" || "${ENABLE_DOCKER_TESTS}" == "no" ]] || die "ENABLE_DOCKER_TESTS must be yes or no."
  [[ "${BOT_LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || die "BOT_LOG_RETENTION_DAYS must be a non-negative integer."
  [[ "${BOT_LOG_MAX_BYTES}" =~ ^[0-9]+$ ]] || die "BOT_LOG_MAX_BYTES must be a non-negative integer."
  [[ -n "${REPO_SYNC_URL}" ]] || die "REPO_SYNC_URL must not be empty."
  [[ -n "${REPO_SYNC_BRANCH}" ]] || die "REPO_SYNC_BRANCH must not be empty."
  [[ "${REPO_SYNC_DIR}" == /* ]] || die "REPO_SYNC_DIR must be an absolute path."
  [[ "${REPO_SYNC_DIR}" != "/" ]] || die "REPO_SYNC_DIR must not be /."
  UI_LANG="$(lang_normalize "${UI_LANG:-}")"
  UI_LANG="${UI_LANG:-en}"
  if [[ -n "${REPORT_TZ}" ]]; then
    validate_timezone "${REPORT_TZ}" || die "Invalid timezone '${REPORT_TZ}'."
  fi
  [[ "${REPORT_TIME}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || REPORT_TIME="08:00"
  [[ "${QUOTA_MONTHLY_CAP_GB}" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "QUOTA_MONTHLY_CAP_GB must be numeric."
  [[ "${QUOTA_RESET_DAY_UTC}" =~ ^[0-9]+$ ]] || die "QUOTA_RESET_DAY_UTC must be an integer."
  (( QUOTA_RESET_DAY_UTC >= 1 && QUOTA_RESET_DAY_UTC <= 28 )) || die "QUOTA_RESET_DAY_UTC must be between 1 and 28."
  REALITY_CANDIDATES="$(normalize_reality_candidates "${REALITY_CANDIDATES}")"
  [[ -n "${REALITY_CANDIDATES}" ]] || die "$(i18n_text error_reality_candidates_required)"
  if [[ "$(count_reality_candidates "${REALITY_CANDIDATES}")" -lt 2 ]]; then
    die "$(i18n_text error_reality_candidates_count)"
  fi
  if [[ -n "${REALITY_SELECTED_DOMAIN}" ]]; then
    REALITY_SELECTED_DOMAIN="$(normalize_reality_candidates "${REALITY_SELECTED_DOMAIN}")"
  fi
  if [[ "${XRAY_LISTEN_PORT}" != "443" && "${ALLOW_NONSTANDARD_REALITY_PORT}" != "yes" ]]; then
    die "XRAY_LISTEN_PORT=${XRAY_LISTEN_PORT} is non-default. Set ALLOW_NONSTANDARD_REALITY_PORT=yes to confirm this higher-risk choice."
  fi
}

resolve_network_defaults() {
  NETWORK_INTERFACE="${NETWORK_INTERFACE:-$(detect_primary_interface)}"
  [[ -n "${NETWORK_INTERFACE}" ]] || die "Unable to determine the primary network interface."
  if [[ -z "${SERVER_PUBLIC_ENDPOINT}" ]]; then
    SERVER_PUBLIC_ENDPOINT="$(detect_route_source_ip 4)"
  fi
  REPORT_TZ="${REPORT_TZ:-$(detect_default_timezone)}"
}

save_installed_config() {
  mkdir_root_only "${NEFLARE_CONFIG_DIR}"
  write_env_file "${NEFLARE_CONFIG_FILE}" \
    "CONFIG_VERSION=1" \
    "UI_LANG=${UI_LANG}" \
    "ADMIN_USER=${ADMIN_USER}" \
    "ADMIN_PUBLIC_KEY=${ADMIN_PUBLIC_KEY}" \
    "ADMIN_NOPASSWD_SUDO=${ADMIN_NOPASSWD_SUDO}" \
    "SSH_PORT=${SSH_PORT}" \
    "SSH_CUTOVER_CONFIRMED=${SSH_CUTOVER_CONFIRMED}" \
    "ENABLE_IPV6=${ENABLE_IPV6}" \
    "ALLOW_IPV6_DISABLE_FROM_IPV6=${ALLOW_IPV6_DISABLE_FROM_IPV6}" \
    "ENABLE_BOT=${ENABLE_BOT}" \
    "ENABLE_DOCKER_TESTS=${ENABLE_DOCKER_TESTS}" \
    "BOT_LOG_RETENTION_DAYS=${BOT_LOG_RETENTION_DAYS}" \
    "BOT_LOG_MAX_BYTES=${BOT_LOG_MAX_BYTES}" \
    "REPO_SYNC_URL=${REPO_SYNC_URL}" \
    "REPO_SYNC_BRANCH=${REPO_SYNC_BRANCH}" \
    "REPO_SYNC_DIR=${REPO_SYNC_DIR}" \
    "BOT_TOKEN=${BOT_TOKEN}" \
    "CHAT_ID=${CHAT_ID}" \
    "REPORT_TIME=${REPORT_TIME}" \
    "REPORT_TZ=${REPORT_TZ}" \
    "QUOTA_MONTHLY_CAP_GB=${QUOTA_MONTHLY_CAP_GB}" \
    "QUOTA_RESET_DAY_UTC=${QUOTA_RESET_DAY_UTC}" \
    "REALITY_CANDIDATES=${REALITY_CANDIDATES}" \
    "REALITY_AUTO_RECOMMEND=${REALITY_AUTO_RECOMMEND}" \
    "REALITY_SELECTED_DOMAIN=${REALITY_SELECTED_DOMAIN}" \
    "REALITY_SERVER_NAME=${REALITY_SERVER_NAME}" \
    "REALITY_DEST=${REALITY_DEST}" \
    "SERVER_PUBLIC_ENDPOINT=${SERVER_PUBLIC_ENDPOINT}" \
    "NETWORK_INTERFACE=${NETWORK_INTERFACE}" \
    "XRAY_LISTEN_PORT=${XRAY_LISTEN_PORT}" \
    "ALLOW_NONSTANDARD_REALITY_PORT=${ALLOW_NONSTANDARD_REALITY_PORT}" \
    "ALLOW_DISCOURAGED_REALITY_TARGET=${ALLOW_DISCOURAGED_REALITY_TARGET}" \
    "XRAY_UUID=${XRAY_UUID}" \
    "XRAY_PRIVATE_KEY=${XRAY_PRIVATE_KEY}" \
    "XRAY_PUBLIC_KEY=${XRAY_PUBLIC_KEY}" \
    "XRAY_SHORT_IDS=${XRAY_SHORT_IDS}" \
    "TEMP_ADMIN_ALLOW_V4=${TEMP_ADMIN_ALLOW_V4}" \
    "TEMP_ADMIN_ALLOW_V6=${TEMP_ADMIN_ALLOW_V6}" \
    "CREATED_ADMIN_USER=${CREATED_ADMIN_USER}"
  success "Saved configuration to ${NEFLARE_CONFIG_FILE}"
}

collect_install_config() {
  set_default_config
  load_installed_config_if_present
  load_user_config_file "${CONFIG_INPUT_FILE}"
  if [[ -n "${UI_LANG_RUNTIME_OVERRIDE:-}" ]]; then
    UI_LANG="$(lang_normalize "${UI_LANG_RUNTIME_OVERRIDE}")"
  fi
  if ! bool_is_true "${NON_INTERACTIVE}"; then
    prompt_install_config
  fi
  if [[ -z "${SSH_PORT}" ]]; then
    SSH_PORT="$(generate_random_high_port)"
  fi
  if [[ -z "${ADMIN_USER}" ]]; then
    ADMIN_USER="$(guess_default_admin_user)"
  fi
  if [[ -z "${ADMIN_PUBLIC_KEY}" ]]; then
    ADMIN_PUBLIC_KEY="$(guess_public_key_from_system)"
  fi
  resolve_network_defaults
  validate_runtime_config
  save_installed_config
}
