#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NEFLARE_SOURCE_ROOT="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/nftables.sh"
source "${SCRIPT_DIR}/lib/xray.sh"
source "${SCRIPT_DIR}/lib/verify.sh"

set_default_config
load_installed_config_if_present
ensure_root

enable_ss2022 || die "Shadowsocks 2022 is disabled in the installed configuration."

port="${1:-${SS2022_LISTEN_PORT}}"

xray_tcp_listener_present "${port}" || die "No listener found on TCP/${port} for Shadowsocks 2022."
xray_udp_listener_present "${port}" || die "No listener found on UDP/${port} for Shadowsocks 2022."
tcp_inbound_namespace_probe_supported || die "SS2022 firewall regression probing requires ip, timeout, and python3."
probe_tcp_listener_via_namespace "${port}" || die "Inbound TCP handshake to Shadowsocks 2022 TCP/${port} did not complete."
/usr/local/bin/neflarectl verify
