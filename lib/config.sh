#!/usr/bin/env bash

set_default_config() {
  NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
  UPGRADE_XRAY="${UPGRADE_XRAY:-0}"
  VERIFY_ONLY="${VERIFY_ONLY:-0}"
  CONFIG_INPUT_FILE="${CONFIG_INPUT_FILE:-}"
  CONFIG_VERSION="${CONFIG_VERSION:-0}"
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
  ENABLE_DOCKER_TESTS="$(normalize_yes_no "${ENABLE_DOCKER_TESTS:-yes}")"
  ENABLE_TIME_SYNC="$(normalize_yes_no "${ENABLE_TIME_SYNC:-yes}")"
  ENABLE_BOT="$(normalize_yes_no "${ENABLE_BOT:-yes}")"
  BOT_LOG_RETENTION_DAYS="${BOT_LOG_RETENTION_DAYS:-14}"
  BOT_LOG_MAX_BYTES="${BOT_LOG_MAX_BYTES:-65536}"
  REPO_SYNC_URL="${REPO_SYNC_URL:-https://github.com/Eclirise/Neflare-Xbot.git}"
  REPO_SYNC_BRANCH="${REPO_SYNC_BRANCH:-main}"
  REPO_SYNC_DIR="${REPO_SYNC_DIR:-/opt/Neflare-Xbot}"
  XRAY_INSTALL_SCRIPT_URL="${XRAY_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh}"
  XRAY_INSTALL_SCRIPT_SHA256="${XRAY_INSTALL_SCRIPT_SHA256:-7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555}"
  XRAY_INSTALL_VERIFY_SHA256="$(normalize_yes_no "${XRAY_INSTALL_VERIFY_SHA256:-no}")"

  ENABLE_VLESS_REALITY="$(normalize_yes_no "${ENABLE_VLESS_REALITY:-yes}")"
  ENABLE_HYSTERIA2="$(normalize_yes_no "${ENABLE_HYSTERIA2:-no}")"
  ENABLE_SS2022="$(normalize_yes_no "${ENABLE_SS2022:-no}")"

  BOT_TOKEN="${BOT_TOKEN:-}"
  CHAT_ID="${CHAT_ID:-}"
  BOT_BIND_TOKEN="${BOT_BIND_TOKEN:-}"
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

  HYSTERIA2_VERSION="${HYSTERIA2_VERSION:-v2.8.1}"
  HYSTERIA2_DOMAIN="${HYSTERIA2_DOMAIN:-}"
  HYSTERIA2_LISTEN_PORT="${HYSTERIA2_LISTEN_PORT:-443}"
  HYSTERIA2_TLS_MODE="${HYSTERIA2_TLS_MODE:-acme}"
  HYSTERIA2_ACME_EMAIL="${HYSTERIA2_ACME_EMAIL:-}"
  HYSTERIA2_ACME_DIR="${HYSTERIA2_ACME_DIR:-${NEFLARE_STATE_DIR}/hysteria2/acme}"
  HYSTERIA2_ACME_CHALLENGE_TYPE="${HYSTERIA2_ACME_CHALLENGE_TYPE:-http}"
  HYSTERIA2_ACME_HTTP_PORT="${HYSTERIA2_ACME_HTTP_PORT:-80}"
  HYSTERIA2_TLS_CERT_FILE="${HYSTERIA2_TLS_CERT_FILE:-}"
  HYSTERIA2_TLS_KEY_FILE="${HYSTERIA2_TLS_KEY_FILE:-}"
  HYSTERIA2_AUTH_PASSWORD="${HYSTERIA2_AUTH_PASSWORD:-}"
  HYSTERIA2_MASQUERADE_TYPE="${HYSTERIA2_MASQUERADE_TYPE:-proxy}"
  HYSTERIA2_MASQUERADE_URL="${HYSTERIA2_MASQUERADE_URL:-https://news.ycombinator.com/}"
  HYSTERIA2_MASQUERADE_REWRITE_HOST="$(normalize_yes_no "${HYSTERIA2_MASQUERADE_REWRITE_HOST:-yes}")"
  HYSTERIA2_MASQUERADE_INSECURE="$(normalize_yes_no "${HYSTERIA2_MASQUERADE_INSECURE:-no}")"

  SS2022_LISTEN_PORT="${SS2022_LISTEN_PORT:-40010}"
  SS2022_METHOD="${SS2022_METHOD:-2022-blake3-aes-256-gcm}"
  SS2022_PASSWORD="${SS2022_PASSWORD:-}"

  TEMP_ADMIN_ALLOW_V4="${TEMP_ADMIN_ALLOW_V4:-}"
  TEMP_ADMIN_ALLOW_V6="${TEMP_ADMIN_ALLOW_V6:-}"
  CREATED_ADMIN_USER="${CREATED_ADMIN_USER:-no}"

  VLESS_REALITY_ADVANCED_EDIT="$(normalize_yes_no "${VLESS_REALITY_ADVANCED_EDIT:-no}")"
  VLESS_REALITY_EDIT_TARGET="$(normalize_yes_no "${VLESS_REALITY_EDIT_TARGET:-no}")"
  VLESS_REALITY_EDIT_MATERIALS="$(normalize_yes_no "${VLESS_REALITY_EDIT_MATERIALS:-no}")"
  INSTALLED_CONFIG_PRESENT="${INSTALLED_CONFIG_PRESENT:-no}"
}

enable_vless_reality() {
  [[ "${ENABLE_VLESS_REALITY}" == "yes" ]]
}

enable_hysteria2() {
  [[ "${ENABLE_HYSTERIA2}" == "yes" ]]
}

enable_ss2022() {
  [[ "${ENABLE_SS2022}" == "yes" ]]
}

enable_time_sync() {
  [[ "${ENABLE_TIME_SYNC}" == "yes" ]]
}

xray_features_enabled() {
  enable_vless_reality || enable_ss2022
}

ss2022_network_mode() {
  printf 'tcp,udp\n'
}

vless_reality_config_complete() {
  [[ -n "${XRAY_UUID}" ]] \
    && [[ -n "${XRAY_PRIVATE_KEY}" ]] \
    && [[ -n "${XRAY_PUBLIC_KEY}" ]] \
    && [[ -n "${XRAY_SHORT_IDS}" ]] \
    && [[ -n "${REALITY_SELECTED_DOMAIN}" ]] \
    && [[ -n "${REALITY_SERVER_NAME}" ]] \
    && [[ -n "${REALITY_DEST}" ]] \
    && [[ -n "${XRAY_LISTEN_PORT}" ]]
}

