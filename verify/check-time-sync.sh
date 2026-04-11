#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/time_sync.sh"
source "${SCRIPT_DIR}/lib/verify.sh"
set_default_config
load_installed_config_if_present
if ! enable_time_sync; then
  echo "Time sync maintenance is disabled in the installed config."
  exit 0
fi
verify_time_sync_state
timedatectl status
