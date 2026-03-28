#!/usr/bin/env bash
set -Eeuo pipefail
systemctl status neflare-bot --no-pager
systemctl status neflare-reality-lint-watch.timer --no-pager

