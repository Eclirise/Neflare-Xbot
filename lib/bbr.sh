#!/usr/bin/env bash

readonly BBR_SYSCTL_FILE="/etc/sysctl.d/99-neflare-bbr.conf"
BBR_STATUS="${BBR_STATUS:-unknown}"

enable_bbr_if_supported() {
  snapshot_file_once "${BBR_SYSCTL_FILE}"
  local available
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  if [[ " ${available} " != *" bbr "* ]]; then
    BBR_STATUS="unsupported"
    warn "Kernel does not advertise BBR support; leaving TCP congestion control unchanged."
    return 0
  fi

  install_text "${BBR_SYSCTL_FILE}" "net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
" 0644 root root
  if ! sysctl --system >/dev/null; then
    rollback_file_and_validate "${BBR_SYSCTL_FILE}" sysctl --system >/dev/null
    die "Failed to apply BBR sysctl settings."
  fi

  if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" == "bbr" ]]; then
    BBR_STATUS="enabled"
    success "BBR enabled successfully"
  else
    BBR_STATUS="failed"
    die "BBR settings were applied but did not become active."
  fi
}

