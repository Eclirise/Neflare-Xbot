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
if ! xray_features_enabled; then
  echo "Xray-backed protocols are disabled in the installed config."
  exit 0
fi
validate_xray_config_file "${XRAY_CONFIG_PATH}"
if enable_vless_reality; then
  lint_current_reality_policy
fi
systemctl status xray --no-pager
