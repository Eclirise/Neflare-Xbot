#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SELF_DIR}"

usage() {
  cat <<'EOF'
Usage: ./safe-update.sh [--check|--sync]

  --check  Show dirty state, list local changes, and create a backup if needed.
  --sync   Back up local changes when present, then force-align the checkout to its upstream branch.
EOF
}

pick_backup_root() {
  local preferred="${NEFLARE_UPDATE_BACKUP_DIR:-/var/backups/neflare/repo-hotfixes}"
  if mkdir -p "${preferred}" >/dev/null 2>&1; then
    printf '%s\n' "${preferred}"
    return 0
  fi
  local fallback="${REPO_DIR}/.git/neflare-update-backups"
  mkdir -p "${fallback}"
  printf '%s\n' "${fallback}"
}

current_branch() {
  git -C "${REPO_DIR}" branch --show-current
}

current_upstream() {
  git -C "${REPO_DIR}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || {
    local branch
    branch="$(current_branch)"
    printf 'origin/%s\n' "${branch}"
  }
}

dirty_status() {
  git -C "${REPO_DIR}" status --porcelain=v1
}

create_backup_bundle() {
  local backup_root timestamp backup_dir tracked_diff untracked_list
  backup_root="$(pick_backup_root)"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_dir="${backup_root}/${timestamp}"
  mkdir -p "${backup_dir}"

  dirty_status > "${backup_dir}/status.txt"
  git -C "${REPO_DIR}" diff --binary HEAD -- > "${backup_dir}/tracked.patch" || true
  git -C "${REPO_DIR}" ls-files --others --exclude-standard > "${backup_dir}/untracked.txt"

  tracked_diff="no"
  untracked_list="no"
  [[ -s "${backup_dir}/tracked.patch" ]] && tracked_diff="yes"
  [[ -s "${backup_dir}/untracked.txt" ]] && untracked_list="yes"

  if [[ "${untracked_list}" == "yes" ]]; then
    git -C "${REPO_DIR}" ls-files --others --exclude-standard -z | tar -C "${REPO_DIR}" --null -T - -czf "${backup_dir}/untracked.tar.gz"
  fi

  printf '%s\n' "${backup_dir}"
  printf '  tracked patch: %s\n' "${tracked_diff}"
  printf '  untracked archive: %s\n' "${untracked_list}"
}

show_status() {
  local branch upstream remote_url local_head remote_head porcelain
  branch="$(current_branch)"
  upstream="$(current_upstream)"
  remote_url="$(git -C "${REPO_DIR}" remote get-url origin)"
  local_head="$(git -C "${REPO_DIR}" rev-parse --short HEAD)"
  remote_head="$(git -C "${REPO_DIR}" rev-parse --short "${upstream}" 2>/dev/null || printf 'unknown')"
  porcelain="$(dirty_status)"

  echo "Repository: ${REPO_DIR}"
  echo "Branch: ${branch}"
  echo "Upstream: ${upstream}"
  echo "Remote: ${remote_url}"
  echo "Local HEAD: ${local_head}"
  echo "Upstream HEAD: ${remote_head}"
  echo

  if [[ -z "${porcelain}" ]]; then
    echo "Working tree: clean"
    return 0
  fi

  echo "Working tree: dirty"
  echo "Changed files:"
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    echo "  ${line}"
  done <<<"${porcelain}"
}

force_sync() {
  local branch upstream backup_details
  branch="$(current_branch)"
  upstream="$(current_upstream)"

  git -C "${REPO_DIR}" fetch --prune origin "${branch}"
  if [[ -n "$(dirty_status)" ]]; then
    echo
    echo "Backing up local checkout changes before force-sync..."
    backup_details="$(create_backup_bundle)"
    echo "${backup_details}"
    echo
    echo "Overwriting local checkout changes to match ${upstream}."
  fi

  git -C "${REPO_DIR}" checkout -f "${branch}"
  git -C "${REPO_DIR}" reset --hard "${upstream}"
  git -C "${REPO_DIR}" clean -fd

  echo "Checkout is now aligned to ${upstream}."
  echo "Next step:"
  echo "  sudo ./install.sh --config /etc/neflare/neflare.env --non-interactive"
}

mode="check"
case "${1:---check}" in
  --check) mode="check" ;;
  --sync) mode="sync" ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

git -C "${REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "This script must be run from inside the git checkout." >&2
  exit 1
}

show_status

if [[ "${mode}" == "check" ]]; then
  if [[ -n "$(dirty_status)" ]]; then
    echo
    echo "Creating a backup bundle for the dirty checkout..."
    create_backup_bundle
    echo
    echo "When you are ready to overwrite the checkout with the upstream branch, run:"
    echo "  sudo ./safe-update.sh --sync"
    exit 2
  fi
  echo
  echo "The checkout is already clean. You can run:"
  echo "  sudo git pull --ff-only"
  echo "or"
  echo "  sudo ./safe-update.sh --sync"
  exit 0
fi

force_sync
