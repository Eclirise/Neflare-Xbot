#!/usr/bin/env bash

verify_os_support() {
  detect_supported_os >/dev/null
}

verify_ssh_state() {
  validate_sshd_config >/dev/null
  local active_port root_login password_auth
  active_port="$(sshd -T | awk '/^port / {print $2; exit}')"
  root_login="$(sshd -T | awk '/^permitrootlogin / {print $2; exit}')"
  password_auth="$(sshd -T | awk '/^passwordauthentication / {print $2; exit}')"
  [[ "${active_port}" == "${SSH_PORT}" ]] || die "sshd active port '${active_port}' does not match configured SSH_PORT '${SSH_PORT}'."
  [[ "${root_login}" == "no" ]] || die "PermitRootLogin is not disabled."
  [[ "${password_auth}" == "no" ]] || die "PasswordAuthentication is not disabled."
}

verify_firewall_state() {
  validate_nftables_config_file "${NFTABLES_MAIN_FILE}" >/dev/null
  systemctl is-active --quiet nftables || die "nftables service is not active."
  systemctl is-active --quiet neflare-cn-ssh-geo-update.timer || die "CN SSH geo-block update timer is not active."
  local ruleset
  ruleset="$(nft list ruleset)"
  grep -q "tcp dport ${SSH_PORT} accept" <<<"${ruleset}" || die "nftables does not allow SSH port ${SSH_PORT}."
  grep -q "tcp dport ${XRAY_LISTEN_PORT} accept" <<<"${ruleset}" || die "nftables does not allow REALITY port ${XRAY_LISTEN_PORT}."
  local drop_line accept_line
  drop_line="$(grep -n "SSH CN IPv4 drop" <<<"${ruleset}" | head -n 1 | cut -d: -f1)"
  accept_line="$(grep -n "SSH\"" <<<"${ruleset}" | head -n 1 | cut -d: -f1)"
  if [[ -n "${drop_line}" && -n "${accept_line}" ]]; then
    (( drop_line < accept_line )) || die "nftables rule ordering allows SSH before CN geo-drop."
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

verify_xray_state() {
  validate_xray_config_file "${XRAY_CONFIG_PATH}" >/dev/null
  systemctl is-active --quiet xray || die "xray service is not active."
  ss -lnt | grep -Eq "[[:space:]]:${XRAY_LISTEN_PORT}[[:space:]]" || die "No listener found on TCP/${XRAY_LISTEN_PORT}."
}

verify_reality_policy_state() {
  lint_current_reality_policy
}

