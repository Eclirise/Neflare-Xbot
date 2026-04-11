#!/usr/bin/env bash

readonly NFTABLES_MAIN_FILE="/etc/nftables.conf"
readonly NFTABLES_CN_SET_FILE="${NEFLARE_CONFIG_DIR}/nftables-cn-ssh-sets.nft"
readonly NFTABLES_CN_METADATA_FILE="${NEFLARE_CONFIG_DIR}/nftables-cn-ssh-meta.json"
readonly NFTABLES_CN_LAST_GOOD_FILE="${NEFLARE_CONFIG_DIR}/nftables-cn-ssh-sets.last-good.nft"

empty_cn_set_content() {
  cat <<'EOF'
set cn_ssh_v4 {
    type ipv4_addr
    flags interval
    auto-merge
}
set cn_ssh_v6 {
    type ipv6_addr
    flags interval
    auto-merge
}
EOF
}

cn_set_file_has_legacy_empty_placeholder() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  local legacy_empty_lines
  legacy_empty_lines="$(grep -Ec '^[[:space:]]*elements[[:space:]]*=[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "${path}" || true)"
  [[ "${legacy_empty_lines}" -eq 2 ]] || return 1
  if grep -Eq '[0-9a-fA-F:.]+/[0-9]+' "${path}"; then
    return 1
  fi
  return 0
}

ensure_empty_cn_set_file() {
  if [[ ! -f "${NFTABLES_CN_SET_FILE}" ]]; then
    install_text "${NFTABLES_CN_SET_FILE}" "$(empty_cn_set_content)" 0600 root root
    return 0
  fi

  if [[ ! -s "${NFTABLES_CN_SET_FILE}" ]]; then
    install_text "${NFTABLES_CN_SET_FILE}" "$(empty_cn_set_content)" 0600 root root
    return 0
  fi

  if cn_set_file_has_legacy_empty_placeholder "${NFTABLES_CN_SET_FILE}"; then
    warn "Detected legacy empty CN SSH nftables set bootstrap file; rewriting it to the current syntax."
    install_text "${NFTABLES_CN_SET_FILE}" "$(empty_cn_set_content)" 0600 root root
  fi
}

nft_public_listener_rules() {
  local rules=()
  if enable_vless_reality; then
    rules+=("tcp dport ${XRAY_LISTEN_PORT} accept comment \"VLESS+REALITY\"")
  fi
  if enable_ss2022; then
    rules+=("tcp dport ${SS2022_LISTEN_PORT} accept comment \"Shadowsocks 2022 TCP\"")
    rules+=("udp dport ${SS2022_LISTEN_PORT} accept comment \"Shadowsocks 2022 UDP\"")
  fi
  if enable_hysteria2; then
    rules+=("udp dport ${HYSTERIA2_LISTEN_PORT} accept comment \"Hysteria 2\"")
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      rules+=("tcp dport ${HYSTERIA2_ACME_HTTP_PORT} accept comment \"Hysteria 2 ACME HTTP\"")
    fi
  fi
  if [[ "${#rules[@]}" -eq 0 ]]; then
    printf '\n'
  else
    printf '%s\n' "${rules[@]}"
  fi
}