capture_installed_config_snapshot() {
  INSTALLED_CONFIG_PRESENT="no"
  if [[ -f "${NEFLARE_CONFIG_FILE}" ]]; then
    INSTALLED_CONFIG_PRESENT="yes"
  fi

  INSTALLED_ENABLE_VLESS_REALITY="${ENABLE_VLESS_REALITY}"
  INSTALLED_ENABLE_HYSTERIA2="${ENABLE_HYSTERIA2}"
  INSTALLED_ENABLE_SS2022="${ENABLE_SS2022}"
  INSTALLED_ENABLE_TIME_SYNC="${ENABLE_TIME_SYNC}"
  INSTALLED_ENABLE_BOT="${ENABLE_BOT}"

  INSTALLED_XRAY_UUID="${XRAY_UUID}"
  INSTALLED_XRAY_PRIVATE_KEY="${XRAY_PRIVATE_KEY}"
  INSTALLED_XRAY_PUBLIC_KEY="${XRAY_PUBLIC_KEY}"
  INSTALLED_XRAY_SHORT_IDS="${XRAY_SHORT_IDS}"
  INSTALLED_REALITY_CANDIDATES="${REALITY_CANDIDATES}"
  INSTALLED_REALITY_AUTO_RECOMMEND="${REALITY_AUTO_RECOMMEND}"
  INSTALLED_REALITY_SELECTED_DOMAIN="${REALITY_SELECTED_DOMAIN}"
  INSTALLED_REALITY_SERVER_NAME="${REALITY_SERVER_NAME}"
  INSTALLED_REALITY_DEST="${REALITY_DEST}"
  INSTALLED_XRAY_LISTEN_PORT="${XRAY_LISTEN_PORT}"
  INSTALLED_ALLOW_NONSTANDARD_REALITY_PORT="${ALLOW_NONSTANDARD_REALITY_PORT}"
  INSTALLED_ALLOW_DISCOURAGED_REALITY_TARGET="${ALLOW_DISCOURAGED_REALITY_TARGET}"

  INSTALLED_HYSTERIA2_DOMAIN="${HYSTERIA2_DOMAIN}"
  INSTALLED_HYSTERIA2_LISTEN_PORT="${HYSTERIA2_LISTEN_PORT}"
  INSTALLED_HYSTERIA2_TLS_MODE="${HYSTERIA2_TLS_MODE}"
  INSTALLED_HYSTERIA2_ACME_EMAIL="${HYSTERIA2_ACME_EMAIL}"
  INSTALLED_HYSTERIA2_ACME_DIR="${HYSTERIA2_ACME_DIR}"
  INSTALLED_HYSTERIA2_ACME_CHALLENGE_TYPE="${HYSTERIA2_ACME_CHALLENGE_TYPE}"
  INSTALLED_HYSTERIA2_ACME_HTTP_PORT="${HYSTERIA2_ACME_HTTP_PORT}"
  INSTALLED_HYSTERIA2_TLS_CERT_FILE="${HYSTERIA2_TLS_CERT_FILE}"
  INSTALLED_HYSTERIA2_TLS_KEY_FILE="${HYSTERIA2_TLS_KEY_FILE}"
  INSTALLED_HYSTERIA2_AUTH_PASSWORD="${HYSTERIA2_AUTH_PASSWORD}"
  INSTALLED_HYSTERIA2_MASQUERADE_TYPE="${HYSTERIA2_MASQUERADE_TYPE}"
  INSTALLED_HYSTERIA2_MASQUERADE_URL="${HYSTERIA2_MASQUERADE_URL}"
  INSTALLED_HYSTERIA2_MASQUERADE_REWRITE_HOST="${HYSTERIA2_MASQUERADE_REWRITE_HOST}"
  INSTALLED_HYSTERIA2_MASQUERADE_INSECURE="${HYSTERIA2_MASQUERADE_INSECURE}"

  INSTALLED_SS2022_LISTEN_PORT="${SS2022_LISTEN_PORT}"
  INSTALLED_SS2022_METHOD="${SS2022_METHOD}"
  INSTALLED_SS2022_PASSWORD="${SS2022_PASSWORD}"

  INSTALLED_BOT_TOKEN="${BOT_TOKEN}"
  INSTALLED_CHAT_ID="${CHAT_ID}"
  INSTALLED_BOT_BIND_TOKEN="${BOT_BIND_TOKEN}"
}

