#!/usr/bin/env bash
set -Eeuo pipefail
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_fastopen
sysctl net.ipv4.tcp_keepalive_time
sysctl net.ipv4.tcp_keepalive_intvl
sysctl net.ipv4.tcp_keepalive_probes
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.core.netdev_max_backlog
sysctl net.ipv4.ip_local_reserved_ports
tc qdisc show dev "$(ip route show default | awk '/default/ {print $5; exit}')"

