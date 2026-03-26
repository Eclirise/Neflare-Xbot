#!/usr/bin/env bash

SNAPSHOT_ID="${SNAPSHOT_ID:-}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-}"

create_install_snapshot() {
  mkdir_system_dir "${NEFLARE_BACKUP_ROOT}" 0700
  SNAPSHOT_ID="${SNAPSHOT_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
  SNAPSHOT_DIR="${NEFLARE_BACKUP_ROOT}/${SNAPSHOT_ID}"
  mkdir_system_dir "${SNAPSHOT_DIR}" 0700
  mkdir_system_dir "${SNAPSHOT_DIR}/files" 0700
  printf '%s\n' "${SNAPSHOT_ID}" > "${NEFLARE_CONFIG_DIR}/last-snapshot-id"
  info "Created install snapshot directory ${SNAPSHOT_DIR}"
}

snapshot_path_for() {
  local path="$1"
  printf '%s/files/%s\n' "${SNAPSHOT_DIR}" "${path#/}"
}

snapshot_file_once() {
  local path="$1"
  if [[ -z "${SNAPSHOT_DIR}" ]]; then
    create_install_snapshot
  fi
  local target
  target="$(snapshot_path_for "${path}")"
  if [[ -e "${target}" || -e "${target}.missing" ]]; then
    return 0
  fi
  mkdir_system_dir "$(dirname "${target}")" 0700
  if [[ -e "${path}" || -L "${path}" ]]; then
    cp -a "${path}" "${target}"
  else
    : > "${target}.missing"
  fi
}

restore_snapshot_path() {
  local path="$1"
  [[ -n "${SNAPSHOT_DIR}" ]] || die "Snapshot directory not initialized."
  local target
  target="$(snapshot_path_for "${path}")"
  if [[ -e "${target}.missing" ]]; then
    rm -rf "${path}"
    return 0
  fi
  [[ -e "${target}" || -L "${target}" ]] || die "Snapshot copy not found for ${path}"
  mkdir_system_dir "$(dirname "${path}")" 0755
  rm -rf "${path}"
  cp -a "${target}" "${path}"
}
