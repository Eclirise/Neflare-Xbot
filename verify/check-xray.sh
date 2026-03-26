#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/xray.sh"
source "${SCRIPT_DIR}/lib/reality.sh"
set_default_config
load_installed_config_if_present
validate_xray_config_file "${XRAY_CONFIG_PATH}"
lint_current_reality_policy
systemctl status xray --no-pager
