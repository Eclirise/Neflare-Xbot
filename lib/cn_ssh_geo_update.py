#!/usr/bin/env python3
"""Fetch mainland-China IP allocations from APNIC and render nftables sets."""

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable, List

APNIC_URL = "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
USER_AGENT = "neflare-cn-ssh-geo-update/1.0"


@dataclass(frozen=True)
class ParsedData:
    ipv4: List[str]
    ipv6: List[str]
    raw_ipv4_records: int
    raw_ipv6_records: int


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def fetch_apnic_text(timeout: float = 30.0) -> str:
    request = urllib.request.Request(APNIC_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="strict")


def iter_cn_networks(text: str) -> ParsedData:
    ipv4_networks: List[ipaddress._BaseNetwork] = []
    ipv6_networks: List[ipaddress._BaseNetwork] = []
    raw_ipv4 = 0
    raw_ipv6 = 0

    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 7:
            continue
        registry, cc, record_type, start, value, _, status = parts
        if registry != "apnic" or cc != "CN" or status not in {"allocated", "assigned"}:
            continue

        if record_type == "ipv4":
            raw_ipv4 += 1
            count = int(value)
            first = int(ipaddress.IPv4Address(start))
            last = first + count - 1
            if count <= 0:
                raise ValueError(f"invalid IPv4 record size for {start}: {value}")
            first_addr = ipaddress.IPv4Address(first)
            last_addr = ipaddress.IPv4Address(last)
            ipv4_networks.extend(ipaddress.summarize_address_range(first_addr, last_addr))
        elif record_type == "ipv6":
            raw_ipv6 += 1
            prefixlen = int(value)
            ipv6_networks.append(ipaddress.IPv6Network(f"{start}/{prefixlen}", strict=False))

    collapsed_v4 = [str(net) for net in ipaddress.collapse_addresses(ipv4_networks)]
    collapsed_v6 = [str(net) for net in ipaddress.collapse_addresses(ipv6_networks)]

    if not collapsed_v4:
        raise ValueError("No mainland-China IPv4 allocations were parsed from APNIC data.")

    return ParsedData(
        ipv4=collapsed_v4,
        ipv6=collapsed_v6,
        raw_ipv4_records=raw_ipv4,
        raw_ipv6_records=raw_ipv6,
    )


def format_elements(networks: Iterable[str], indent: str = "        ", wrap: int = 6) -> str:
    items = list(networks)
    if not items:
        return indent
    lines: List[str] = []
    for index in range(0, len(items), wrap):
        chunk = items[index : index + wrap]
        lines.append(indent + ", ".join(chunk))
    return ",\n".join(lines)


def render_set_file(parsed: ParsedData) -> str:
    ipv4_elements = format_elements(parsed.ipv4)
    ipv6_elements = format_elements(parsed.ipv6)
    return f"""set cn_ssh_v4 {{
    type ipv4_addr
    flags interval
    auto-merge
    elements = {{
{ipv4_elements}
    }}
}}
set cn_ssh_v6 {{
    type ipv6_addr
    flags interval
    auto-merge
    elements = {{
{ipv6_elements}
    }}
}}
"""


def write_text(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def build_metadata(parsed: ParsedData) -> dict:
    return {
        "fetched_at": utc_now(),
        "source_url": APNIC_URL,
        "verification_model": "https-transport-and-strict-parsing-only",
        "raw_ipv4_records": parsed.raw_ipv4_records,
        "raw_ipv6_records": parsed.raw_ipv6_records,
        "collapsed_ipv4_prefixes": len(parsed.ipv4),
        "collapsed_ipv6_prefixes": len(parsed.ipv6),
    }


def contains_ip(parsed: ParsedData, value: str) -> bool:
    address = ipaddress.ip_address(value)
    networks = parsed.ipv6 if address.version == 6 else parsed.ipv4
    return any(address in ipaddress.ip_network(network, strict=False) for network in networks)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="Destination path for rendered nftables set declarations")
    parser.add_argument("--metadata", help="Destination path for metadata JSON")
    parser.add_argument("--contains-ip", help="Check whether the given IP falls inside the parsed mainland-China allocations")
    args = parser.parse_args(argv)

    text = fetch_apnic_text()
    parsed = iter_cn_networks(text)
    if args.contains_ip:
        return 0 if contains_ip(parsed, args.contains_ip) else 1
    if not args.output or not args.metadata:
        raise ValueError("--output and --metadata are required unless --contains-ip is used")
    write_text(args.output, render_set_file(parsed))
    write_text(args.metadata, json.dumps(build_metadata(parsed), indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI error path
        print(f"cn_ssh_geo_update.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
