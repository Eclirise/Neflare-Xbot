#!/usr/bin/env bash

rollback_file_and_validate() {
  local path="$1"
  shift
  restore_snapshot_path "${path}"
  if [[ "$#" -gt 0 ]]; then
    "$@"
  fi
}

rollback_paths() {
  local path
  for path in "$@"; do
    restore_snapshot_path "${path}"
  done
}

