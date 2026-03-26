#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -eq 0 || "$#" -eq 2 || "$#" -eq 3 ]] || {
  echo "Usage: verify/quota-calibrate.sh [<used_gb> <remain_gb> [next_reset_utc]]" >&2
  exit 2
}
if [[ "$#" -eq 0 ]]; then
  /usr/local/bin/neflarectl quota-clear
else
  /usr/local/bin/neflarectl quota-set "$@"
fi