verify_bbr_state() {
  if [[ "${BBR_STATUS:-unknown}" == "unsupported" ]]; then
    return 0
  fi
  [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" == "bbr" ]] || die "BBR is not active."
}

verify_bot_state() {
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    return 0
  fi
  if [[ -n "${BOT_TOKEN}" ]]; then
    systemctl is-active --quiet neflare-bot || die "neflare-bot service is not active."
  fi
}

run_full_verification() {
  verify_os_support
  verify_ssh_state
  verify_firewall_state
  verify_ipv6_state
  verify_xray_state
  verify_reality_policy_state
  verify_bbr_state
  verify_bot_state
  success "$(i18n_text verify_ok)"
}

print_cloud_firewall_guidance() {
  echo "$(i18n_text cloud_firewall_header)"
  echo "$(i18n_text provider_inbound_drop)"
  echo "$(i18n_text provider_outbound_accept)"
  printf '%s\n' "$(i18n_text provider_allow_xray "${XRAY_LISTEN_PORT}")"
  printf '%s\n' "$(i18n_text provider_allow_ssh "${SSH_PORT}")"
}

print_client_yaml_snippet() {
  cat <<EOF
- name: "neflare-reality"
  type: vless
  server: ${SERVER_PUBLIC_ENDPOINT}
  port: ${XRAY_LISTEN_PORT}
  uuid: ${XRAY_UUID}
  network: tcp
  tls: true
  udp: true
  packet-encoding: xudp
  flow: xtls-rprx-vision
  servername: ${REALITY_SERVER_NAME}
  client-fingerprint: chrome
  reality-opts:
    public-key: ${XRAY_PUBLIC_KEY}
    short-id: $(first_short_id)
EOF
}

print_policy_summary() {
  local policy_level apple_related unresolved public_port_status triggered
  public_port_status="$(i18n_bool no)"
  if [[ "${XRAY_LISTEN_PORT}" == "443" ]]; then
    public_port_status="$(i18n_bool yes)"
  fi
  policy_level="$(policy_state_field '.selected.policy.warning_level // empty')"
  apple_related="$(policy_state_field '.selected.policy.apple_related // false')"
  unresolved="$(policy_state_field '(.selected.policy.unresolved_warnings // []) | join("; ")')"
  triggered="$(i18n_bool no)"
  if [[ -n "${policy_level}" && "${policy_level}" != "none" && "${policy_level}" != "null" ]]; then
    triggered="$(i18n_bool yes)"
  fi
  if [[ -z "${policy_level}" || "${policy_level}" == "null" ]]; then
    if [[ "$(current_ui_lang)" == "zh" ]]; then
      policy_level="未知"
    else
      policy_level="unknown"
    fi
  elif [[ "$(current_ui_lang)" == "zh" ]]; then
    case "${policy_level}" in
      none) policy_level="无" ;;
      "soft warning") policy_level="轻度告警" ;;
      "strong warning") policy_level="强告警" ;;
      "hard failure") policy_level="硬失败" ;;
    esac
  fi
  apple_related="$(i18n_bool "$(normalize_yes_no "${apple_related}")")"
  if [[ -z "${unresolved}" || "${unresolved}" == "null" ]]; then
    unresolved="$(i18n_none)"
  fi
  echo "$(i18n_text policy_header)"
  printf '%s\n' "$(i18n_text policy_port443 "${public_port_status}")"
  printf '%s\n' "$(i18n_text policy_ipv6 "$(i18n_bool "${ENABLE_IPV6}")")"
  printf '%s\n' "$(i18n_text policy_triggered "${triggered}")"
  printf '%s\n' "$(i18n_text policy_level "${policy_level}")"
  printf '%s\n' "$(i18n_text policy_apple "${apple_related}")"
  printf '%s\n' "$(i18n_text policy_unresolved "${unresolved}")"
}

summary_heading() {
  local key="$1"
  echo "$(i18n_text "${key}")"
}

summary_line_done() {
  echo "- $1"
}

