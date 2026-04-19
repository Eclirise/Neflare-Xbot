#!/usr/bin/env bash

verify_os_support() {
  detect_supported_os >/dev/null
}

verify_ssh_state() {
  validate_sshd_config >/dev/null || die "sshd configuration validation failed."
  local active_port root_login password_auth sshd_effective
  sshd_effective="$("$(sshd_binary_path)" -T)" || die "Failed to read effective sshd configuration."
  active_port="$(awk '/^port / {print $2; exit}' <<<"${sshd_effective}")"
  [[ "${active_port}" == "${SSH_PORT}" ]] || die "sshd active port '${active_port}' does not match configured SSH_PORT '${SSH_PORT}'."
  if ! manage_ssh_hardening; then
    return 0
  fi
  root_login="$(awk '/^permitrootlogin / {print $2; exit}' <<<"${sshd_effective}")"
  password_auth="$(awk '/^passwordauthentication / {print $2; exit}' <<<"${sshd_effective}")"
  [[ "${root_login}" == "no" ]] || die "PermitRootLogin is not disabled."
  [[ "${password_auth}" == "no" ]] || die "PasswordAuthentication is not disabled."
}

verify_firewall_state() {
  validate_nftables_config_file "${NFTABLES_MAIN_FILE}" >/dev/null || die "nftables configuration validation failed for ${NFTABLES_MAIN_FILE}."
  systemctl is-active --quiet nftables || die "nftables service is not active."
  if enable_ssh_geo_block; then
    systemctl is-active --quiet neflare-cn-ssh-geo-update.timer || die "CN SSH geo-block update timer is not active."
  fi
  local ruleset
  ruleset="$(nft list ruleset)" || die "Failed to read active nftables ruleset."
  nft_ruleset_allows_dport tcp "${SSH_PORT}" || die "nftables does not effectively allow SSH port ${SSH_PORT}."
  if enable_vless_reality; then
    nft_ruleset_allows_dport tcp "${XRAY_LISTEN_PORT}" || die "nftables does not effectively allow VLESS+REALITY port ${XRAY_LISTEN_PORT}."
  fi
  if enable_ss2022; then
    nft_ruleset_allows_dport tcp "${SS2022_LISTEN_PORT}" || die "nftables does not effectively allow Shadowsocks 2022 TCP/${SS2022_LISTEN_PORT}."
    nft_ruleset_allows_dport udp "${SS2022_LISTEN_PORT}" || die "nftables does not effectively allow Shadowsocks 2022 UDP/${SS2022_LISTEN_PORT}."
  fi
  if enable_hysteria2; then
    nft_ruleset_allows_dport udp "${HYSTERIA2_LISTEN_PORT}" || die "nftables does not effectively allow Hysteria 2 UDP/${HYSTERIA2_LISTEN_PORT}."
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      nft_ruleset_allows_dport tcp "${HYSTERIA2_ACME_HTTP_PORT}" || die "nftables does not effectively allow Hysteria 2 ACME TCP/${HYSTERIA2_ACME_HTTP_PORT}."
    fi
  fi
  if enable_ssh_geo_block; then
    local drop_line accept_line
    drop_line="$(grep -n -m1 "SSH CN IPv4 drop" <<<"${ruleset}" | cut -d: -f1 || true)"
    accept_line="$(grep -n -m1 'SSH"' <<<"${ruleset}" | cut -d: -f1 || true)"
    if [[ -n "${drop_line}" && -n "${accept_line}" ]]; then
      (( drop_line < accept_line )) || die "nftables rule ordering allows SSH before CN geo-drop."
    fi
  fi
}

verify_ipv6_state() {
  local current
  current="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || printf '0')"
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    [[ "${current}" == "0" ]] || die "IPv6 was expected to be enabled but disable_ipv6=${current}."
  else
    [[ "${current}" == "1" ]] || die "IPv6 was expected to be disabled but disable_ipv6=${current}."
  fi
}

