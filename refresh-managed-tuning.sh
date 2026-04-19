#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: sudo ./refresh-managed-tuning.sh [--config FILE]

Delete only the known NeFlare-managed tuning files, back them up, and rerun
the installer in non-interactive mode.
EOF
}

CONFIG_FILE="/etc/neflare/neflare.env"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="${2:-}"
      [[ -n "${CONFIG_FILE}" ]] || die "--config requires a file path"
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

ensure_root
[[ -f "${CONFIG_FILE}" ]] || die "Config file not found: ${CONFIG_FILE}"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${NEFLARE_BACKUP_ROOT}/managed-tuning-refresh/${timestamp}"
mkdir_system_dir "${backup_dir}" 0700

known_paths=(
  "/etc/sysctl.d/99-proxy-bbr.conf"
  "/etc/sysctl.d/zzz-proxy-tcp-tuning.conf"
  "/etc/modules-load.d/bbr.conf"
  "/root/rollback-proxy-bbr.sh"
)

info "Backing up and removing only the known NeFlare-managed tuning files"

for path in "${known_paths[@]}"; do
  if [[ -e "${path}" || -L "${path}" ]]; then
    target="${backup_dir}/${path#/}"
    mkdir_system_dir "$(dirname "${target}")" 0700
    cp -a "${path}" "${target}"
    rm -f "${path}"
    info "Removed ${path}"
  else
    info "Skipped missing ${path}"
  fi
done

info "Rerunning the installer to write and apply the current managed tuning set"
exec bash "${SCRIPT_DIR}/install.sh" --config "${CONFIG_FILE}" --non-interactive