maybe_migrate_xray_install_checksum_policy() {
  local old_default_url old_default_sha old_version
  old_default_url="https://raw.githubusercontent.com/XTLS/Xray-install/e741a4f56d368afbb9e5be3361b40c4552d3710d/install-release.sh"
  old_default_sha="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
  old_version="${CONFIG_VERSION:-0}"
  [[ "${old_version}" =~ ^[0-9]+$ ]] || old_version=0

  if (( old_version < 2 )) \
    && [[ "${XRAY_INSTALL_SCRIPT_URL}" == "${old_default_url}" ]] \
    && [[ "${XRAY_INSTALL_SCRIPT_SHA256}" == "${old_default_sha}" ]] \
    && [[ "${XRAY_INSTALL_VERIFY_SHA256}" == "yes" ]]; then
    XRAY_INSTALL_VERIFY_SHA256="no"
    info "Migrated XRAY_INSTALL_VERIFY_SHA256 from yes to no for the legacy pinned Xray installer policy."
  fi
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
  if [[ -f "${NEFLARE_BOT_STATE_DIR}/runtime.env" ]]; then
    info "Loading bot runtime overrides from ${NEFLARE_BOT_STATE_DIR}/runtime.env"
    source_env_file "${NEFLARE_BOT_STATE_DIR}/runtime.env"
  fi
  maybe_migrate_xray_install_checksum_policy
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

validate_udp_port() {
  validate_tcp_port "$1"
}

validate_public_key() {
  local key="$1"
  [[ -n "${key}" ]] || return 1
  ssh-keygen -l -f <(printf '%s\n' "${key}") >/dev/null 2>&1
}

installer_text() {
  local key="$1"
  shift || true
  local format=""

  case "$(current_ui_lang):${key}" in
    zh:section_system_host) format='1）系统 / 主机设置' ;;
    zh:section_protocol_selection) format='2）协议选择' ;;
    zh:section_protocol_settings) format='3）协议详细设置' ;;
    zh:section_bot_settings) format='4）Telegram Bot 设置' ;;
    zh:section_final_summary) format='5）最终摘要 / 确认' ;;
    zh:system_host_settings) format='系统 / 主机设置' ;;
    zh:protocols) format='协议' ;;
    zh:telegram_bot) format='Telegram Bot' ;;
    zh:current_states) format='当前状态：' ;;
    zh:admin_user) format='管理员用户名' ;;
    zh:admin_ssh_public_key) format='管理员 SSH 公钥' ;;
    zh:persisted_ssh_port) format='持久化 SSH 端口' ;;
    zh:enable_ipv6) format='启用 IPv6' ;;
    zh:enable_docker_tests) format='启用一次性 Docker 网络测试' ;;
    zh:enable_time_sync) format='启用系统自动校时与定期校准' ;;
    zh:repo_sync_url) format='仓库同步 URL' ;;
    zh:repo_sync_branch) format='仓库同步分支' ;;
    zh:repo_sync_dir) format='仓库同步目录' ;;
    zh:server_public_endpoint) format='客户端连接地址覆盖（留空自动检测）' ;;
    zh:xray_upgrade_flag) format='Xray 核心升级仍需显式触发，本次运行升级标志：%s' ;;
    zh:enable_vless_reality) format='启用 VLESS+REALITY' ;;
    zh:enable_hysteria2) format='启用 Hysteria 2' ;;
    zh:enable_ss2022) format='启用 Shadowsocks 2022' ;;
    zh:open_vless_advanced) format='进入 VLESS+REALITY 高级编辑菜单' ;;
    zh:vless_port) format='VLESS+REALITY TCP 监听端口' ;;
    zh:change_reality_target) format='修改当前 REALITY 目标 / 域名选择' ;;
    zh:edit_reality_materials) format='修改 UUID / 密钥材料 / short IDs' ;;
    zh:reality_uuid) format='REALITY UUID' ;;
    zh:reality_private_key) format='REALITY 私钥' ;;
    zh:reality_public_key) format='REALITY 公钥' ;;
    zh:reality_short_ids) format='REALITY short IDs（逗号分隔）' ;;
    zh:hysteria2_port) format='Hysteria 2 UDP 监听端口' ;;
    zh:hysteria2_domain) format='Hysteria 2 域名' ;;
    zh:hysteria2_tls_mode) format='Hysteria 2 TLS 模式（acme/file）' ;;
    zh:hysteria2_acme_email) format='Hysteria 2 ACME 邮箱' ;;
    zh:hysteria2_acme_dir) format='Hysteria 2 ACME 目录' ;;
    zh:hysteria2_acme_challenge) format='Hysteria 2 ACME 验证方式（http）' ;;
    zh:hysteria2_acme_http_port) format='Hysteria 2 ACME HTTP 验证端口' ;;
    zh:hysteria2_cert_file) format='Hysteria 2 证书文件' ;;
    zh:hysteria2_key_file) format='Hysteria 2 证书私钥文件' ;;
    zh:hysteria2_auth_password) format='Hysteria 2 认证密码' ;;
    zh:hysteria2_masquerade_type) format='Hysteria 2 伪装模式（proxy/none）' ;;
    zh:hysteria2_masquerade_url) format='Hysteria 2 伪装代理 URL' ;;
    zh:hysteria2_rewrite_host) format='伪装代理时改写 Host' ;;
    zh:hysteria2_insecure) format='关闭伪装源站 TLS 校验' ;;
    zh:ss2022_port) format='Shadowsocks 2022 监听端口' ;;
    zh:ss2022_method) format='Shadowsocks 2022 加密方法' ;;
    zh:ss2022_password) format='Shadowsocks 2022 密码' ;;
    zh:no_proxy_protocols_enabled) format='当前未启用任何代理协议。本次安装将只维护 SSH、防火墙和可选 Bot 设置。' ;;
    zh:enable_bot) format='启用 Telegram Bot 支持' ;;
    zh:bot_disabled_notice) format='Bot 配置会保留在磁盘中，但服务保持禁用。' ;;
    zh:bot_token) format='Telegram BOT_TOKEN' ;;
    zh:chat_id) format='Telegram CHAT_ID' ;;
    zh:bot_token_configured) format='BOT_TOKEN 当前状态：%s' ;;
    zh:chat_id_configured) format='CHAT_ID 当前状态：%s' ;;
    zh:chat_id_not_configured) format='CHAT_ID 尚未配置；安装器会按需保留或生成 BOT_BIND_TOKEN。' ;;
    zh:bot_bind_state) format='BOT_BIND_TOKEN 状态：%s' ;;
    zh:daily_report_time) format='每日报告时间 HH:MM' ;;
    zh:daily_report_timezone) format='每日报告时区' ;;
    zh:monthly_quota_cap) format='月流量配额（GB，0 表示不限制）' ;;
    zh:monthly_quota_reset) format='每月配额重置日（UTC，建议 1-28）' ;;
    zh:enabled_protocols) format='启用的协议' ;;
    zh:listener_label) format='监听' ;;
    zh:selected_domain) format='当前域名' ;;
    zh:reality_material) format='REALITY 材料' ;;
    zh:docker_tests) format='Docker 测试' ;;
    zh:repo_sync) format='仓库同步' ;;
    zh:xray_upgrade_this_run) format='本次运行升级 Xray 核心' ;;
    zh:enabled_label) format='启用' ;;
    zh:current_reality_domain) format='当前 REALITY 域名' ;;
    zh:uuid_label) format='UUID' ;;
    zh:key_material) format='密钥材料' ;;
    zh:short_ids) format='Short IDs' ;;
    zh:domain) format='域名' ;;
    zh:tls_mode) format='TLS 模式' ;;
    zh:acme_email) format='ACME 邮箱' ;;
    zh:acme_challenge) format='ACME 验证' ;;
    zh:certificate_file) format='证书文件' ;;
    zh:key_file) format='私钥文件' ;;
    zh:auth_password) format='认证密码' ;;
    zh:masquerade) format='伪装' ;;
    zh:report_schedule) format='报告计划' ;;
    zh:time_sync) format='自动校时' ;;
    zh:preserve_or_auto_select) format='[保留现有 / 稍后自动选择]' ;;
    zh:configured) format='[已配置]' ;;
    zh:not_configured) format='[未配置]' ;;
    zh:preserve_existing) format='[保留现有]' ;;
    zh:enabled) format='已启用' ;;
    zh:disabled) format='未启用' ;;
    zh:none) format='无' ;;
    zh:keep_existing_hint) format='直接回车保留现有值' ;;
    zh:clear_hint) format='输入 clear 清空' ;;
    zh:apply_configuration) format='应用以上配置' ;;
    zh:ss2022_clock_warning) format='Shadowsocks 2022 使用重放保护，强烈建议保持系统时间自动同步。' ;;
    en:section_system_host) format='1) System / host settings' ;;
    en:section_protocol_selection) format='2) Protocol selection' ;;
    en:section_protocol_settings) format='3) Per-protocol settings' ;;
    en:section_bot_settings) format='4) Telegram bot settings' ;;
    en:section_final_summary) format='5) Final summary / confirmation' ;;
    en:system_host_settings) format='System / host settings' ;;
    en:protocols) format='Protocols' ;;
    en:telegram_bot) format='Telegram bot' ;;
    en:current_states) format='Current states:' ;;
    en:admin_user) format='Admin user' ;;
    en:admin_ssh_public_key) format='Admin SSH public key' ;;
    en:persisted_ssh_port) format='Persisted SSH port' ;;
    en:enable_ipv6) format='Enable IPv6' ;;
    en:enable_docker_tests) format='Enable disposable Docker-backed tests' ;;
    en:enable_time_sync) format='Enable system time sync and periodic recalibration' ;;
    en:repo_sync_url) format='Repository sync URL' ;;
    en:repo_sync_branch) format='Repository sync branch' ;;
    en:repo_sync_dir) format='Repository sync directory' ;;
    en:server_public_endpoint) format='Client-facing server IP/domain override (blank to auto-detect)' ;;
    en:xray_upgrade_flag) format='Xray core upgrades remain explicit. Current run upgrade flag: %s' ;;
    en:enable_vless_reality) format='Enable VLESS+REALITY' ;;
    en:enable_hysteria2) format='Enable Hysteria 2' ;;
    en:enable_ss2022) format='Enable Shadowsocks 2022' ;;
    en:open_vless_advanced) format='Open advanced VLESS+REALITY edit menu' ;;
    en:vless_port) format='VLESS+REALITY TCP listener port' ;;
    en:change_reality_target) format='Change the current REALITY target/domain selection' ;;
    en:edit_reality_materials) format='Edit UUID / key material / short IDs' ;;
    en:reality_uuid) format='REALITY UUID' ;;
    en:reality_private_key) format='REALITY private key' ;;
    en:reality_public_key) format='REALITY public key' ;;
    en:reality_short_ids) format='REALITY short IDs (comma-separated)' ;;
    en:hysteria2_port) format='Hysteria 2 UDP listener port' ;;
    en:hysteria2_domain) format='Hysteria 2 domain' ;;
    en:hysteria2_tls_mode) format='Hysteria 2 TLS mode (acme/file)' ;;
    en:hysteria2_acme_email) format='Hysteria 2 ACME email' ;;
    en:hysteria2_acme_dir) format='Hysteria 2 ACME directory' ;;
    en:hysteria2_acme_challenge) format='Hysteria 2 ACME challenge type (http)' ;;
    en:hysteria2_acme_http_port) format='Hysteria 2 ACME HTTP challenge port' ;;
    en:hysteria2_cert_file) format='Hysteria 2 certificate file' ;;
    en:hysteria2_key_file) format='Hysteria 2 certificate key file' ;;
    en:hysteria2_auth_password) format='Hysteria 2 auth password' ;;
    en:hysteria2_masquerade_type) format='Hysteria 2 masquerade (proxy/none)' ;;
    en:hysteria2_masquerade_url) format='Hysteria 2 masquerade proxy URL' ;;
    en:hysteria2_rewrite_host) format='Rewrite Host when proxying masquerade traffic' ;;
    en:hysteria2_insecure) format='Disable TLS verification for the masquerade origin' ;;
    en:ss2022_port) format='Shadowsocks 2022 listener port' ;;
    en:ss2022_method) format='Shadowsocks 2022 method' ;;
    en:ss2022_password) format='Shadowsocks 2022 password' ;;
    en:no_proxy_protocols_enabled) format='No proxy protocols enabled. The installer will maintain SSH, firewall, and optional bot settings only.' ;;
    en:enable_bot) format='Enable Telegram bot support' ;;
    en:bot_disabled_notice) format='Bot settings will be kept on disk but the service will remain disabled.' ;;
    en:bot_token) format='Telegram BOT_TOKEN' ;;
    en:chat_id) format='Telegram CHAT_ID' ;;
    en:bot_token_configured) format='BOT_TOKEN state: %s' ;;
    en:chat_id_configured) format='CHAT_ID state: %s' ;;
    en:chat_id_not_configured) format='CHAT_ID is not configured yet. The installer will preserve or generate BOT_BIND_TOKEN as needed.' ;;
    en:bot_bind_state) format='BOT_BIND_TOKEN state: %s' ;;
    en:daily_report_time) format='Daily report time HH:MM' ;;
    en:daily_report_timezone) format='Daily report timezone' ;;
    en:monthly_quota_cap) format='Monthly quota cap in GB (0 disables cap)' ;;
    en:monthly_quota_reset) format='Monthly quota reset day in UTC (1-28 recommended)' ;;
    en:enabled_protocols) format='Enabled protocols' ;;
    en:listener_label) format='Listener' ;;
    en:selected_domain) format='Selected domain' ;;
    en:reality_material) format='REALITY material' ;;
    en:docker_tests) format='Docker tests' ;;
    en:repo_sync) format='Repo sync' ;;
    en:xray_upgrade_this_run) format='Xray core upgrade this run' ;;
    en:enabled_label) format='Enabled' ;;
    en:current_reality_domain) format='Current REALITY domain' ;;
    en:uuid_label) format='UUID' ;;
    en:key_material) format='Key material' ;;
    en:short_ids) format='Short IDs' ;;
    en:domain) format='Domain' ;;
    en:tls_mode) format='TLS mode' ;;
    en:acme_email) format='ACME email' ;;
    en:acme_challenge) format='ACME challenge' ;;
    en:certificate_file) format='Certificate file' ;;
    en:key_file) format='Key file' ;;
    en:auth_password) format='Auth password' ;;
    en:masquerade) format='Masquerade' ;;
    en:report_schedule) format='Report schedule' ;;
    en:time_sync) format='Time sync' ;;
    en:preserve_or_auto_select) format='[preserve existing / auto-select later]' ;;
    en:configured) format='[configured]' ;;
    en:not_configured) format='[not configured]' ;;
    en:preserve_existing) format='[preserve existing]' ;;
    en:enabled) format='enabled' ;;
    en:disabled) format='disabled' ;;
    en:none) format='none' ;;
    en:keep_existing_hint) format='press Enter to keep existing' ;;
    en:clear_hint) format="type 'clear' to remove" ;;
    en:apply_configuration) format='Apply this configuration' ;;
    en:ss2022_clock_warning) format='Shadowsocks 2022 uses replay protection, so keeping the system clock synchronized is strongly recommended.' ;;
    *) format='%s' ; set -- "${key}" "$@" ;;
  esac

  printf -- "${format}" "$@"
}

