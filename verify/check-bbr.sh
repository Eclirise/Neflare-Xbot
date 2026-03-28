#!/usr/bin/env bash
set -Eeuo pipefail
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.core.default_qdisc
tc qdisc show dev "$(ip route show default | awk '/default/ {print $5; exit}')"

