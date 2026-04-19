#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/hysteria2.sh"
set_default_config
load_installed_config_if_present
if ! enable_hysteria2; then
  echo "Hysteria 2 is disabled in the installed config."
  exit 0
fi
validate_hysteria2_config_file "${HYSTERIA2_CONFIG_PATH}"
systemctl status neflare-hysteria2 --no-pager