section_heading() {
  local title="$1"
  echo
  echo "== ${title} =="
}

configured_state_marker() {
  if [[ -n "${1:-}" ]]; then
    installer_text configured
  else
    installer_text not_configured
  fi
  printf '\n'
}

preserve_state_marker() {
  if [[ -n "${1:-}" ]]; then
    installer_text preserve_existing
  else
    installer_text not_configured
  fi
  printf '\n'
}

enabled_state_label() {
  if [[ "$(normalize_yes_no "${1:-no}")" == "yes" ]]; then
    installer_text enabled
  else
    installer_text disabled
  fi
  printf '\n'
}

read_yes_no_setting() {
  local prompt="$1"
  local default_value="$2"
  local answer
  answer="$(read_prompt "${prompt}" "${default_value}" yes)"
  answer="$(normalize_yes_no "${answer}")"
  [[ "${answer}" == "yes" || "${answer}" == "no" ]] || die "Expected yes or no for '${prompt}', got '${answer}'."
  printf '%s\n' "${answer}"
}

read_choice_setting() {
  local prompt="$1"
  local default_value="$2"
  shift 2
  local answer
  answer="$(read_prompt "${prompt}" "${default_value}" yes)"
  answer="$(trim "${answer}")"
  local allowed
  for allowed in "$@"; do
    if [[ "${answer}" == "${allowed}" ]]; then
      printf '%s\n' "${answer}"
      return 0
    fi
  done
  die "Expected one of [$*] for '${prompt}', got '${answer}'."
}

