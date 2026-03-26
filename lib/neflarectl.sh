#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d /usr/local/lib/neflare/lib ]]; then
  LIB_DIR="/usr/local/lib/neflare/lib"
else
  LIB_DIR="${SELF_DIR}"
fi

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=lib/i18n.sh
source "${LIB_DIR}/i18n.sh"
# shellcheck source=lib/os.sh
source "${LIB_DIR}/os.sh"
# shellcheck source=lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=lib/backup.sh
source "${LIB_DIR}/backup.sh"
# shellcheck source=lib/rollback.sh
source "${LIB_DIR}/rollback.sh"
# shellcheck source=lib/ssh.sh
source "${LIB_DIR}/ssh.sh"
# shellcheck source=lib/ipv6.sh
source "${LIB_DIR}/ipv6.sh"
# shellcheck source=lib/nftables.sh
source "${LIB_DIR}/nftables.sh"
# shellcheck source=lib/bbr.sh
source "${LIB_DIR}/bbr.sh"
# shellcheck source=lib/xray.sh
source "${LIB_DIR}/xray.sh"
# shellcheck source=lib/reality.sh
source "${LIB_DIR}/reality.sh"
# shellcheck source=lib/bot.sh
source "${LIB_DIR}/bot.sh"
# shellcheck source=lib/verify.sh
source "${LIB_DIR}/verify.sh"

set_default_config
load_installed_config_if_present
UI_LANG="$(lang_normalize "${UI_LANG:-}")"
UI_LANG="${UI_LANG:-en}"
export UI_LANG

python_bot_main() {
  python3 "${NEFLARE_BOT_INSTALL_DIR}/main.py" "$@"
}

require_explicit_yes() {
  [[ "${1:-}" == "--yes" ]] || die "This action requires --yes."
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  update-cn-ssh-geo)
    ensure_root
    update_cn_ssh_geo_sets
    ;;
  reality-test)
    if [[ "${1:-}" == "--json" ]]; then
      shift
      python3 "${NEFLARE_RUNTIME_LIB_DIR}/reality_probe.py" --json --public-port "${XRAY_LISTEN_PORT}" "$@"
    else
      python3 "${NEFLARE_RUNTIME_LIB_DIR}/reality_probe.py" --public-port "${XRAY_LISTEN_PORT}" "$@"
    fi
    ;;
  reality-set)
    ensure_root
    domain="${1:-}"
    [[ -n "${domain}" ]] || die "Usage: neflarectl reality-set <domain> [--force]"
    force="no"
    if [[ "${2:-}" == "--force" ]]; then
      force="yes"
    fi
    reality_set_domain "${domain}" "${force}"
    ;;
  reality-lint)
    ensure_root
    lint_current_reality_policy
    policy_state_field '.selected'
    ;;
  status)
    python_bot_main --status-text
    ;;
  daily)
    python_bot_main --daily-text
    ;;
  quota)
    python_bot_main --quota-text
    ;;
  quota-set)
    python_bot_main --quota-set "$@"
    ;;
  quota-clear)
    python_bot_main --quota-clear
    ;;
  bind-chat)
    ensure_root
    python_bot_main --bind-chat "$@"
    ;;
  list-chat-candidates)
    python_bot_main --list-chat-candidates
    ;;
  send-daily)
    python_bot_main --send-daily
    ;;
  print-client)
    print_client_yaml_snippet
    ;;
  print-policy)
    print_policy_summary
    ;;
  restart-xray)
    ensure_root
    require_explicit_yes "${1:-}"
    validate_xray_config_file "${XRAY_CONFIG_PATH}"
    systemctl restart xray
    ;;
  reboot)
    ensure_root
    require_explicit_yes "${1:-}"
    systemctl reboot
    ;;
  verify)
    ensure_root
    run_full_verification
    ;;
  *)
    cat <<EOF
Usage: neflarectl <command>

Commands:
  update-cn-ssh-geo
  reality-test [--json] <domain> [...]
  reality-set <domain> [--force]
  reality-lint
  status
  daily
  quota
  quota-set <used_gb> <remain_gb> [next_reset_utc]
  quota-clear
  bind-chat <chat_id>
  list-chat-candidates
  send-daily
  print-policy
  print-client
  restart-xray --yes
  reboot --yes
  verify
EOF
    ;;
esac
