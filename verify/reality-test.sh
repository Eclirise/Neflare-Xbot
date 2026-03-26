#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$#" -ge 1 ]] || { echo "Usage: verify/reality-test.sh <domain> [...]" >&2; exit 2; }
/usr/local/bin/neflarectl reality-test "$@"