read_sensitive_setting() {
  local prompt="$1"
  local current_value="$2"
  local required="${3:-no}"
  local secret_input="${4:-no}"
  local allow_clear="${5:-no}"
  local state_label value allow_hint

  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    if [[ -n "${current_value}" || "${required}" != "yes" ]]; then
      printf '%s\n' "${current_value}"
      return 0
    fi
    die "Required value missing for '${prompt}'."
  fi

  state_label="$(configured_state_marker "${current_value}")"
  allow_hint=""
  if [[ -n "${current_value}" ]]; then
    allow_hint=", $(installer_text keep_existing_hint)"
  fi
  if [[ "${allow_clear}" == "yes" ]]; then
    allow_hint="${allow_hint}, $(installer_text clear_hint)"
  fi

  while true; do
    if [[ "${secret_input}" == "yes" ]]; then
      read -r -s -p "${prompt} ${state_label}${allow_hint}: " value
      printf '\n' >&2
    else
      read -r -p "${prompt} ${state_label}${allow_hint}: " value
    fi
    if [[ -z "${value}" && -n "${current_value}" ]]; then
      printf '%s\n' "${current_value}"
      return 0
    fi
    if [[ "${allow_clear}" == "yes" && "${value}" == "clear" ]]; then
      printf '\n'
      return 0
    fi
    if [[ -n "${value}" || "${required}" != "yes" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done
}

protocols_enabled_summary() {
  local names=()
  enable_vless_reality && names+=("VLESS+REALITY")
  enable_hysteria2 && names+=("Hysteria 2")
  enable_ss2022 && names+=("Shadowsocks 2022")
  if [[ "${#names[@]}" -eq 0 ]]; then
    installer_text none
    printf '\n'
  else
    join_by ", " "${names[@]}" | tr -d '\n'
    printf '\n'
  fi
}

vless_reality_change_requested() {
  [[ "${INSTALLED_CONFIG_PRESENT}" == "yes" ]] || return 1
  [[ "${ENABLE_VLESS_REALITY}" != "${INSTALLED_ENABLE_VLESS_REALITY}" ]] && return 0
  [[ "${XRAY_LISTEN_PORT}" != "${INSTALLED_XRAY_LISTEN_PORT}" ]] && return 0
  [[ "${REALITY_CANDIDATES}" != "${INSTALLED_REALITY_CANDIDATES}" ]] && return 0
  [[ "${REALITY_AUTO_RECOMMEND}" != "${INSTALLED_REALITY_AUTO_RECOMMEND}" ]] && return 0
  [[ "${REALITY_SELECTED_DOMAIN}" != "${INSTALLED_REALITY_SELECTED_DOMAIN}" ]] && return 0
  [[ "${REALITY_SERVER_NAME}" != "${INSTALLED_REALITY_SERVER_NAME}" ]] && return 0
  [[ "${REALITY_DEST}" != "${INSTALLED_REALITY_DEST}" ]] && return 0
  [[ "${XRAY_UUID}" != "${INSTALLED_XRAY_UUID}" ]] && return 0
  [[ "${XRAY_PRIVATE_KEY}" != "${INSTALLED_XRAY_PRIVATE_KEY}" ]] && return 0
  [[ "${XRAY_PUBLIC_KEY}" != "${INSTALLED_XRAY_PUBLIC_KEY}" ]] && return 0
  [[ "${XRAY_SHORT_IDS}" != "${INSTALLED_XRAY_SHORT_IDS}" ]] && return 0
  [[ "${ALLOW_NONSTANDARD_REALITY_PORT}" != "${INSTALLED_ALLOW_NONSTANDARD_REALITY_PORT}" ]] && return 0
  [[ "${ALLOW_DISCOURAGED_REALITY_TARGET}" != "${INSTALLED_ALLOW_DISCOURAGED_REALITY_TARGET}" ]] && return 0
  return 1
}

prompt_system_host_settings() {
  local default_admin default_tz key_default ssh_default report_time_default
  default_admin="$(guess_default_admin_user)"
  default_tz="$(detect_default_timezone)"
  key_default="$(guess_public_key_from_system)"
  report_time_default="${REPORT_TIME:-08:00}"

  section_heading "$(installer_text section_system_host)"

  ADMIN_USER="$(read_prompt "$(installer_text admin_user)" "${ADMIN_USER:-${default_admin}}" yes)"
  if [[ -z "${ADMIN_PUBLIC_KEY}" ]]; then
    ADMIN_PUBLIC_KEY="$(read_prompt "$(installer_text admin_ssh_public_key)" "${key_default}" yes)"
  else
    ADMIN_PUBLIC_KEY="$(read_prompt "$(installer_text admin_ssh_public_key)" "${ADMIN_PUBLIC_KEY}" yes)"
  fi

  if [[ -z "${SSH_PORT}" ]]; then
    ssh_default="$(generate_random_high_port)"
  else
    ssh_default="${SSH_PORT}"
  fi
  SSH_PORT="$(read_prompt "$(installer_text persisted_ssh_port)" "${ssh_default}" yes)"
  ENABLE_IPV6="$(read_yes_no_setting "$(installer_text enable_ipv6)" "${ENABLE_IPV6:-yes}")"
  ENABLE_DOCKER_TESTS="$(read_yes_no_setting "$(installer_text enable_docker_tests)" "${ENABLE_DOCKER_TESTS:-yes}")"
  ENABLE_TIME_SYNC="$(read_yes_no_setting "$(installer_text enable_time_sync)" "${ENABLE_TIME_SYNC:-yes}")"
  REPO_SYNC_URL="$(read_prompt "$(installer_text repo_sync_url)" "${REPO_SYNC_URL}" yes)"
  REPO_SYNC_BRANCH="$(read_prompt "$(installer_text repo_sync_branch)" "${REPO_SYNC_BRANCH}" yes)"
  REPO_SYNC_DIR="$(read_prompt "$(installer_text repo_sync_dir)" "${REPO_SYNC_DIR}" yes)"
  SERVER_PUBLIC_ENDPOINT="$(read_prompt "$(installer_text server_public_endpoint)" "${SERVER_PUBLIC_ENDPOINT}" no)"
  info "$(installer_text xray_upgrade_flag "$(enabled_state_label "${UPGRADE_XRAY}")")"
  REPORT_TIME="${REPORT_TIME:-${report_time_default}}"
  REPORT_TZ="${REPORT_TZ:-${default_tz}}"
}

prompt_protocol_selection_menu() {
  section_heading "$(installer_text section_protocol_selection)"
  echo "$(installer_text current_states)"
  echo "- VLESS+REALITY: $(enabled_state_label "${ENABLE_VLESS_REALITY}")"
  echo "- Hysteria 2: $(enabled_state_label "${ENABLE_HYSTERIA2}")"
  echo "- Shadowsocks 2022: $(enabled_state_label "${ENABLE_SS2022}")"

  ENABLE_VLESS_REALITY="$(read_yes_no_setting "$(installer_text enable_vless_reality)" "${ENABLE_VLESS_REALITY}")"
  ENABLE_HYSTERIA2="$(read_yes_no_setting "$(installer_text enable_hysteria2)" "${ENABLE_HYSTERIA2}")"
  ENABLE_SS2022="$(read_yes_no_setting "$(installer_text enable_ss2022)" "${ENABLE_SS2022}")"
}

prompt_vless_reality_settings() {
  local current_complete current_port material_state
  enable_vless_reality || return 0

  echo
  echo "VLESS+REALITY"
  current_complete="no"
  if vless_reality_config_complete; then
    current_complete="yes"
  fi

  if [[ "${current_complete}" == "yes" ]] && [[ "${INSTALLED_CONFIG_PRESENT}" == "yes" ]] && ! vless_reality_change_requested && [[ "${VLESS_REALITY_ADVANCED_EDIT}" != "yes" ]]; then
    current_port="${XRAY_LISTEN_PORT}"
    material_state="$(preserve_state_marker "${XRAY_PRIVATE_KEY}")"
    echo "- $(installer_text listener_label): TCP ${current_port}"
    echo "- $(installer_text selected_domain): ${REALITY_SELECTED_DOMAIN}"
    echo "- $(installer_text reality_material): ${material_state}"
    VLESS_REALITY_ADVANCED_EDIT="$(read_yes_no_setting "$(installer_text open_vless_advanced)" "no")"
    if [[ "${VLESS_REALITY_ADVANCED_EDIT}" != "yes" ]]; then
      VLESS_REALITY_EDIT_TARGET="no"
      VLESS_REALITY_EDIT_MATERIALS="no"
      return 0
    fi
  else
    VLESS_REALITY_ADVANCED_EDIT="yes"
  fi

  XRAY_LISTEN_PORT="$(read_prompt "$(installer_text vless_port)" "${XRAY_LISTEN_PORT:-443}" yes)"
  if [[ "${XRAY_LISTEN_PORT}" == "443" ]]; then
    ALLOW_NONSTANDARD_REALITY_PORT="no"
  else
    warn "$(i18n_text warn_non443)"
    confirm_or_die "$(i18n_text confirm_non443 "${XRAY_LISTEN_PORT}")"
    ALLOW_NONSTANDARD_REALITY_PORT="yes"
  fi

  REALITY_CANDIDATES="$(read_prompt "$(i18n_text prompt_reality_candidates)" "${REALITY_CANDIDATES}" yes)"
  REALITY_AUTO_RECOMMEND="$(read_yes_no_setting "$(i18n_text prompt_auto_select)" "${REALITY_AUTO_RECOMMEND:-yes}")"

  if [[ "${current_complete}" == "yes" ]]; then
    VLESS_REALITY_EDIT_TARGET="$(read_yes_no_setting "$(installer_text change_reality_target)" "no")"
    VLESS_REALITY_EDIT_MATERIALS="$(read_yes_no_setting "$(installer_text edit_reality_materials)" "no")"
    if [[ "${VLESS_REALITY_EDIT_TARGET}" != "yes" ]]; then
      REALITY_SELECTED_DOMAIN="${INSTALLED_REALITY_SELECTED_DOMAIN}"
      REALITY_SERVER_NAME="${INSTALLED_REALITY_SERVER_NAME}"
      REALITY_DEST="${INSTALLED_REALITY_DEST}"
    fi
    if [[ "${VLESS_REALITY_EDIT_MATERIALS}" != "yes" ]]; then
      XRAY_UUID="${INSTALLED_XRAY_UUID}"
      XRAY_PRIVATE_KEY="${INSTALLED_XRAY_PRIVATE_KEY}"
      XRAY_PUBLIC_KEY="${INSTALLED_XRAY_PUBLIC_KEY}"
      XRAY_SHORT_IDS="${INSTALLED_XRAY_SHORT_IDS}"
    fi
  else
    VLESS_REALITY_EDIT_TARGET="yes"
    VLESS_REALITY_EDIT_MATERIALS="no"
  fi

  if [[ "${VLESS_REALITY_EDIT_MATERIALS}" == "yes" ]]; then
    XRAY_UUID="$(read_sensitive_setting "$(installer_text reality_uuid)" "${XRAY_UUID}" yes no no)"
    XRAY_PRIVATE_KEY="$(read_sensitive_setting "$(installer_text reality_private_key)" "${XRAY_PRIVATE_KEY}" yes yes no)"
    XRAY_PUBLIC_KEY="$(read_sensitive_setting "$(installer_text reality_public_key)" "${XRAY_PUBLIC_KEY}" yes no no)"
    XRAY_SHORT_IDS="$(read_sensitive_setting "$(installer_text reality_short_ids)" "${XRAY_SHORT_IDS}" yes no no)"
  fi
}

prompt_hysteria2_settings() {
  enable_hysteria2 || return 0

  echo
  echo "Hysteria 2"
  HYSTERIA2_LISTEN_PORT="$(read_prompt "$(installer_text hysteria2_port)" "${HYSTERIA2_LISTEN_PORT:-443}" yes)"
  HYSTERIA2_DOMAIN="$(read_prompt "$(installer_text hysteria2_domain)" "${HYSTERIA2_DOMAIN}" yes)"
  HYSTERIA2_TLS_MODE="$(read_choice_setting "$(installer_text hysteria2_tls_mode)" "${HYSTERIA2_TLS_MODE:-acme}" acme file)"
  if [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
    HYSTERIA2_ACME_EMAIL="$(read_prompt "$(installer_text hysteria2_acme_email)" "${HYSTERIA2_ACME_EMAIL}" yes)"
    HYSTERIA2_ACME_DIR="$(read_prompt "$(installer_text hysteria2_acme_dir)" "${HYSTERIA2_ACME_DIR}" yes)"
    HYSTERIA2_ACME_CHALLENGE_TYPE="$(read_choice_setting "$(installer_text hysteria2_acme_challenge)" "${HYSTERIA2_ACME_CHALLENGE_TYPE:-http}" http)"
    HYSTERIA2_ACME_HTTP_PORT="$(read_prompt "$(installer_text hysteria2_acme_http_port)" "${HYSTERIA2_ACME_HTTP_PORT:-80}" yes)"
    HYSTERIA2_TLS_CERT_FILE=""
    HYSTERIA2_TLS_KEY_FILE=""
  else
    HYSTERIA2_TLS_CERT_FILE="$(read_prompt "$(installer_text hysteria2_cert_file)" "${HYSTERIA2_TLS_CERT_FILE}" yes)"
    HYSTERIA2_TLS_KEY_FILE="$(read_prompt "$(installer_text hysteria2_key_file)" "${HYSTERIA2_TLS_KEY_FILE}" yes)"
  fi
  HYSTERIA2_AUTH_PASSWORD="$(read_sensitive_setting "$(installer_text hysteria2_auth_password)" "${HYSTERIA2_AUTH_PASSWORD}" yes yes no)"
  HYSTERIA2_MASQUERADE_TYPE="$(read_choice_setting "$(installer_text hysteria2_masquerade_type)" "${HYSTERIA2_MASQUERADE_TYPE:-proxy}" proxy none)"
  if [[ "${HYSTERIA2_MASQUERADE_TYPE}" == "proxy" ]]; then
    HYSTERIA2_MASQUERADE_URL="$(read_prompt "$(installer_text hysteria2_masquerade_url)" "${HYSTERIA2_MASQUERADE_URL}" yes)"
    HYSTERIA2_MASQUERADE_REWRITE_HOST="$(read_yes_no_setting "$(installer_text hysteria2_rewrite_host)" "${HYSTERIA2_MASQUERADE_REWRITE_HOST:-yes}")"
    HYSTERIA2_MASQUERADE_INSECURE="$(read_yes_no_setting "$(installer_text hysteria2_insecure)" "${HYSTERIA2_MASQUERADE_INSECURE:-no}")"
  else
    HYSTERIA2_MASQUERADE_URL=""
    HYSTERIA2_MASQUERADE_REWRITE_HOST="yes"
    HYSTERIA2_MASQUERADE_INSECURE="no"
  fi
}

prompt_ss2022_settings() {
  enable_ss2022 || return 0

  echo
  echo "Shadowsocks 2022"
  SS2022_LISTEN_PORT="$(read_prompt "$(installer_text ss2022_port)" "${SS2022_LISTEN_PORT:-40010}" yes)"
  SS2022_METHOD="$(read_choice_setting "$(installer_text ss2022_method)" "${SS2022_METHOD:-2022-blake3-aes-256-gcm}" 2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305)"
  SS2022_PASSWORD="$(read_sensitive_setting "$(installer_text ss2022_password)" "${SS2022_PASSWORD}" yes yes no)"
}

prompt_protocol_settings() {
  section_heading "$(installer_text section_protocol_settings)"
  if ! enable_vless_reality && ! enable_hysteria2 && ! enable_ss2022; then
    echo "- $(installer_text no_proxy_protocols_enabled)"
    return 0
  fi
  prompt_vless_reality_settings
  prompt_hysteria2_settings
  prompt_ss2022_settings
}

prompt_bot_settings() {
  local default_tz
  default_tz="$(detect_default_timezone)"

  section_heading "$(installer_text section_bot_settings)"
  ENABLE_BOT="$(read_yes_no_setting "$(installer_text enable_bot)" "${ENABLE_BOT:-yes}")"
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    echo "- $(installer_text bot_disabled_notice)"
    return 0
  fi

  BOT_TOKEN="$(read_sensitive_setting "$(installer_text bot_token)" "${BOT_TOKEN}" no yes yes)"
  CHAT_ID="$(read_sensitive_setting "$(installer_text chat_id)" "${CHAT_ID}" no no yes)"
  if [[ -n "${BOT_TOKEN}" ]]; then
    echo "- $(installer_text bot_token_configured "$(configured_state_marker "${BOT_TOKEN}")")"
  fi
  if [[ -n "${CHAT_ID}" ]]; then
    echo "- $(installer_text chat_id_configured "$(configured_state_marker "${CHAT_ID}")")"
  else
    echo "- $(installer_text chat_id_not_configured)"
  fi
  echo "- $(installer_text bot_bind_state "$(preserve_state_marker "${BOT_BIND_TOKEN}")")"

  REPORT_TIME="$(read_prompt "$(installer_text daily_report_time)" "${REPORT_TIME:-08:00}" yes)"
  REPORT_TZ="$(read_prompt "$(installer_text daily_report_timezone)" "${REPORT_TZ:-${default_tz}}" yes)"
  QUOTA_MONTHLY_CAP_GB="$(read_prompt "$(installer_text monthly_quota_cap)" "${QUOTA_MONTHLY_CAP_GB}" yes)"
  QUOTA_RESET_DAY_UTC="$(read_prompt "$(installer_text monthly_quota_reset)" "${QUOTA_RESET_DAY_UTC}" yes)"
}

print_install_summary() {
  section_heading "$(installer_text section_final_summary)"
  echo "$(installer_text system_host_settings)"
  echo "- $(installer_text admin_user): ${ADMIN_USER}"
  echo "- SSH: TCP ${SSH_PORT}"
  echo "- IPv6: $(i18n_bool "${ENABLE_IPV6}")"
  echo "- $(installer_text docker_tests): $(enabled_state_label "${ENABLE_DOCKER_TESTS}")"
  echo "- $(installer_text time_sync): $(enabled_state_label "${ENABLE_TIME_SYNC}")"
  echo "- $(installer_text repo_sync): ${REPO_SYNC_URL} (${REPO_SYNC_BRANCH}) -> ${REPO_SYNC_DIR}"
  echo "- $(installer_text xray_upgrade_this_run): $(enabled_state_label "${UPGRADE_XRAY}")"
  echo
  echo "$(installer_text protocols)"
  echo "- $(installer_text enabled_protocols): $(protocols_enabled_summary)"
  if enable_vless_reality; then
    echo "- VLESS+REALITY: TCP ${XRAY_LISTEN_PORT}"
    echo "  $(installer_text current_reality_domain): ${REALITY_SELECTED_DOMAIN:-$(installer_text preserve_or_auto_select)}"
    echo "  $(installer_text uuid_label): $(preserve_state_marker "${XRAY_UUID}")"
    echo "  $(installer_text key_material): $(preserve_state_marker "${XRAY_PRIVATE_KEY}")"
    echo "  $(installer_text short_ids): $(preserve_state_marker "${XRAY_SHORT_IDS}")"
  else
    echo "- VLESS+REALITY: $(installer_text disabled)"
  fi
  if enable_hysteria2; then
    echo "- Hysteria 2: UDP ${HYSTERIA2_LISTEN_PORT}"
    echo "  $(installer_text domain): ${HYSTERIA2_DOMAIN}"
    echo "  $(installer_text tls_mode): ${HYSTERIA2_TLS_MODE}"
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
      echo "  $(installer_text acme_email): ${HYSTERIA2_ACME_EMAIL}"
      echo "  $(installer_text acme_challenge): ${HYSTERIA2_ACME_CHALLENGE_TYPE} on TCP/${HYSTERIA2_ACME_HTTP_PORT}"
    else
      echo "  $(installer_text certificate_file): ${HYSTERIA2_TLS_CERT_FILE}"
      echo "  $(installer_text key_file): ${HYSTERIA2_TLS_KEY_FILE}"
    fi
    echo "  $(installer_text auth_password): $(configured_state_marker "${HYSTERIA2_AUTH_PASSWORD}")"
    echo "  $(installer_text masquerade): ${HYSTERIA2_MASQUERADE_TYPE}${HYSTERIA2_MASQUERADE_URL:+ (${HYSTERIA2_MASQUERADE_URL})}"
  else
    echo "- Hysteria 2: $(installer_text disabled)"
  fi
  if enable_ss2022; then
    echo "- Shadowsocks 2022: TCP/UDP ${SS2022_LISTEN_PORT}"
    echo "  Method: ${SS2022_METHOD}"
    echo "  Password: $(configured_state_marker "${SS2022_PASSWORD}")"
  else
    echo "- Shadowsocks 2022: $(installer_text disabled)"
  fi
  echo
  echo "$(installer_text telegram_bot)"
  echo "- $(installer_text enabled_label): $(enabled_state_label "${ENABLE_BOT}")"
  echo "- BOT_TOKEN: $(configured_state_marker "${BOT_TOKEN}")"
  echo "- CHAT_ID: $(configured_state_marker "${CHAT_ID}")"
  echo "- BOT_BIND_TOKEN: $(preserve_state_marker "${BOT_BIND_TOKEN}")"
  if [[ "${ENABLE_BOT}" == "yes" ]]; then
    echo "- $(installer_text report_schedule): ${REPORT_TIME} ${REPORT_TZ}"
  fi
}

prompt_install_config() {
  prompt_system_host_settings
  prompt_protocol_selection_menu
  prompt_protocol_settings
  prompt_bot_settings
  print_install_summary
  confirm_or_die "$(installer_text apply_configuration)"
}

validate_listener_collisions() {
  declare -A seen=()
  local listeners=()
  listeners+=("ssh:tcp:${SSH_PORT}")
  if enable_vless_reality; then
    listeners+=("vless-reality:tcp:${XRAY_LISTEN_PORT}")
  fi
  if enable_hysteria2; then
    listeners+=("hysteria2:udp:${HYSTERIA2_LISTEN_PORT}")
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      listeners+=("hysteria2-acme-http:tcp:${HYSTERIA2_ACME_HTTP_PORT}")
    fi
  fi
  if enable_ss2022; then
    listeners+=("ss2022:tcp:${SS2022_LISTEN_PORT}")
    listeners+=("ss2022:udp:${SS2022_LISTEN_PORT}")
  fi

  local item name proto port key
  for item in "${listeners[@]}"; do
    IFS=: read -r name proto port <<<"${item}"
    key="${proto}:${port}"
    if [[ -n "${seen[${key}]:-}" ]]; then
      die "Port collision detected on ${proto^^}/${port} between ${seen[${key}]} and ${name}."
    fi
    seen["${key}"]="${name}"
  done
}

validate_protocol_settings() {
  if enable_vless_reality; then
    validate_tcp_port "${XRAY_LISTEN_PORT}" || die "Invalid XRAY_LISTEN_PORT '${XRAY_LISTEN_PORT}'. Use 1-65535."
    if [[ "${XRAY_LISTEN_PORT}" != "443" && "${ALLOW_NONSTANDARD_REALITY_PORT}" != "yes" ]]; then
      die "XRAY_LISTEN_PORT=${XRAY_LISTEN_PORT} is non-default. Set ALLOW_NONSTANDARD_REALITY_PORT=yes to confirm this higher-risk choice."
    fi
    if [[ "${VLESS_REALITY_ADVANCED_EDIT}" == "yes" || ! vless_reality_config_complete ]]; then
      REALITY_CANDIDATES="$(normalize_reality_candidates "${REALITY_CANDIDATES}")"
      [[ -n "${REALITY_CANDIDATES}" ]] || die "$(i18n_text error_reality_candidates_required)"
      if [[ "$(count_reality_candidates "${REALITY_CANDIDATES}")" -lt 2 ]]; then
        die "$(i18n_text error_reality_candidates_count)"
      fi
    elif [[ -n "${REALITY_CANDIDATES}" ]]; then
      REALITY_CANDIDATES="$(normalize_reality_candidates "${REALITY_CANDIDATES}")"
    fi
    if [[ -n "${REALITY_SELECTED_DOMAIN}" ]]; then
      REALITY_SELECTED_DOMAIN="$(normalize_reality_candidates "${REALITY_SELECTED_DOMAIN}")"
    fi
  fi

  if enable_hysteria2; then
    validate_udp_port "${HYSTERIA2_LISTEN_PORT}" || die "Invalid HYSTERIA2_LISTEN_PORT '${HYSTERIA2_LISTEN_PORT}'. Use 1-65535."
    [[ -n "${HYSTERIA2_DOMAIN}" ]] || die "HYSTERIA2_DOMAIN is required when ENABLE_HYSTERIA2=yes."
    case "${HYSTERIA2_TLS_MODE}" in
      acme|file) ;;
      *) die "HYSTERIA2_TLS_MODE must be acme or file." ;;
    esac
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
      [[ -n "${HYSTERIA2_ACME_EMAIL}" ]] || die "HYSTERIA2_ACME_EMAIL is required when HYSTERIA2_TLS_MODE=acme."
      [[ "${HYSTERIA2_ACME_EMAIL}" == *"@"* ]] || die "HYSTERIA2_ACME_EMAIL must look like an email address."
      [[ "${HYSTERIA2_ACME_DIR}" == /* ]] || die "HYSTERIA2_ACME_DIR must be an absolute path."
      [[ "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]] || die "Only HYSTERIA2_ACME_CHALLENGE_TYPE=http is supported by this repo."
      validate_tcp_port "${HYSTERIA2_ACME_HTTP_PORT}" || die "Invalid HYSTERIA2_ACME_HTTP_PORT '${HYSTERIA2_ACME_HTTP_PORT}'."
    else
      [[ "${HYSTERIA2_TLS_CERT_FILE}" == /* ]] || die "HYSTERIA2_TLS_CERT_FILE must be an absolute path."
      [[ "${HYSTERIA2_TLS_KEY_FILE}" == /* ]] || die "HYSTERIA2_TLS_KEY_FILE must be an absolute path."
      [[ -n "${HYSTERIA2_TLS_CERT_FILE}" && -n "${HYSTERIA2_TLS_KEY_FILE}" ]] || die "HYSTERIA2 TLS certificate and key files are required when HYSTERIA2_TLS_MODE=file."
    fi
    [[ -n "${HYSTERIA2_AUTH_PASSWORD}" ]] || die "HYSTERIA2_AUTH_PASSWORD is required when ENABLE_HYSTERIA2=yes."
    case "${HYSTERIA2_MASQUERADE_TYPE}" in
      proxy|none) ;;
      *) die "HYSTERIA2_MASQUERADE_TYPE must be proxy or none." ;;
    esac
    if [[ "${HYSTERIA2_MASQUERADE_TYPE}" == "proxy" ]]; then
      [[ "${HYSTERIA2_MASQUERADE_URL}" =~ ^https?:// ]] || die "HYSTERIA2_MASQUERADE_URL must start with http:// or https:// when proxy masquerade is enabled."
    fi
  fi

  if enable_ss2022; then
    validate_tcp_port "${SS2022_LISTEN_PORT}" || die "Invalid SS2022_LISTEN_PORT '${SS2022_LISTEN_PORT}'. Use 1-65535."
    case "${SS2022_METHOD}" in
      2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) ;;
      *) die "Unsupported SS2022_METHOD '${SS2022_METHOD}'." ;;
    esac
    [[ -n "${SS2022_PASSWORD}" ]] || die "SS2022_PASSWORD is required when ENABLE_SS2022=yes."
    if ! enable_time_sync; then
      warn "$(installer_text ss2022_clock_warning)"
    fi
  fi

  validate_listener_collisions
}

validate_runtime_config() {
  validate_ssh_port "${SSH_PORT}" || die "Invalid SSH port '${SSH_PORT}'. Use 1024-65535 and not 443."
  validate_public_key "${ADMIN_PUBLIC_KEY}" || die "Invalid SSH public key provided for admin user."
  [[ "${ENABLE_IPV6}" == "yes" || "${ENABLE_IPV6}" == "no" ]] || die "ENABLE_IPV6 must be yes or no."
  [[ "${ENABLE_BOT}" == "yes" || "${ENABLE_BOT}" == "no" ]] || die "ENABLE_BOT must be yes or no."
  [[ "${ENABLE_DOCKER_TESTS}" == "yes" || "${ENABLE_DOCKER_TESTS}" == "no" ]] || die "ENABLE_DOCKER_TESTS must be yes or no."
  [[ "${ENABLE_TIME_SYNC}" == "yes" || "${ENABLE_TIME_SYNC}" == "no" ]] || die "ENABLE_TIME_SYNC must be yes or no."
  [[ "${ENABLE_VLESS_REALITY}" == "yes" || "${ENABLE_VLESS_REALITY}" == "no" ]] || die "ENABLE_VLESS_REALITY must be yes or no."
  [[ "${ENABLE_HYSTERIA2}" == "yes" || "${ENABLE_HYSTERIA2}" == "no" ]] || die "ENABLE_HYSTERIA2 must be yes or no."
  [[ "${ENABLE_SS2022}" == "yes" || "${ENABLE_SS2022}" == "no" ]] || die "ENABLE_SS2022 must be yes or no."
  [[ "${XRAY_INSTALL_VERIFY_SHA256}" == "yes" || "${XRAY_INSTALL_VERIFY_SHA256}" == "no" ]] || die "XRAY_INSTALL_VERIFY_SHA256 must be yes or no."
  [[ "${BOT_LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || die "BOT_LOG_RETENTION_DAYS must be a non-negative integer."
  [[ "${BOT_LOG_MAX_BYTES}" =~ ^[0-9]+$ ]] || die "BOT_LOG_MAX_BYTES must be a non-negative integer."
  [[ -n "${REPO_SYNC_URL}" ]] || die "REPO_SYNC_URL must not be empty."
  [[ -n "${REPO_SYNC_BRANCH}" ]] || die "REPO_SYNC_BRANCH must not be empty."
  [[ "${REPO_SYNC_DIR}" == /* ]] || die "REPO_SYNC_DIR must be an absolute path."
  [[ "${REPO_SYNC_DIR}" != "/" ]] || die "REPO_SYNC_DIR must not be /."
  [[ -n "${XRAY_INSTALL_SCRIPT_URL}" ]] || die "XRAY_INSTALL_SCRIPT_URL must not be empty."
  if [[ "${XRAY_INSTALL_VERIFY_SHA256}" == "yes" ]]; then
    [[ -n "${XRAY_INSTALL_SCRIPT_SHA256}" ]] || die "XRAY_INSTALL_SCRIPT_SHA256 must not be empty when XRAY_INSTALL_VERIFY_SHA256=yes."
  fi
  UI_LANG="$(lang_normalize "${UI_LANG:-}")"
  UI_LANG="${UI_LANG:-en}"
  if [[ -n "${REPORT_TZ}" ]]; then
    validate_timezone "${REPORT_TZ}" || die "Invalid timezone '${REPORT_TZ}'."
  fi
  [[ "${REPORT_TIME}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || REPORT_TIME="08:00"
  [[ "${QUOTA_MONTHLY_CAP_GB}" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "QUOTA_MONTHLY_CAP_GB must be numeric."
  [[ "${QUOTA_RESET_DAY_UTC}" =~ ^[0-9]+$ ]] || die "QUOTA_RESET_DAY_UTC must be an integer."
  (( QUOTA_RESET_DAY_UTC >= 1 && QUOTA_RESET_DAY_UTC <= 28 )) || die "QUOTA_RESET_DAY_UTC must be between 1 and 28."
  [[ -n "${HYSTERIA2_VERSION}" ]] || die "HYSTERIA2_VERSION must not be empty."
  validate_protocol_settings
}

resolve_network_defaults() {
  NETWORK_INTERFACE="${NETWORK_INTERFACE:-$(detect_primary_interface)}"
  [[ -n "${NETWORK_INTERFACE}" ]] || die "Unable to determine the primary network interface."
  if [[ -z "${SERVER_PUBLIC_ENDPOINT}" ]]; then
    SERVER_PUBLIC_ENDPOINT="$(detect_public_ipv4 || true)"
  fi
  REPORT_TZ="${REPORT_TZ:-$(detect_default_timezone)}"
}

write_installed_config_file() {
  mkdir_root_only "${NEFLARE_CONFIG_DIR}"
  write_env_file "${NEFLARE_CONFIG_FILE}" \
    "CONFIG_VERSION=4" \
    "UI_LANG=${UI_LANG}" \
    "ADMIN_USER=${ADMIN_USER}" \
    "ADMIN_PUBLIC_KEY=${ADMIN_PUBLIC_KEY}" \
    "ADMIN_NOPASSWD_SUDO=${ADMIN_NOPASSWD_SUDO}" \
    "SSH_PORT=${SSH_PORT}" \
    "SSH_CUTOVER_CONFIRMED=${SSH_CUTOVER_CONFIRMED}" \
    "ENABLE_IPV6=${ENABLE_IPV6}" \
    "ALLOW_IPV6_DISABLE_FROM_IPV6=${ALLOW_IPV6_DISABLE_FROM_IPV6}" \
    "ENABLE_DOCKER_TESTS=${ENABLE_DOCKER_TESTS}" \
    "ENABLE_TIME_SYNC=${ENABLE_TIME_SYNC}" \
    "ENABLE_BOT=${ENABLE_BOT}" \
    "BOT_LOG_RETENTION_DAYS=${BOT_LOG_RETENTION_DAYS}" \
    "BOT_LOG_MAX_BYTES=${BOT_LOG_MAX_BYTES}" \
    "REPO_SYNC_URL=${REPO_SYNC_URL}" \
    "REPO_SYNC_BRANCH=${REPO_SYNC_BRANCH}" \
    "REPO_SYNC_DIR=${REPO_SYNC_DIR}" \
    "XRAY_INSTALL_SCRIPT_URL=${XRAY_INSTALL_SCRIPT_URL}" \
    "XRAY_INSTALL_SCRIPT_SHA256=${XRAY_INSTALL_SCRIPT_SHA256}" \
    "XRAY_INSTALL_VERIFY_SHA256=${XRAY_INSTALL_VERIFY_SHA256}" \
    "ENABLE_VLESS_REALITY=${ENABLE_VLESS_REALITY}" \
    "ENABLE_HYSTERIA2=${ENABLE_HYSTERIA2}" \
    "ENABLE_SS2022=${ENABLE_SS2022}" \
    "BOT_TOKEN=${BOT_TOKEN}" \
    "CHAT_ID=${CHAT_ID}" \
    "BOT_BIND_TOKEN=${BOT_BIND_TOKEN}" \
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
    "HYSTERIA2_VERSION=${HYSTERIA2_VERSION}" \
    "HYSTERIA2_DOMAIN=${HYSTERIA2_DOMAIN}" \
    "HYSTERIA2_LISTEN_PORT=${HYSTERIA2_LISTEN_PORT}" \
    "HYSTERIA2_TLS_MODE=${HYSTERIA2_TLS_MODE}" \
    "HYSTERIA2_ACME_EMAIL=${HYSTERIA2_ACME_EMAIL}" \
    "HYSTERIA2_ACME_DIR=${HYSTERIA2_ACME_DIR}" \
    "HYSTERIA2_ACME_CHALLENGE_TYPE=${HYSTERIA2_ACME_CHALLENGE_TYPE}" \
    "HYSTERIA2_ACME_HTTP_PORT=${HYSTERIA2_ACME_HTTP_PORT}" \
    "HYSTERIA2_TLS_CERT_FILE=${HYSTERIA2_TLS_CERT_FILE}" \
    "HYSTERIA2_TLS_KEY_FILE=${HYSTERIA2_TLS_KEY_FILE}" \
    "HYSTERIA2_AUTH_PASSWORD=${HYSTERIA2_AUTH_PASSWORD}" \
    "HYSTERIA2_MASQUERADE_TYPE=${HYSTERIA2_MASQUERADE_TYPE}" \
    "HYSTERIA2_MASQUERADE_URL=${HYSTERIA2_MASQUERADE_URL}" \
    "HYSTERIA2_MASQUERADE_REWRITE_HOST=${HYSTERIA2_MASQUERADE_REWRITE_HOST}" \
    "HYSTERIA2_MASQUERADE_INSECURE=${HYSTERIA2_MASQUERADE_INSECURE}" \
    "SS2022_LISTEN_PORT=${SS2022_LISTEN_PORT}" \
    "SS2022_METHOD=${SS2022_METHOD}" \
    "SS2022_PASSWORD=${SS2022_PASSWORD}" \
    "TEMP_ADMIN_ALLOW_V4=${TEMP_ADMIN_ALLOW_V4}" \
    "TEMP_ADMIN_ALLOW_V6=${TEMP_ADMIN_ALLOW_V6}" \
    "CREATED_ADMIN_USER=${CREATED_ADMIN_USER}"
  rm -f "${NEFLARE_BOT_STATE_DIR}/runtime.env"
  success "Saved configuration to ${NEFLARE_CONFIG_FILE}"
}

save_installed_config() {
  if bool_is_true "${DEFER_INSTALLED_CONFIG_SAVE:-0}"; then
    if ! bool_is_true "${DEFER_INSTALLED_CONFIG_SAVE_NOTIFIED:-0}"; then
      info "Deferring updates to ${NEFLARE_CONFIG_FILE} until the managed runtime passes verification."
      DEFER_INSTALLED_CONFIG_SAVE_NOTIFIED=1
    fi
    return 0
  fi
  write_installed_config_file
}

flush_deferred_installed_config() {
  local deferred="${DEFER_INSTALLED_CONFIG_SAVE:-0}"
  DEFER_INSTALLED_CONFIG_SAVE=0
  write_installed_config_file
  DEFER_INSTALLED_CONFIG_SAVE="${deferred}"
}

collect_install_config() {
  set_default_config
  load_installed_config_if_present
  capture_installed_config_snapshot
  load_user_config_file "${CONFIG_INPUT_FILE}"
  if [[ -n "${UI_LANG_RUNTIME_OVERRIDE:-}" ]]; then
    UI_LANG="$(lang_normalize "${UI_LANG_RUNTIME_OVERRIDE}")"
  fi
  if vless_reality_change_requested; then
    VLESS_REALITY_ADVANCED_EDIT="yes"
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
  if [[ "${ENABLE_BOT}" == "yes" && -n "${BOT_TOKEN}" && -z "${CHAT_ID}" && -z "${BOT_BIND_TOKEN}" ]]; then
    BOT_BIND_TOKEN="$(generate_hex 8)"
  fi
  validate_runtime_config
  save_installed_config
}
