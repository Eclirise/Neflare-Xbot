#!/usr/bin/env bash

readonly BBR_MODULE_FILE="/etc/modules-load.d/bbr.conf"
readonly BBR_SYSCTL_FILE="/etc/sysctl.d/99-proxy-bbr.conf"
readonly BBR_ROLLBACK_FILE="/root/rollback-proxy-bbr.sh"
BBR_STATUS="${BBR_STATUS:-unknown}"

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
  snapshot_file_once "${BBR_MODULE_FILE}"
  snapshot_file_once "${BBR_SYSCTL_FILE}"
  snapshot_file_once "${BBR_ROLLBACK_FILE}"

  modprobe tcp_bbr 2>/dev/null || true

  install_text "${BBR_MODULE_FILE}" 'tcp_bbr
' 0644 root root
  install_text "${BBR_SYSCTL_FILE}" 'net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864

net.ipv4.ip_local_port_range = 10000 65535
' 0644 root root
  install_bbr_rollback_script

  if ! sysctl --system >/dev/null; then
    rollback_paths "${BBR_MODULE_FILE}" "${BBR_SYSCTL_FILE}" "${BBR_ROLLBACK_FILE}"
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