verify_time_sync_state() {
  if ! enable_time_sync; then
    return 0
  fi
  time_sync_supported || die "timedatectl/systemctl is unavailable for time sync verification."
  [[ -f "${TIME_SYNC_SERVICE_UNIT}" ]] || die "${TIME_SYNC_SERVICE_UNIT} is missing."
  [[ -f "${TIME_SYNC_TIMER_UNIT}" ]] || die "${TIME_SYNC_TIMER_UNIT} is missing."
  systemctl is-active --quiet neflare-time-sync.timer || die "neflare-time-sync.timer is not active."
  systemctl is-enabled --quiet neflare-time-sync.timer || die "neflare-time-sync.timer is not enabled at boot."
  time_sync_ntp_enabled || die "Automatic NTP synchronization is not enabled."
  if ! time_sync_synchronized; then
    if enable_ss2022; then
      die "System clock is not reported as synchronized, which is unsafe for Shadowsocks 2022 replay protection."
    fi
    warn "System clock is not reported as synchronized yet; periodic maintenance is enabled and will retry."
  fi
}

verify_xray_state() {
  if ! xray_features_enabled; then
    return 0
  fi
  assert_xray_runtime_ready "${XRAY_CONFIG_PATH}" yes
}

verify_ss2022_reachability_state() {
  if ! enable_ss2022; then
    return 0
  fi
  tcp_inbound_namespace_probe_supported || die "Shadowsocks 2022 TCP reachability probing requires ip, timeout, and python3."
  probe_tcp_listener_via_namespace "${SS2022_LISTEN_PORT}" || die "Shadowsocks 2022 TCP/${SS2022_LISTEN_PORT} did not complete an inbound TCP handshake through nftables."
}

verify_hysteria2_state() {
  if ! enable_hysteria2; then
    return 0
  fi
  validate_hysteria2_config_file "${HYSTERIA2_CONFIG_PATH}"
  systemctl is-active --quiet neflare-hysteria2 || die "neflare-hysteria2 service is not active."
  systemctl is-enabled --quiet neflare-hysteria2 || die "neflare-hysteria2 service is not enabled at boot."
  ss -H -lun "( sport = :${HYSTERIA2_LISTEN_PORT} )" | grep -q . || die "No listener found on UDP/${HYSTERIA2_LISTEN_PORT} for Hysteria 2."
}

verify_reality_policy_state() {
  if enable_vless_reality; then
    lint_current_reality_policy || die "REALITY policy linting failed."
  fi
}

verify_bbr_state() {
  if [[ "${BBR_STATUS:-unknown}" == "unsupported" ]]; then
    return 0
  fi
  [[ -f "${BBR_MODULE_FILE}" ]] || die "BBR module load file is missing."
  [[ -f "${BBR_SYSCTL_FILE}" ]] || die "BBR sysctl file is missing."
  [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" == "bbr" ]] || die "BBR is not active."
  [[ "$(sysctl -n net.core.default_qdisc 2>/dev/null || true)" == "fq" ]] || die "default_qdisc is not fq."
}

verify_docker_tests_state() {
  if [[ "${ENABLE_DOCKER_TESTS:-no}" != "yes" ]]; then
    return 0
  fi
  docker_cli_path >/dev/null 2>&1 || die "docker CLI is not installed."
  systemctl is-active --quiet docker || die "docker service is not active."
  systemctl is-enabled --quiet docker || die "docker service is not enabled at boot."
  wait_for_docker_daemon 60 || die "docker daemon is not reachable."
  python3 - /etc/docker/daemon.json <<'PY' || die "docker daemon.json is missing the required disposable-test restrictions."
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(1)
payload = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(payload, dict):
    raise SystemExit(1)
required = {
    "bridge": "none",
    "iptables": False,
    "ip6tables": False,
}
for key, value in required.items():
    if payload.get(key) != value:
        raise SystemExit(1)
PY
}

verify_bot_state() {
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    return 0
  fi
  if [[ -n "${BOT_TOKEN}" ]]; then
    systemctl is-active --quiet neflare-bot || die "neflare-bot service is not active."
    systemctl is-enabled --quiet neflare-bot || die "neflare-bot service is not enabled at boot."
  fi
  if systemctl is-active --quiet neflare-reality-lint-watch.timer; then
    die "neflare-reality-lint-watch.timer should not be active."
  fi
}

run_full_verification() {
  verify_os_support
  verify_ssh_state
  verify_firewall_state
  verify_ipv6_state
  verify_time_sync_state
  verify_xray_state
  verify_ss2022_reachability_state
  verify_hysteria2_state
  verify_reality_policy_state
  verify_bbr_state
  verify_docker_tests_state
  verify_bot_state
  success "$(i18n_text verify_ok)"
}

print_cloud_firewall_guidance() {
  echo "Provider firewall manual rules:"
  echo "- Inbound default: DROP"
  echo "- Outbound default: ACCEPT"
  if manage_ssh_hardening; then
    echo "- Allow TCP/$(effective_ssh_public_port) from your admin source(s)"
  else
    echo "- Allow TCP/$(effective_ssh_public_port) according to your existing SSH access policy"
  fi
  if enable_vless_reality; then
    echo "- Allow TCP/${XRAY_LISTEN_PORT} from anywhere for VLESS+REALITY"
  fi
  if enable_ss2022; then
    echo "- Allow TCP/${SS2022_LISTEN_PORT} from anywhere for Shadowsocks 2022"
    echo "- Allow UDP/${SS2022_LISTEN_PORT} from anywhere for Shadowsocks 2022"
  fi
  if enable_hysteria2; then
    echo "- Allow UDP/${HYSTERIA2_LISTEN_PORT} from anywhere for Hysteria 2"
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      echo "- Allow TCP/${HYSTERIA2_ACME_HTTP_PORT} from anywhere for Hysteria 2 ACME HTTP-01"
    fi
  fi
}

hydrate_client_snippet_defaults() {
  if [[ -z "${SERVER_PUBLIC_ENDPOINT}" ]]; then
    SERVER_PUBLIC_ENDPOINT="$(detect_public_ipv4 || true)"
  fi

  if enable_ss2022 && [[ -z "${SS2022_PASSWORD}" ]] && [[ -f "${XRAY_CONFIG_PATH}" ]]; then
    SS2022_PASSWORD="$(
      jq -r \
        --argjson port "${SS2022_LISTEN_PORT}" \
        '
        [
          .inbounds[]?
          | select(.protocol == "shadowsocks" and (.port | tonumber) == $port)
          | .settings.password // empty
        ][0] // empty
        ' \
        "${XRAY_CONFIG_PATH}" 2>/dev/null
    )"
  fi
}

