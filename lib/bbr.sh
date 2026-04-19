#!/usr/bin/env bash

readonly BBR_MODULE_FILE="/etc/modules-load.d/bbr.conf"
readonly BBR_SYSCTL_FILE="/etc/sysctl.d/99-proxy-bbr.conf"
readonly BBR_ROLLBACK_FILE="/root/rollback-proxy-bbr.sh"
BBR_STATUS="${BBR_STATUS:-unknown}"

legacy_proxy_tuning_paths() {
  printf '%s\n' "/etc/sysctl.d/zzz-proxy-tcp-tuning.conf"
}

managed_listener_ports() {
  local ports=("${SSH_PORT}")
  if enable_vless_reality; then
    ports+=("${XRAY_LISTEN_PORT}")
  fi
  if enable_ss2022; then
    ports+=("${SS2022_LISTEN_PORT}")
  fi
  if enable_hysteria2; then
    ports+=("${HYSTERIA2_LISTEN_PORT}")
    if [[ "${HYSTERIA2_TLS_MODE}" == "acme" && "${HYSTERIA2_ACME_CHALLENGE_TYPE}" == "http" ]]; then
      ports+=("${HYSTERIA2_ACME_HTTP_PORT}")
    fi
  fi

  printf '%s\n' "${ports[@]}" | awk '
    /^[0-9]+$/ && $1 >= 1 && $1 <= 65535 && !seen[$1]++ { print $1 }
  '
}

merge_reserved_ports() {
  local current="$1"
  shift || true
  python3 - "${current}" "$@" <<'PY'
import sys

ports = set()

def add_token(token: str) -> None:
    token = token.strip()
    if not token:
        return
    if "-" in token:
        start_text, end_text = token.split("-", 1)
        start = int(start_text)
        end = int(end_text)
        if start > end:
            start, end = end, start
        for value in range(start, end + 1):
            if 1 <= value <= 65535:
                ports.add(value)
        return
    value = int(token)
    if 1 <= value <= 65535:
        ports.add(value)

for token in sys.argv[1].split(","):
    add_token(token)

for token in sys.argv[2:]:
    add_token(token)

ordered = sorted(ports)
if not ordered:
    raise SystemExit(0)

ranges = []
start = prev = ordered[0]
for value in ordered[1:]:
    if value == prev + 1:
        prev = value
        continue
    ranges.append((start, prev))
    start = prev = value
ranges.append((start, prev))

parts = []
for start, end in ranges:
    if start == end:
        parts.append(str(start))
    else:
        parts.append(f"{start}-{end}")

print(",".join(parts))
PY
}

managed_reserved_ports_value() {
  local current_reserved
  current_reserved="$(sysctl -n net.ipv4.ip_local_reserved_ports 2>/dev/null || true)"
  local ports=()
  while IFS= read -r port; do
    [[ -n "${port}" ]] || continue
    ports+=("${port}")
  done < <(managed_listener_ports)
  merge_reserved_ports "${current_reserved}" "${ports[@]}"
}

render_bbr_sysctl_content() {
  local reserved_ports
  reserved_ports="$(managed_reserved_ports_value)"

  cat <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5

net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864

net.ipv4.ip_local_port_range = 10000 65535
EOF

  if [[ -n "${reserved_ports}" ]]; then
    printf 'net.ipv4.ip_local_reserved_ports = %s\n' "${reserved_ports}"
  fi
}

remove_legacy_proxy_tuning_files() {
  local path
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    [[ "${path}" != "${BBR_SYSCTL_FILE}" ]] || continue
    snapshot_file_once "${path}"
    if [[ -e "${path}" || -L "${path}" ]]; then
      rm -f "${path}"
      info "Removed legacy proxy sysctl override ${path}"
    fi
  done < <(legacy_proxy_tuning_paths)
}

set_live_fq_best_effort() {
  local iface="$1"
  [[ -n "${iface}" ]] || return 0

  local qdisc_output
  qdisc_output="$(tc qdisc show dev "${iface}" 2>/dev/null || true)"
  [[ -n "${qdisc_output}" ]] || return 0

  if grep -q '^qdisc mq ' <<<"${qdisc_output}"; then
    local parents=()
    local parent
    while IFS= read -r parent; do
      parents+=("${parent}")
    done < <(awk '
      $1 == "qdisc" && $4 == "parent" && $2 != "fq" && !seen[$5]++ { print $5 }
    ' <<<"${qdisc_output}")

    for parent in "${parents[@]}"; do
      if tc qdisc replace dev "${iface}" parent "${parent}" fq 2>/dev/null; then
        :
      fi
    done
    return 0
  fi

  if grep -q '^qdisc fq_codel ' <<<"${qdisc_output}"; then
    tc qdisc replace dev "${iface}" root fq 2>/dev/null || true
  fi
}

install_bbr_rollback_script() {
  install_text "${BBR_ROLLBACK_FILE}" '#!/usr/bin/env bash
set -Eeuo pipefail

rm -f /etc/modules-load.d/bbr.conf
rm -f /etc/sysctl.d/99-proxy-bbr.conf

sysctl --system
' 0700 root root
}

enable_bbr_if_supported() {
  local legacy_paths=()
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    legacy_paths+=("${path}")
  done < <(legacy_proxy_tuning_paths)

  snapshot_file_once "${BBR_MODULE_FILE}"
  snapshot_file_once "${BBR_SYSCTL_FILE}"
  snapshot_file_once "${BBR_ROLLBACK_FILE}"
  local path
  for path in "${legacy_paths[@]}"; do
    snapshot_file_once "${path}"
  done

  modprobe tcp_bbr 2>/dev/null || true

  remove_legacy_proxy_tuning_files

  install_text "${BBR_MODULE_FILE}" 'tcp_bbr
' 0644 root root
  install_text "${BBR_SYSCTL_FILE}" "$(render_bbr_sysctl_content)
" 0644 root root
  install_bbr_rollback_script

  if ! sysctl --system >/dev/null; then
    rollback_paths "${BBR_MODULE_FILE}" "${BBR_SYSCTL_FILE}" "${BBR_ROLLBACK_FILE}" "${legacy_paths[@]}"
    sysctl --system >/dev/null
    BBR_STATUS="failed"
    die "Failed to apply proxy BBR sysctl settings."
  fi

  set_live_fq_best_effort "$(detect_primary_interface)"

  if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" == "bbr" ]]; then
    BBR_STATUS="enabled"
  else
    BBR_STATUS="failed"
    die "BBR settings were applied but did not become active."
  fi
}

