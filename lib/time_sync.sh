#!/usr/bin/env bash

readonly TIME_SYNC_SERVICE_UNIT="/etc/systemd/system/neflare-time-sync.service"
readonly TIME_SYNC_TIMER_UNIT="/etc/systemd/system/neflare-time-sync.timer"

time_sync_supported() {
  command_exists systemctl && command_exists timedatectl
}

time_sync_primary_unit() {
  local unit
  for unit in systemd-timesyncd.service chrony.service chronyd.service ntp.service ntpsec.service openntpd.service; do
    if systemctl is-active --quiet "${unit}" 2>/dev/null; then
      printf '%s\n' "${unit}"
      return 0
    fi
  done
  for unit in systemd-timesyncd.service chrony.service chronyd.service ntp.service ntpsec.service openntpd.service; do
    if systemctl list-unit-files "${unit}" --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "${unit}"; then
      printf '%s\n' "${unit}"
      return 0
    fi
  done
  return 1
}

time_sync_ntp_enabled() {
  [[ "$(timedatectl show -p NTP --value 2>/dev/null || true)" == "yes" ]]
}

time_sync_synchronized() {
  local value=""
  value="$(timedatectl show -p SystemClockSynchronized --value 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
  fi
  [[ "${value}" == "yes" ]]
}

calibrate_server_time() {
  time_sync_supported || die "timedatectl and systemctl are required for time synchronization management."

  if ! timedatectl set-ntp true >/dev/null 2>&1; then
    warn "Unable to enable automatic time synchronization through timedatectl."
  fi

  local unit=""
  unit="$(time_sync_primary_unit || true)"
  if [[ -n "${unit}" ]]; then
    systemctl enable --now "${unit}" >/dev/null 2>&1 || true
    if [[ "${unit}" == "systemd-timesyncd.service" ]] && ! time_sync_synchronized; then
      systemctl restart "${unit}" >/dev/null 2>&1 || true
    fi
  fi

  local attempt
  for attempt in 1 2 3 4 5; do
    if time_sync_synchronized; then
      info "System clock synchronization is healthy."
      return 0
    fi
    sleep 2
  done

  warn "Time sync maintenance completed, but the clock is not yet reported as synchronized."
}

install_time_sync_units() {
  snapshot_file_once "${TIME_SYNC_SERVICE_UNIT}"
  snapshot_file_once "${TIME_SYNC_TIMER_UNIT}"
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-time-sync.service" "${TIME_SYNC_SERVICE_UNIT}" 0644 root root
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-time-sync.timer" "${TIME_SYNC_TIMER_UNIT}" 0644 root root
  systemctl daemon-reload
}

disable_time_sync_runtime() {
  systemctl disable --now neflare-time-sync.timer >/dev/null 2>&1 || true
  systemctl stop neflare-time-sync.service >/dev/null 2>&1 || true
  info "NeFlare time sync watchdog is disabled; existing OS time sync services were left untouched."
}

configure_time_sync_runtime() {
  if ! enable_time_sync; then
    disable_time_sync_runtime
    return 0
  fi

  install_time_sync_units
  calibrate_server_time
  systemctl enable --now neflare-time-sync.timer >/dev/null 2>&1 || die "Failed to enable and start neflare-time-sync.timer."
  systemctl is-enabled --quiet neflare-time-sync.timer || die "neflare-time-sync.timer is not enabled after installation."
  systemctl is-active --quiet neflare-time-sync.timer || die "neflare-time-sync.timer is not active after installation."
  success "Time sync watchdog is enabled"
}
