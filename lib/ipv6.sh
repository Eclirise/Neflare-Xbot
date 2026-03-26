#!/usr/bin/env bash

readonly IPV6_SYSCTL_FILE="/etc/sysctl.d/99-neflare-ipv6.conf"

current_session_uses_ipv6() {
  [[ -n "${CURRENT_ADMIN_SOURCE_IP:-}" && "${CURRENT_ADMIN_SOURCE_IP}" == *:* ]]
}

apply_sysctl_with_rollback() {
  local path="$1"
  snapshot_file_once "${path}"
  sysctl --system >/dev/null
}

configure_ipv6_mode() {
  snapshot_file_once "${IPV6_SYSCTL_FILE}"
  if [[ "${ENABLE_IPV6}" == "yes" ]]; then
    if [[ -f "${IPV6_SYSCTL_FILE}" ]]; then
      rm -f "${IPV6_SYSCTL_FILE}"
      sysctl --system >/dev/null || rollback_file_and_validate "${IPV6_SYSCTL_FILE}" sysctl --system >/dev/null
    fi
    success "IPv6 mode left enabled"
    return 0
  fi

  if current_session_uses_ipv6 && [[ "${ALLOW_IPV6_DISABLE_FROM_IPV6}" != "yes" ]]; then
    die "Current admin session uses IPv6. Refusing to disable IPv6 without ALLOW_IPV6_DISABLE_FROM_IPV6=yes."
  fi

  install_text "${IPV6_SYSCTL_FILE}" "net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
" 0644 root root
  if ! sysctl --system >/dev/null; then
    rollback_file_and_validate "${IPV6_SYSCTL_FILE}" sysctl --system >/dev/null
    die "Failed to apply IPv6 disable sysctl settings."
  fi
  success "IPv6 explicitly disabled"
}

