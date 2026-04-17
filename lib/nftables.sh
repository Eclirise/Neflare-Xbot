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
  if [[ "${#rules[@]}" -gt 0 ]]; then
    printf '%s\n' "${rules[@]}"
  fi
}

nft_input_allow_rules() {
  local rules=(
    "tcp dport ${SSH_PORT} accept comment \"SSH\""
  )
  local listener_rule
  while IFS= read -r listener_rule; do
    [[ -n "${listener_rule}" ]] || continue
    rules+=("${listener_rule}")
  done < <(nft_public_listener_rules)
  printf '%s\n' "${rules[@]}"
}

render_nftables_main_file() {
  local destination="$1"
  ensure_empty_cn_set_file
  local ipv6_rule ipv6_icmp temp_v4 temp_v6 ipv6_geo_rule set_declarations input_allow_rules

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
  input_allow_rules="$(nft_input_allow_rules | sed 's/^/        /')"

  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/nftables.conf.tpl" "${destination}" \
    "CN_SET_DECLARATIONS=${set_declarations}" \
    "SSH_PORT=${SSH_PORT}" \
    "IPV6_POLICY_RULE=${ipv6_rule}" \
    "IPV6_ICMP_RULE=${ipv6_icmp}" \
    "TEMP_ADMIN_ALLOW_V4_RULE=${temp_v4}" \
    "TEMP_ADMIN_ALLOW_V6_RULE=${temp_v6}" \
    "IPV6_SSH_GEO_RULE=${ipv6_geo_rule}" \
    "INPUT_ALLOW_RULES=${input_allow_rules}"
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

nft_ruleset_text_allows_dport() {
  local protocol="$1"
  local port="$2"
  local family="${3:-ip}"
  local chain_text line normalized verdict policy
  chain_text="$(nft list chain inet neflare input 2>/dev/null)" || return 1
  policy="drop"
  while IFS= read -r line; do
    normalized="$(normalize_nft_rule_text "${line}")"
    [[ -n "${normalized}" ]] || continue
    if [[ "${normalized}" == type\ filter\ hook\ input* ]]; then
      if [[ "${normalized}" =~ policy[[:space:]]+([a-z]+) ]]; then
        policy="${BASH_REMATCH[1]}"
      fi
      continue
    fi
    verdict="$(nft_rule_verdict_text "${normalized}" || true)"
    [[ -n "${verdict}" ]] || continue
    nft_rule_matches_inbound_listener_text "${line}" "${protocol}" "${port}" "${family}" || continue
    [[ "${verdict}" == "accept" ]]
    return
  done <<<"${chain_text}"
  [[ "${policy}" == "accept" ]]
}

nft_ruleset_allows_dport() {
  local protocol="$1"
  local port="$2"
  nft_ruleset_text_allows_dport "${protocol}" "${port}" ip
}

normalize_nft_rule_text() {
  local line="$1"
  line="${line%% comment *}"
  line="${line//\{/ }"
  line="${line//\}/ }"
  line="${line//;/ }"
  line="${line//,/ }"
  line="$(tr -s '[:space:]' ' ' <<<"${line}")"
  line="$(trim "${line}")"
  printf '%s\n' "${line}"
}

nft_rule_verdict_text() {
  local line="$1"
  if [[ "${line}" =~ (^|[[:space:]])accept([[:space:]]|$) ]]; then
    printf 'accept\n'
    return 0
  fi
  if [[ "${line}" =~ (^|[[:space:]])drop([[:space:]]|$) ]]; then
    printf 'drop\n'
    return 0
  fi
  if [[ "${line}" =~ (^|[[:space:]])reject([[:space:]]|$) ]]; then
    printf 'reject\n'
    return 0
  fi
  return 1
}

nft_rule_matches_inbound_listener_text() {
  local raw_line="$1"
  local protocol="$2"
  local port="$3"
  local family="${4:-ip}"
  local line
  line="$(normalize_nft_rule_text "${raw_line}")"
  [[ -n "${line}" ]] || return 1

  case "${line}" in
    chain\ *|table\ *|type\ filter\ hook\ input*|'{'|'}') return 1 ;;
  esac

  if [[ "${line}" == *'iif "lo"'* || "${line}" == *"iif lo"* ]]; then
    return 1
  fi

  if [[ "${line}" == *"ct state"* ]]; then
    if [[ "${line}" == *"invalid"* ]]; then
      return 1
    fi
    if [[ "${line}" == *"established"* || "${line}" == *"related"* ]]; then
      [[ "${line}" == *"new"* ]] || return 1
    fi
  fi

  if [[ "${family}" == "ip" ]]; then
    [[ "${line}" == *"meta nfproto ipv6"* ]] && return 1
    [[ "${line}" == ip6\ * || "${line}" == *" ip6 "* ]] && return 1
    [[ "${line}" == *"icmpv6"* ]] && return 1
  else
    [[ "${line}" == *"meta nfproto ipv4"* ]] && return 1
    if [[ "${line}" == ip\ * || "${line}" == *" ip saddr "* || "${line}" == *" ip daddr "* || "${line}" == *" ip protocol "* ]]; then
      return 1
    fi
    [[ "${line}" == *" icmp type "* || "${line}" == ip\ protocol\ icmp* ]] && return 1
  fi

  # Generic listener checks should only consider rules that broadly expose a
  # port, not address-scoped allow/drop rules such as CN SSH geo-blocking.
  if [[ "${line}" == ip\ saddr\ * || "${line}" == *" ip saddr "* || "${line}" == *" ip daddr "* ]]; then
    return 1
  fi
  if [[ "${line}" == ip6\ saddr\ * || "${line}" == *" ip6 saddr "* || "${line}" == *" ip6 daddr "* ]]; then
    return 1
  fi

  case "${protocol}" in
    tcp)
      [[ "${line}" == *"udp dport"* || "${line}" == *"udp sport"* ]] && return 1
      [[ "${line}" == *"ip protocol icmp"* || "${line}" == *"icmpv6 type"* ]] && return 1
      ;;
    udp)
      [[ "${line}" == *"tcp dport"* || "${line}" == *"tcp sport"* ]] && return 1
      [[ "${line}" == *"ip protocol icmp"* || "${line}" == *"icmpv6 type"* ]] && return 1
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "${line}" == *"dport"* ]]; then
    [[ "${line}" =~ (^|[[:space:]])${protocol}[[:space:]]+dport[[:space:]]+${port}([[:space:]]|$) ]] || return 1
  fi

  return 0
}