render_nftables_main_file() {
  local destination="$1"
  ensure_empty_cn_set_file
  local ipv6_rule ipv6_icmp temp_v4 temp_v6 ipv6_geo_rule set_declarations public_listener_rules

  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    ipv6_rule=""
    ipv6_icmp='meta nfproto ipv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert, echo-request, echo-reply, mld-listener-query, mld-listener-report, mld-listener-done } accept'
    ipv6_geo_rule="ip6 saddr @cn_ssh_v6 tcp dport ${SSH_PORT} drop comment \"SSH CN IPv6 drop\""
  else
    ipv6_rule='meta nfproto ipv6 drop comment "IPv6 disabled by installer"'
    ipv6_icmp=''
    ipv6_geo_rule=''
  fi

  if [[ -n "${TEMP_ADMIN_ALLOW_V4}" ]]; then
    temp_v4="ip saddr ${TEMP_ADMIN_ALLOW_V4} tcp dport ${SSH_PORT} accept comment \"temporary admin IPv4 allow\""
  else
    temp_v4=""
  fi

  if [[ -n "${TEMP_ADMIN_ALLOW_V6}" && "${ENABLE_IPV6}" == "yes" ]]; then
    temp_v6="ip6 saddr ${TEMP_ADMIN_ALLOW_V6} tcp dport ${SSH_PORT} accept comment \"temporary admin IPv6 allow\""
  else
    temp_v6=""
  fi

  set_declarations="$(sed 's/^/    /' "${NFTABLES_CN_SET_FILE}")"
  public_listener_rules="$(nft_public_listener_rules | sed 's/^/        /')"

  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/nftables.conf.tpl" "${destination}" \
    "CN_SET_DECLARATIONS=${set_declarations}" \
    "SSH_PORT=${SSH_PORT}" \
    "IPV6_POLICY_RULE=${ipv6_rule}" \
    "IPV6_ICMP_RULE=${ipv6_icmp}" \
    "TEMP_ADMIN_ALLOW_V4_RULE=${temp_v4}" \
    "TEMP_ADMIN_ALLOW_V6_RULE=${temp_v6}" \
    "IPV6_SSH_GEO_RULE=${ipv6_geo_rule}" \
    "PUBLIC_LISTENER_RULES=${public_listener_rules}"
}

prepare_temp_admin_allow_if_needed() {
  TEMP_ADMIN_ALLOW_V4=""
  TEMP_ADMIN_ALLOW_V6=""
  [[ -n "${CURRENT_ADMIN_SOURCE_IP:-}" ]] || return 0
  if python3 "${NEFLARE_RUNTIME_LIB_DIR}/cn_ssh_geo_update.py" --contains-ip "${CURRENT_ADMIN_SOURCE_IP}" >/dev/null; then
    if [[ "${CURRENT_ADMIN_SOURCE_FAMILY}" == "6" && "${ENABLE_IPV6}" == "yes" ]]; then
      TEMP_ADMIN_ALLOW_V6="${CURRENT_ADMIN_SOURCE_IP}"
    elif [[ "${CURRENT_ADMIN_SOURCE_FAMILY}" == "4" ]]; then
      TEMP_ADMIN_ALLOW_V4="${CURRENT_ADMIN_SOURCE_IP}"
    fi
    warn "Current admin source ${CURRENT_ADMIN_SOURCE_IP} falls inside the CN SSH geo-block set. A temporary allow rule will be installed for migration safety."
  fi
}

validate_nftables_config_file() {
  local path="$1"
  nft -c -f "${path}"
}

apply_nftables_file() {
  local rendered_file="$1"
  snapshot_file_once "${NFTABLES_MAIN_FILE}"
  local previous
  previous="$(mktemp)"
  if [[ -f "${NFTABLES_MAIN_FILE}" ]]; then
    cp -a "${NFTABLES_MAIN_FILE}" "${previous}"
  else
    : > "${previous}"
  fi
  install_file_atomic "${rendered_file}" "${NFTABLES_MAIN_FILE}" 0644 root root
  if ! validate_nftables_config_file "${NFTABLES_MAIN_FILE}"; then
    warn "nftables validation failed; restoring previous ruleset"
    if [[ -s "${previous}" ]]; then
      cp -a "${previous}" "${NFTABLES_MAIN_FILE}"
    else
      rm -f "${NFTABLES_MAIN_FILE}"
    fi
    rm -f "${previous}"
    return 1
  fi

  if ! nft -f "${NFTABLES_MAIN_FILE}"; then
    warn "Applying nftables rules failed; restoring previous configuration"
    if [[ -s "${previous}" ]]; then
      cp -a "${previous}" "${NFTABLES_MAIN_FILE}"
      nft -f "${NFTABLES_MAIN_FILE}" || true
    else
      rm -f "${NFTABLES_MAIN_FILE}"
    fi
    rm -f "${previous}"
    return 1
  fi
  if ! systemctl enable --now nftables >/dev/null 2>&1; then
    warn "Failed to enable/start nftables after applying rules; restoring previous configuration"
    if [[ -s "${previous}" ]]; then
      cp -a "${previous}" "${NFTABLES_MAIN_FILE}"
      nft -f "${NFTABLES_MAIN_FILE}" || true
    else
      rm -f "${NFTABLES_MAIN_FILE}"
    fi
    systemctl enable --now nftables >/dev/null 2>&1 || true
    rm -f "${previous}"
    return 1
  fi
  rm -f "${previous}"
  success "nftables rules applied successfully"
}

