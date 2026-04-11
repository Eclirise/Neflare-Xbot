#!/usr/sbin/nft -f
flush ruleset

table inet neflare {
__CN_SET_DECLARATIONS__

    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state invalid drop
        ct state { established, related } accept

        ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem, echo-request, echo-reply } accept
        __IPV6_ICMP_RULE__

        __IPV6_POLICY_RULE__

        __TEMP_ADMIN_ALLOW_V4_RULE__
        __TEMP_ADMIN_ALLOW_V6_RULE__

        ip saddr @cn_ssh_v4 tcp dport __SSH_PORT__ drop comment "SSH CN IPv4 drop"
        __IPV6_SSH_GEO_RULE__

        tcp dport __SSH_PORT__ accept comment "SSH"
__PUBLIC_LISTENER_RULES__
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
