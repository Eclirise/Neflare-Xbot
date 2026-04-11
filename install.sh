#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/i18n.sh
source "${SCRIPT_DIR}/lib/i18n.sh"
# shellcheck source=lib/os.sh
source "${SCRIPT_DIR}/lib/os.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/backup.sh
source "${SCRIPT_DIR}/lib/backup.sh"
# shellcheck source=lib/rollback.sh
source "${SCRIPT_DIR}/lib/rollback.sh"
# shellcheck source=lib/packages.sh
source "${SCRIPT_DIR}/lib/packages.sh"
# shellcheck source=lib/ssh.sh
source "${SCRIPT_DIR}/lib/ssh.sh"
# shellcheck source=lib/ipv6.sh
source "${SCRIPT_DIR}/lib/ipv6.sh"
# shellcheck source=lib/nftables.sh
source "${SCRIPT_DIR}/lib/nftables.sh"
# shellcheck source=lib/bbr.sh
source "${SCRIPT_DIR}/lib/bbr.sh"
# shellcheck source=lib/time_sync.sh
source "${SCRIPT_DIR}/lib/time_sync.sh"
# shellcheck source=lib/xray.sh
source "${SCRIPT_DIR}/lib/xray.sh"
# shellcheck source=lib/hysteria2.sh
source "${SCRIPT_DIR}/lib/hysteria2.sh"
# shellcheck source=lib/reality.sh
source "${SCRIPT_DIR}/lib/reality.sh"
# shellcheck source=lib/bot.sh
source "${SCRIPT_DIR}/lib/bot.sh"
# shellcheck source=lib/verify.sh
source "${SCRIPT_DIR}/lib/verify.sh"

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --config FILE         Load installer values from FILE
  --non-interactive     Do not prompt; require all needed values from config or existing state
  --upgrade-xray        Explicitly upgrade Xray core through the official install flow
  --verify-only         Run verification only
  --help                Show this help text
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --config)
        CONFIG_INPUT_FILE="${2:-}"
        [[ -n "${CONFIG_INPUT_FILE}" ]] || die "--config requires a file path"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --upgrade-xray)
        UPGRADE_XRAY=1
        shift
        ;;
      --verify-only)
        VERIFY_ONLY=1
        shift
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

main() {
  parse_args "$@"
  ensure_root
  mkdir_root_only "${NEFLARE_CONFIG_DIR}"
  mkdir_root_only "${NEFLARE_STATE_DIR}"
  mkdir_root_only "${NEFLARE_BACKUP_ROOT}"
  detect_supported_os
  bootstrap_python3_if_missing
  set_default_config
  load_installed_config_if_present
  load_user_config_file "${CONFIG_INPUT_FILE}"
  if bool_is_true "${VERIFY_ONLY:-0}"; then
    NON_INTERACTIVE=1
  fi
  choose_ui_language
  UI_LANG_RUNTIME_OVERRIDE="${UI_LANG}"
  export UI_LANG_RUNTIME_OVERRIDE

  if bool_is_true "${VERIFY_ONLY:-0}"; then
    run_full_verification
    print_cloud_firewall_guidance
    print_final_summary_lists
    print_policy_summary
    print_client_yaml_snippet
    return 0
  fi

  collect_install_config
  detect_current_admin_source
  save_installed_config
  create_install_snapshot
  install_base_packages
  install_runtime_assets
  ensure_admin_user
  configure_ssh_hardening
  save_installed_config
  ensure_xray_installed_if_needed
  prepare_vless_reality_runtime
  configure_ipv6_mode
  prepare_temp_admin_allow_if_needed
  save_installed_config
  configure_xray_runtime
  configure_hysteria2_runtime
  configure_nftables_firewall
  update_cn_ssh_geo_sets
  install_cn_ssh_geo_update_units
  enable_bbr_if_supported
  configure_optional_docker_tests_runtime
  configure_time_sync_runtime
  configure_optional_bot
  save_installed_config
  run_full_verification

  echo
  print_cloud_firewall_guidance
  echo
  print_final_summary_lists
  echo
  print_policy_summary
  echo
  print_client_yaml_snippet
}

main "$@"