configure_nftables_firewall() {
  ensure_empty_cn_set_file
  local rendered
  rendered="$(mktemp)"
  render_nftables_main_file "${rendered}"
  apply_nftables_file "${rendered}" || die "Failed to apply nftables rules."
  rm -f "${rendered}"
}

update_cn_ssh_geo_sets() {
  mkdir_root_only "${NEFLARE_LOCK_DIR}"
  exec 9>"${NEFLARE_LOCK_DIR}/cn-ssh-geo.lock"
  flock -n 9 || die "Another CN SSH geo-block update is already running."

  ensure_empty_cn_set_file
  snapshot_file_once "${NFTABLES_CN_SET_FILE}"
  snapshot_file_once "${NFTABLES_CN_METADATA_FILE}"

  local tmp_sets tmp_meta
  tmp_sets="$(mktemp)"
  tmp_meta="$(mktemp)"
  python3 "${NEFLARE_RUNTIME_LIB_DIR}/cn_ssh_geo_update.py" \
    --output "${tmp_sets}" \
    --metadata "${tmp_meta}"

  install_file_atomic "${tmp_sets}" "${NFTABLES_CN_SET_FILE}" 0600 root root
  install_file_atomic "${tmp_meta}" "${NFTABLES_CN_METADATA_FILE}" 0600 root root

  local rendered
  rendered="$(mktemp)"
  render_nftables_main_file "${rendered}"
  if ! validate_nftables_config_file "${rendered}"; then
    warn "Updated CN SSH geo sets failed validation; restoring last-known-good copy"
    rollback_paths "${NFTABLES_CN_SET_FILE}" "${NFTABLES_CN_METADATA_FILE}"
    rm -f "${tmp_sets}" "${tmp_meta}" "${rendered}"
    die "Updated CN SSH geo sets failed validation."
  fi
  if ! apply_nftables_file "${rendered}"; then
    warn "Failed to apply refreshed CN SSH geo sets; restoring last-known-good copy"
    rollback_paths "${NFTABLES_CN_SET_FILE}" "${NFTABLES_CN_METADATA_FILE}"
    rm -f "${tmp_sets}" "${tmp_meta}" "${rendered}"
    die "Failed to apply refreshed CN SSH geo sets."
  fi
  install_file_atomic "${NFTABLES_CN_SET_FILE}" "${NFTABLES_CN_LAST_GOOD_FILE}" 0600 root root
  rm -f "${tmp_sets}" "${tmp_meta}" "${rendered}"
  success "CN SSH geo-block sets updated successfully"
}

install_cn_ssh_geo_update_units() {
  mkdir_system_dir /etc/systemd/system 0755
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-cn-ssh-geo-update.service" "/etc/systemd/system/neflare-cn-ssh-geo-update.service" 0644 root root
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-cn-ssh-geo-update.timer" "/etc/systemd/system/neflare-cn-ssh-geo-update.timer" 0644 root root
  systemctl daemon-reload
  systemctl enable --now neflare-cn-ssh-geo-update.timer
}
