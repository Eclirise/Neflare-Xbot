#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/nftables.sh"
set_default_config
load_installed_config_if_present
validate_nftables_config_file "${NFTABLES_MAIN_FILE}"
nft list ruleset