tcp_inbound_namespace_probe_supported() {
  command_exists ip && command_exists python3 && command_exists timeout
}

probe_tcp_listener_via_namespace() {
  local port="$1"
  local timeout_seconds="${2:-5}"
  local suffix host_if ns_if ns_name status
  tcp_inbound_namespace_probe_supported || return 1

  suffix="$(printf '%05d' "$((RANDOM % 100000))")"
  host_if="nfh${suffix}"
  ns_if="nfn${suffix}"
  ns_name="neflare-probe-${suffix}"
  status=1

  if ip netns add "${ns_name}" >/dev/null 2>&1 \
    && ip link add "${host_if}" type veth peer name "${ns_if}" >/dev/null 2>&1 \
    && ip link set "${ns_if}" netns "${ns_name}" >/dev/null 2>&1 \
    && ip addr add 198.18.0.1/30 dev "${host_if}" >/dev/null 2>&1 \
    && ip link set "${host_if}" up >/dev/null 2>&1 \
    && ip netns exec "${ns_name}" ip link set lo up >/dev/null 2>&1 \
    && ip netns exec "${ns_name}" ip addr add 198.18.0.2/30 dev "${ns_if}" >/dev/null 2>&1 \
    && ip netns exec "${ns_name}" ip link set "${ns_if}" up >/dev/null 2>&1; then
    if timeout "${timeout_seconds}" ip netns exec "${ns_name}" python3 - "198.18.0.1" "${port}" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(3.0)
try:
    sock.connect((host, port))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
    then
      status=0
    fi
  fi

  ip link delete "${host_if}" >/dev/null 2>&1 || true
  ip netns del "${ns_name}" >/dev/null 2>&1 || true
  return "${status}"
}

nft_enabled_listener_rules_effective() {
  nft_ruleset_allows_dport tcp "${SSH_PORT}" || return 1
  if enable_vless_reality; then
    nft_ruleset_allows_dport tcp "${XRAY_LISTEN_PORT}" || return 1
  fi
  if enable_ss2022; then
    nft_ruleset_allows_dport tcp "${SS2022_LISTEN_PORT}" || return 1
    nft_ruleset_allows_dport udp "${SS2022_LISTEN_PORT}" || return 1
    if declare -F xray_tcp_listener_present >/dev/null 2>&1 \
      && xray_tcp_listener_present "${SS2022_LISTEN_PORT}" \
      && tcp_inbound_namespace_probe_supported; then
      probe_tcp_listener_via_namespace "${SS2022_LISTEN_PORT}" || return 1
    fi
  fi
  if enable_hysteria2; then
    nft_ruleset_allows_dport udp "${HYSTERIA2_LISTEN_PORT}" || return 1
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      nft_ruleset_allows_dport tcp "${HYSTERIA2_ACME_HTTP_PORT}" || return 1
    fi
  fi
  return 0
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
  if ! nft_enabled_listener_rules_effective; then
    warn "Applied nftables rules did not effectively allow the enabled listener set; restoring previous configuration"
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