print_client_yaml_snippet() {
  if ! enable_vless_reality && ! enable_hysteria2 && ! enable_ss2022; then
    echo "# No proxy protocols are enabled; no Clash Meta snippet is available."
    return 0
  fi
  if xray_features_enabled; then
    assert_xray_runtime_ready "${XRAY_CONFIG_PATH}" no
  fi
  hydrate_client_snippet_defaults

  cat <<EOF
proxies:
EOF

  if enable_vless_reality; then
    cat <<EOF
  - name: "${CLIENT_PROXY_NAME_VLESS:-neflare-reality}"
    type: vless
    server: ${SERVER_PUBLIC_ENDPOINT}
    port: ${XRAY_LISTEN_PORT}
    uuid: ${XRAY_UUID}
    network: tcp
    tls: true
    udp: true
    packet-encoding: xudp
    flow: xtls-rprx-vision
    encryption: ""
    servername: ${REALITY_SERVER_NAME}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${XRAY_PUBLIC_KEY}
      short-id: $(first_short_id)
EOF
  fi

  if enable_hysteria2; then
    cat <<EOF
  - name: "${CLIENT_PROXY_NAME_HYSTERIA2:-neflare-hysteria2}"
    type: hysteria2
    server: ${SERVER_PUBLIC_ENDPOINT}
    port: ${HYSTERIA2_LISTEN_PORT}
    password: ${HYSTERIA2_AUTH_PASSWORD}
    sni: ${HYSTERIA2_DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3
EOF
  fi

  if enable_ss2022; then
    cat <<EOF
  - name: "${CLIENT_PROXY_NAME_SS2022:-neflare-ss2022}"
    type: ss
    server: ${SERVER_PUBLIC_ENDPOINT}
    port: ${SS2022_LISTEN_PORT}
    cipher: ${SS2022_METHOD}
    password: ${SS2022_PASSWORD}
    udp: true
EOF
  fi
}

print_policy_summary() {
  if ! enable_vless_reality; then
    echo "Policy summary:"
    echo "- VLESS+REALITY is disabled."
    return 0
  fi

  local policy_level apple_related unresolved public_port_status triggered
  public_port_status="no"
  if [[ "${XRAY_LISTEN_PORT}" == "443" ]]; then
    public_port_status="yes"
  fi
  policy_level="$(policy_state_field '.selected.policy.warning_level // empty')"
  apple_related="$(policy_state_field '.selected.policy.apple_related // false')"
  unresolved="$(policy_state_field '(.selected.policy.unresolved_warnings // []) | join("; ")')"
  triggered="no"
  if [[ -n "${policy_level}" && "${policy_level}" != "none" && "${policy_level}" != "null" ]]; then
    triggered="yes"
  fi
  if [[ -z "${policy_level}" || "${policy_level}" == "null" ]]; then
    policy_level="unknown"
  fi
  if [[ -z "${unresolved}" || "${unresolved}" == "null" ]]; then
    unresolved="none"
  fi
  echo "Policy summary:"
  echo "- Public REALITY port is 443: ${public_port_status}"
  echo "- IPv6 mode: ${ENABLE_IPV6}"
  echo "- Selected camouflage target triggered operational-risk warnings: ${triggered}"
  echo "- Selected camouflage target warning level: ${policy_level}"
  echo "- Selected target is Apple/iCloud-related: ${apple_related}"
  echo "- Unresolved conservative warnings: ${unresolved}"
}

summary_heading() {
  echo "$1"
}

summary_line_done() {
  echo "- $1"
}

print_final_summary_lists() {
  summary_heading "Done:"
  summary_line_done "Debian ${DISTRO_VERSION_ID} support with explicit Debian-only detection"
  if manage_ssh_hardening; then
    summary_line_done "Hardened SSH on persisted port $(effective_ssh_public_port) with root/password login disabled"
  else
    summary_line_done "Left existing SSH configuration unchanged on local TCP/${SSH_PORT} (public TCP/$(effective_ssh_public_port))"
  fi
  summary_line_done "nftables default-drop inbound policy with only the enabled listener set allowed"
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    summary_line_done "Explicit IPv6 firewall policy enabled"
  else
    summary_line_done "IPv6 explicitly disabled with sysctl and firewall enforcement"
  fi
  if enable_time_sync; then
    summary_line_done "Periodic time synchronization watchdog enabled"
  fi
  summary_line_done "Enabled protocols: $(protocols_enabled_summary)"
  if enable_vless_reality; then
    summary_line_done "VLESS+REALITY configured on TCP/${XRAY_LISTEN_PORT}"
    summary_line_done "REALITY selected target ${REALITY_SELECTED_DOMAIN}"
  fi
  if enable_ss2022; then
    summary_line_done "Shadowsocks 2022 configured on TCP/UDP ${SS2022_LISTEN_PORT}"
  fi
  if enable_hysteria2; then
    summary_line_done "Hysteria 2 configured as a separate service on UDP/${HYSTERIA2_LISTEN_PORT}"
  fi
  if enable_ssh_geo_block; then
    summary_line_done "CN SSH geo-block updater deployed with APNIC-based sets"
  else
    summary_line_done "CN SSH geo-block updater disabled by configuration"
  fi
  summary_line_done "vnStat-backed daily/quota reporting support"
  if [[ "${ENABLE_BOT}" == "yes" ]]; then
    summary_line_done "Optional Telegram bot deployed"
  fi
  if [[ "${ENABLE_DOCKER_TESTS:-no}" == "yes" ]]; then
    summary_line_done "Disposable Docker-backed network test runtime enabled"
  fi

  echo
  summary_heading "Manual follow-up steps:"
  echo "- Review the provider firewall rules above."
  if [[ "${ENABLE_BOT}" == "yes" && -z "${BOT_TOKEN}" ]]; then
    echo "- Populate BOT_TOKEN and optionally CHAT_ID in ${BOT_ENV_FILE}, then start neflare-bot."
  fi
  if [[ "${ENABLE_BOT}" == "yes" && -n "${BOT_TOKEN}" && -z "${CHAT_ID}" ]]; then
    echo "- Send /start to the bot, review chat candidates, then claim the bot with /claim ${BOT_BIND_TOKEN}."
  fi
  if enable_hysteria2 && [[ "${HYSTERIA2_TLS_MODE}" == "acme" ]]; then
    echo "- Make sure DNS for ${HYSTERIA2_DOMAIN} points to this server before the Hysteria 2 ACME flow runs."
  fi
}
