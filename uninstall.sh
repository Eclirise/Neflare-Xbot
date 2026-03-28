#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/i18n.sh
source "${SCRIPT_DIR}/lib/i18n.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/backup.sh
source "${SCRIPT_DIR}/lib/backup.sh"
# shellcheck source=lib/rollback.sh
source "${SCRIPT_DIR}/lib/rollback.sh"
# shellcheck source=lib/ssh.sh
source "${SCRIPT_DIR}/lib/ssh.sh"
# shellcheck source=lib/ipv6.sh
source "${SCRIPT_DIR}/lib/ipv6.sh"
# shellcheck source=lib/nftables.sh
source "${SCRIPT_DIR}/lib/nftables.sh"
# shellcheck source=lib/bbr.sh
source "${SCRIPT_DIR}/lib/bbr.sh"
# shellcheck source=lib/xray.sh
source "${SCRIPT_DIR}/lib/xray.sh"
# shellcheck source=lib/bot.sh
source "${SCRIPT_DIR}/lib/bot.sh"

PURGE_XRAY=0
RESTORE_NETWORK=0
RESTORE_SNAPSHOT_ID=""

usage() {
  cat <<EOF
Usage: ./uninstall.sh [options]

Options:
  --purge-xray        Stop and remove Xray binary/config managed by this repo
  --restore-network   Restore SSH/firewall/sysctl files from the selected snapshot
  --snapshot ID       Use a specific snapshot ID from /var/backups/neflare
  --help              Show this help text
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --purge-xray)
        PURGE_XRAY=1
        shift
        ;;
      --restore-network)
        RESTORE_NETWORK=1
        shift
        ;;
      --snapshot)
        RESTORE_SNAPSHOT_ID="${2:-}"
        [[ -n "${RESTORE_SNAPSHOT_ID}" ]] || die "--snapshot requires a snapshot id"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

resolve_snapshot() {
  if [[ -n "${RESTORE_SNAPSHOT_ID}" ]]; then
    SNAPSHOT_ID="${RESTORE_SNAPSHOT_ID}"
  elif [[ -f "${NEFLARE_CONFIG_DIR}/last-snapshot-id" ]]; then
    SNAPSHOT_ID="$(cat "${NEFLARE_CONFIG_DIR}/last-snapshot-id")"
  fi
  if [[ -n "${SNAPSHOT_ID:-}" ]]; then
    SNAPSHOT_DIR="${NEFLARE_BACKUP_ROOT}/${SNAPSHOT_ID}"
  fi
}

restore_network_state() {
  [[ -n "${SNAPSHOT_DIR:-}" && -d "${SNAPSHOT_DIR}" ]] || die "Requested network restore but no snapshot directory was resolved."
  restore_snapshot_path "${SSHD_DROPIN_PATH}"
  restore_snapshot_path "${SUDOERS_DROPIN_PATH}"
  restore_snapshot_path "${NFTABLES_MAIN_FILE}"
  restore_snapshot_path "${NFTABLES_CN_SET_FILE}"
  if [[ -e "$(snapshot_path_for "${IPV6_SYSCTL_FILE}")" || -e "$(snapshot_path_for "${IPV6_SYSCTL_FILE}").missing" ]]; then
    restore_snapshot_path "${IPV6_SYSCTL_FILE}"
  fi
  if [[ -e "$(snapshot_path_for "${BBR_MODULE_FILE}")" || -e "$(snapshot_path_for "${BBR_MODULE_FILE}").missing" ]]; then
    restore_snapshot_path "${BBR_MODULE_FILE}"
  fi
  if [[ -e "$(snapshot_path_for "${BBR_SYSCTL_FILE}")" || -e "$(snapshot_path_for "${BBR_SYSCTL_FILE}").missing" ]]; then
    restore_snapshot_path "${BBR_SYSCTL_FILE}"
  fi
  if [[ -e "$(snapshot_path_for "${BBR_ROLLBACK_FILE}")" || -e "$(snapshot_path_for "${BBR_ROLLBACK_FILE}").missing" ]]; then
    restore_snapshot_path "${BBR_ROLLBACK_FILE}"
  fi
  validate_sshd_config
  systemctl reload ssh
  validate_nftables_config_file "${NFTABLES_MAIN_FILE}"
  nft -f "${NFTABLES_MAIN_FILE}"
  sysctl --system >/dev/null
}

purge_xray_managed_files() {
  systemctl disable --now xray >/dev/null 2>&1 || true
  rm -rf /usr/local/etc/xray
  rm -f "${XRAY_OVERRIDE_PATH}"
  local binary
  binary="$(xray_binary_path || true)"
  if [[ -n "${binary}" ]]; then
    rm -f "${binary}"
  fi
  systemctl daemon-reload
}

main() {
  parse_args "$@"
  ensure_root
  set_default_config
  load_installed_config_if_present
  UI_LANG="$(lang_normalize "${UI_LANG:-}")"
  UI_LANG="${UI_LANG:-en}"
  resolve_snapshot

  systemctl disable --now neflare-bot >/dev/null 2>&1 || true
  systemctl disable --now neflare-reality-lint-watch.timer >/dev/null 2>&1 || true
  systemctl disable --now neflare-cn-ssh-geo-update.timer >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/neflare-bot.service
  rm -f /etc/systemd/system/neflare-reality-lint-watch.service
  rm -f /etc/systemd/system/neflare-reality-lint-watch.timer
  rm -f /etc/systemd/system/neflare-cn-ssh-geo-update.service
  rm -f /etc/systemd/system/neflare-cn-ssh-geo-update.timer
  systemctl daemon-reload

  if [[ "${RESTORE_NETWORK}" -eq 1 ]]; then
    restore_network_state
  fi
  if [[ "${PURGE_XRAY}" -eq 1 ]]; then
    purge_xray_managed_files
  fi

  rm -f "${BOT_ENV_FILE}" "${NFTABLES_CN_SET_FILE}" "${NFTABLES_CN_METADATA_FILE}" "${NFTABLES_CN_LAST_GOOD_FILE}"
  rm -rf "${NEFLARE_INSTALL_ROOT}" "${NEFLARE_BOT_INSTALL_DIR}"
  rm -f "${NEFLARE_RUNTIME_BIN_DIR}/neflarectl"

  if [[ "$(current_ui_lang)" == "zh" ]]; then
    echo "NeFlare 卸载已完成。"
  else
    echo "NeFlare uninstall completed."
  fi
  if [[ "${RESTORE_NETWORK}" -ne 1 ]]; then
    if [[ "$(current_ui_lang)" == "zh" ]]; then
      echo "SSH/防火墙状态已保留。如需从快照恢复，请重新执行并带上 --restore-network。"
    else
      echo "SSH/firewall state was left in place. Re-run with --restore-network to restore from snapshot."
    fi
  fi
}

main "$@"