print_final_summary_lists() {
  if [[ "$(current_ui_lang)" == "zh" ]]; then
    summary_heading summary_done
    echo "- 已显式限制仅支持 Debian ${DISTRO_VERSION_ID}"
    echo "- SSH 已迁移到持久化端口 ${SSH_PORT}，并关闭 root 与密码登录"
    echo "- nftables 已启用入站默认拒绝，仅放行 TCP/${XRAY_LISTEN_PORT} 和 SSH"
    if [[ "${ENABLE_IPV6}" == "yes" ]]; then
      echo "- IPv6 已启用并配置显式防火墙策略"
    else
      echo "- IPv6 已通过 sysctl 和防火墙显式禁用"
    fi
    echo "- Xray VLESS + REALITY 已配置在 TCP/RAW ${XRAY_LISTEN_PORT}"
    echo "- 已完成 REALITY 候选测试并选定 ${REALITY_SELECTED_DOMAIN}"
    echo "- 已部署基于 APNIC 的 CN SSH geo-block 更新器"
    echo "- 已启用基于 vnStat 的日报与配额统计能力"
    if [[ "${ENABLE_BOT}" == "yes" ]]; then
      echo "- 已部署可选 Telegram Bot"
    fi

    summary_heading summary_not_done
    echo "- 未实现云厂商控制台防火墙自动化"
    echo "- 未实现 APNIC 完整签名信任链校验"
    if [[ "${ENABLE_BOT}" != "yes" ]]; then
      echo "- 未启用 Telegram Bot"
    fi
    if [[ -n "${TEMP_ADMIN_ALLOW_V4}${TEMP_ADMIN_ALLOW_V6}" ]]; then
      echo "- 尚未清理临时管理员放行规则"
    fi

    summary_heading summary_limitations
    echo "- CN SSH 阻断基于 APNIC 分配数据，不是商业级精确地理库"
    echo "- REALITY 适配评分属于保守启发式，网络或目标变化后应重新测试"
    if [[ "${XRAY_LISTEN_PORT}" != "443" ]]; then
      echo "- 公网 REALITY 监听端口不是 443，本项目将其视为更高风险的运维选择"
    fi
    if [[ "${ENABLE_IPV6}" == "no" ]]; then
      echo "- 公网 IPv6 连通性被有意禁用"
    fi

    summary_heading summary_manual
    echo "- 在云厂商面板中放行 TCP/${XRAY_LISTEN_PORT} 和 TCP/${SSH_PORT}"
    echo "- 从新终端验证 ${ADMIN_USER}@${SERVER_PUBLIC_ENDPOINT}:${SSH_PORT} 的 SSH 登录"
    if [[ "${ENABLE_BOT}" == "yes" && -z "${BOT_TOKEN}" ]]; then
      echo "- 在 ${BOT_ENV_FILE} 中补充 BOT_TOKEN 和可选的 CHAT_ID，然后启动 neflare-bot"
    fi
    if [[ -n "${TEMP_ADMIN_ALLOW_V4}${TEMP_ADMIN_ALLOW_V6}" ]]; then
      echo "- 不再需要迁移保护后，删除临时管理员放行规则"
    fi
    return 0
  fi

  summary_heading summary_done
  summary_line_done "Debian ${DISTRO_VERSION_ID} support with explicit Debian-only detection"
  summary_line_done "Hardened SSH on persisted port ${SSH_PORT} with root/password login disabled"
  summary_line_done "nftables default-drop inbound policy with TCP/${XRAY_LISTEN_PORT} and SSH allowances only"
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    summary_line_done "Explicit IPv6 firewall policy enabled"
  else
    summary_line_done "IPv6 explicitly disabled with sysctl and firewall enforcement"
  fi
  summary_line_done "Xray VLESS + REALITY configured on TCP/RAW ${XRAY_LISTEN_PORT}"
  summary_line_done "REALITY camouflage candidate testing and selected target ${REALITY_SELECTED_DOMAIN}"
  summary_line_done "CN SSH geo-block updater deployed with APNIC-based sets"
  summary_line_done "vnStat-backed daily/quota reporting support"
  if [[ "${ENABLE_BOT}" == "yes" ]]; then
    summary_line_done "Optional Telegram bot deployed"
  fi

  summary_heading summary_not_done
  echo "- Provider control-plane firewall automation"
  echo "- Full APNIC signature trust-chain verification"
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    echo "- Telegram bot enablement"
  fi
  if [[ -n "${TEMP_ADMIN_ALLOW_V4}${TEMP_ADMIN_ALLOW_V6}" ]]; then
    echo "- Temporary admin firewall allow cleanup"
  fi

  summary_heading summary_limitations
  echo "- CN SSH blocking is allocation-based from APNIC delegated data, not commercial geolocation"
  echo "- REALITY suitability scoring is heuristic and should be re-tested after major network or target changes"
  if [[ "${XRAY_LISTEN_PORT}" != "443" ]]; then
    echo "- Public REALITY listener is not on 443, which this project treats as a higher-risk operational choice"
  fi
  if [[ "${ENABLE_IPV6}" == "no" ]]; then
    echo "- Public IPv6 connectivity is intentionally disabled"
  fi

  summary_heading summary_manual
  echo "- Apply matching provider-panel firewall rules for TCP/${XRAY_LISTEN_PORT} and TCP/${SSH_PORT}"
  echo "- Verify a fresh SSH session to ${ADMIN_USER}@${SERVER_PUBLIC_ENDPOINT} on port ${SSH_PORT}"
  if [[ "${ENABLE_BOT}" == "yes" && -z "${BOT_TOKEN}" ]]; then
    echo "- Populate BOT_TOKEN and optionally CHAT_ID in ${BOT_ENV_FILE}, then start neflare-bot"
  fi
  if [[ -n "${TEMP_ADMIN_ALLOW_V4}${TEMP_ADMIN_ALLOW_V6}" ]]; then
    echo "- Remove temporary admin allow entries after you no longer need migration safety access"
  fi
}
