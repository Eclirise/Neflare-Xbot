#!/usr/bin/env python3
"""Probe candidate camouflage domains for Xray REALITY suitability and policy risk."""

from __future__ import annotations

import argparse
import json
import shutil
import socket
import ssl
import statistics
import subprocess
import time
import urllib.parse
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional, Sequence

CDN_HINTS = (
    "cloudflare",
    "akamai",
    "edgekey",
    "edgesuite",
    "fastly",
    "cloudfront",
    "azureedge",
    "cdn77",
    "incapdns",
)

APPLE_PATTERNS = (
    "apple",
    "icloud",
    "me.com",
    "mzstatic",
    "aaplimg",
    "itunes",
    "appstore",
)

TUTORIAL_LIKE_TARGETS = {
    "www.apple.com",
    "gateway.icloud.com",
    "www.icloud.com",
    "www.microsoft.com",
    "www.bing.com",
    "www.cloudflare.com",
}

HIGH_PROFILE_BRAND_HINTS = (
    "apple",
    "icloud",
    "microsoft",
    "bing",
    "google",
    "youtube",
    "amazon",
    "aws",
    "cloudflare",
    "facebook",
    "meta",
    "netflix",
    "telegram",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def normalize_domain(raw: str) -> str:
    candidate = raw.strip()
    if not candidate:
        raise ValueError("blank domain")
    if "://" in candidate:
        candidate = urllib.parse.urlparse(candidate).hostname or ""
    else:
        candidate = candidate.split("/", 1)[0]
    candidate = candidate.strip().rstrip(".")
    if not candidate:
        raise ValueError(f"unable to parse domain from {raw!r}")
    return candidate.lower()


def query_cname(domain: str) -> List[str]:
    if shutil.which("dig") is None:
        return []
    proc = subprocess.run(
        ["dig", "+short", "CNAME", domain],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    return [line.strip().rstrip(".") for line in proc.stdout.splitlines() if line.strip()]


def resolve_addresses(domain: str) -> List[str]:
    infos = socket.getaddrinfo(domain, 443, type=socket.SOCK_STREAM, proto=socket.IPPROTO_TCP)
    addresses: List[str] = []
    seen = set()
    for info in infos:
        address = info[4][0]
        if address not in seen:
            addresses.append(address)
            seen.add(address)
    return addresses


def collect_sans(cert: dict) -> List[str]:
    return [entry[1] for entry in cert.get("subjectAltName", []) if len(entry) >= 2]


def call_xray_tls_ping(domain: str) -> Optional[Dict[str, str]]:
    if shutil.which("xray") is None:
        return None
    try:
        proc = subprocess.run(
            ["xray", "tls", "ping", domain],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except Exception:
        return None
    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip()[:4000],
        "stderr": proc.stderr.strip()[:4000],
    }


@dataclass
class Attempt:
    address: str
    tcp_ok: bool
    tls_ok: bool
    latency_ms: Optional[float]
    tls_version: Optional[str]
    cipher: Optional[str]
    certificate: Optional[dict]
    error: Optional[str]


def probe_address(domain: str, address: str, timeout: float) -> Attempt:
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    start = time.monotonic()
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    tcp_ok = False
    try:
        sock.connect((address, 443))
        tcp_ok = True
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        with context.wrap_socket(sock, server_hostname=domain) as tls_sock:
            latency_ms = round((time.monotonic() - start) * 1000.0, 2)
            return Attempt(
                address=address,
                tcp_ok=True,
                tls_ok=True,
                latency_ms=latency_ms,
                tls_version=tls_sock.version(),
                cipher=tls_sock.cipher()[0] if tls_sock.cipher() else None,
                certificate=tls_sock.getpeercert(),
                error=None,
            )
    except Exception as exc:
        return Attempt(
            address=address,
            tcp_ok=tcp_ok,
            tls_ok=False,
            latency_ms=None,
            tls_version=None,
            cipher=None,
            certificate=None,
            error=str(exc),
        )
    finally:
        try:
            sock.close()
        except Exception:
            pass


def likely_cdn(domain: str, cnames: Iterable[str], sans: Iterable[str]) -> bool:
    joined = " ".join([domain, *cnames, *sans]).lower()
    return any(hint in joined for hint in CDN_HINTS)


def has_any_pattern(values: Sequence[str], patterns: Sequence[str]) -> bool:
    joined = " ".join(values).lower()
    return any(pattern in joined for pattern in patterns)


def summarize_latency(value: Optional[float]) -> str:
    if value is None:
        return "unknown"
    if value <= 80:
        return "low"
    if value <= 180:
        return "moderate"
    return "high"


def summarize_stability(value: Optional[float]) -> str:
    if value is None:
        return "unknown"
    if value <= 10:
        return "stable"
    if value <= 30:
        return "moderately variable"
    return "variable"


def add_finding(findings: List[dict], severity: str, code: str, message: str) -> None:
    findings.append({"severity": severity, "code": code, "message": message})


def severity_rank(severity: str) -> int:
    return {
        "hard_failure": 3,
        "strong_warning": 2,
        "soft_warning": 1,
        "none": 0,
    }.get(severity, 0)


def warning_level(findings: Sequence[dict]) -> str:
    severities = {finding["severity"] for finding in findings}
    if "hard_failure" in severities:
        return "hard failure"
    if "strong_warning" in severities:
        return "strong warning"
    if "soft_warning" in severities:
        return "soft warning"
    return "none"


def recommendation_from_findings(findings: Sequence[dict]) -> str:
    level = warning_level(findings)
    codes = {finding["code"] for finding in findings}
    if level == "hard failure":
        return "incompatible"
    if codes & {"apple_or_icloud_related", "tutorial_like_default", "likely_cdn_fronting"}:
        return "high-risk"
    if "high_profile_brand" in codes or "tls_stability_warning" in codes or "latency_stability_warning" in codes:
        return "discouraged"
    if level == "strong warning":
        if codes & {"apple_or_icloud_related", "tutorial_like_default", "likely_cdn_fronting"}:
            return "high-risk"
        if codes == {"public_port_not_443"}:
            return "acceptable"
        return "discouraged"
    if "latency_high" in codes or "latency_variability_warning" in codes:
        return "acceptable"
    if level == "soft warning":
        return "acceptable"
    return "recommended"


def evaluate_policy(
    *,
    domain: str,
    cnames: Sequence[str],
    sans: Sequence[str],
    public_port: int,
    tls_success: bool,
    tls13: bool,
    san_match: bool,
    tls_success_ratio: float,
    latency_median_ms: Optional[float],
    latency_stdev_ms: Optional[float],
    likely_cdn_fronting: bool,
) -> dict:
    findings: List[dict] = []
    joined_values = [domain, *cnames, *sans]
    apple_related = has_any_pattern(joined_values, APPLE_PATTERNS)
    tutorial_like = domain in TUTORIAL_LIKE_TARGETS
    high_profile_brand = has_any_pattern(joined_values, HIGH_PROFILE_BRAND_HINTS)
    discouraged_patterns: List[str] = []

    if public_port != 443:
        add_finding(
            findings,
            "strong_warning",
            "public_port_not_443",
            f"Public REALITY listener port is {public_port}, not 443. This project treats that as a higher-risk, non-default choice.",
        )
    if not tls_success:
        add_finding(findings, "hard_failure", "tls_handshake_failed", "TLS handshake did not complete reliably enough for REALITY use.")
    if not tls13:
        add_finding(findings, "hard_failure", "tls13_missing", "TLS 1.3 was not observed.")
    if not san_match:
        add_finding(findings, "hard_failure", "san_sni_incompatible", "Target failed SAN/SNI compatibility checks.")
    if tls_success_ratio < 0.67:
        add_finding(findings, "hard_failure", "tls_stability_failed", "Repeated TLS probes were too unstable for a conservative REALITY deployment.")
    elif tls_success_ratio < 1.0:
        add_finding(findings, "strong_warning", "tls_stability_warning", "Some repeated TLS probes failed; stability is not clean.")
    if latency_stdev_ms is not None and latency_stdev_ms > 30:
        add_finding(findings, "strong_warning", "latency_stability_warning", "Latency variation is higher than this project recommends.")
    elif latency_stdev_ms is not None and latency_stdev_ms > 15:
        add_finding(findings, "soft_warning", "latency_variability_warning", "Latency variation is moderate.")
    if latency_median_ms is not None and latency_median_ms > 220:
        add_finding(findings, "soft_warning", "latency_high", "Median latency is high enough to reduce headroom.")
    if likely_cdn_fronting:
        add_finding(findings, "strong_warning", "likely_cdn_fronting", "Likely CDN/fronting behavior detected from CNAME or certificate hints.")
        discouraged_patterns.append("likely CDN/fronting target")
    if apple_related:
        add_finding(findings, "strong_warning", "apple_or_icloud_related", "Target appears Apple/iCloud-related, which this project discourages operationally.")
        discouraged_patterns.append("Apple/iCloud-related")
    if tutorial_like:
        add_finding(findings, "strong_warning", "tutorial_like_default", "Target matches an overused tutorial-style camouflage pattern.")
        discouraged_patterns.append("tutorial-like default")
    if high_profile_brand and not apple_related:
        add_finding(findings, "soft_warning", "high_profile_brand", "Target looks like a high-profile consumer brand frequently seen in community examples.")
        discouraged_patterns.append("high-profile consumer brand")

    level = warning_level(findings)
    recommendation = recommendation_from_findings(findings)
    unresolved = [finding["message"] for finding in findings if finding["severity"] != "none"]
    compatibility_result = "compatible" if all(
        [tls_success, tls13, san_match, tls_success_ratio >= 0.67]
    ) else "incompatible"
    stability_result = "stable"
    if tls_success_ratio < 0.67:
        stability_result = "failed"
    elif tls_success_ratio < 1.0 or (latency_stdev_ms is not None and latency_stdev_ms > 30):
        stability_result = "warning"

    return {
        "warning_level": level,
        "recommendation": recommendation,
        "public_port": public_port,
        "public_port_443": public_port == 443,
        "apple_related": apple_related,
        "tutorial_like": tutorial_like,
        "discouraged_patterns": sorted(set(discouraged_patterns)),
        "findings": findings,
        "unresolved_warnings": unresolved,
        "compatibility_result": compatibility_result,
        "stability_result": stability_result,
    }


def score_candidate(
    *,
    tls_ok: bool,
    tls13: bool,
    san_match: bool,
    median: Optional[float],
    stdev: Optional[float],
    policy: dict,
) -> float:
    if policy["warning_level"] == "hard failure":
        return 0.0
    score = 0.0
    if tls_ok:
        score += 35
    if tls13:
        score += 20
    if san_match:
        score += 20
    if median is not None:
        score += max(0.0, 15.0 - median / 20.0)
    if stdev is not None:
        score += max(0.0, 10.0 - stdev / 5.0)
    if policy["warning_level"] == "strong warning":
        score -= 25
    elif policy["warning_level"] == "soft warning":
        score -= 10
    return round(max(score, 0.0), 2)


def probe_domain(domain: str, attempts: int, timeout: float, public_port: int) -> dict:
    normalized = normalize_domain(domain)
    cnames = query_cname(normalized)
    try:
        addresses = resolve_addresses(normalized)
    except Exception as exc:
        findings = [{"severity": "hard_failure", "code": "dns_resolution_failed", "message": f"DNS resolution failed: {exc}"}]
        policy = {
            "warning_level": "hard failure",
            "recommendation": "incompatible",
            "public_port": public_port,
            "public_port_443": public_port == 443,
            "apple_related": False,
            "tutorial_like": False,
            "discouraged_patterns": [],
            "findings": findings,
            "unresolved_warnings": [findings[0]["message"]],
            "compatibility_result": "incompatible",
            "stability_result": "failed",
        }
        return {
            "domain": normalized,
            "compatible": False,
            "valid": False,
            "score": 0.0,
            "summary": f"incompatible; DNS resolution failed; policy {policy['warning_level']}.",
            "reasons": [findings[0]["message"]],
            "dns": {"addresses": [], "cname": cnames},
            "tcp_success": False,
            "tls_success": False,
            "tls13": False,
            "san_match": False,
            "latency_median_ms": None,
            "latency_stdev_ms": None,
            "tls_success_ratio": 0.0,
            "likely_cdn": False,
            "certificate_subject": [],
            "certificate_sans": [],
            "compatibility_result": "incompatible",
            "latency_result": "failed",
            "policy": policy,
            "policy_warning_level": policy["warning_level"],
            "discouraged_patterns": [],
            "apple_related": False,
            "unresolved_warnings": policy["unresolved_warnings"],
            "attempts": [],
            "xray_tls_ping": call_xray_tls_ping(normalized),
        }

    results: List[Attempt] = []
    for index in range(attempts):
        address = addresses[index % len(addresses)]
        results.append(probe_address(normalized, address, timeout))

    tcp_success = any(item.tcp_ok for item in results)
    successful = [item for item in results if item.tls_ok and item.latency_ms is not None]
    tls_success = bool(successful)
    tls_success_ratio = round(len(successful) / float(len(results) or 1), 3)
    tls13 = any(item.tls_version == "TLSv1.3" for item in successful)
    cert = successful[0].certificate if successful else None
    sans = collect_sans(cert or {})
    san_match = bool(sans) and normalized in {san.lower() for san in sans}
    latency_values = [item.latency_ms for item in successful if item.latency_ms is not None]
    median = round(statistics.median(latency_values), 2) if latency_values else None
    stdev = round(statistics.pstdev(latency_values), 2) if len(latency_values) > 1 else 0.0 if latency_values else None
    cdn_risk = likely_cdn(normalized, cnames, sans)
    policy = evaluate_policy(
        domain=normalized,
        cnames=cnames,
        sans=sans,
        public_port=public_port,
        tls_success=tls_success,
        tls13=tls13,
        san_match=san_match,
        tls_success_ratio=tls_success_ratio,
        latency_median_ms=median,
        latency_stdev_ms=stdev,
        likely_cdn_fronting=cdn_risk,
    )
    compatible = policy["compatibility_result"] == "compatible"
    score = score_candidate(
        tls_ok=tls_success,
        tls13=tls13,
        san_match=san_match,
        median=median,
        stdev=stdev,
        policy=policy,
    )

    reasons = [
        f"DNS resolution {'succeeded' if addresses else 'failed'}",
        f"TCP 443 {'reachable' if tcp_success else 'unreachable'}",
        f"TLS handshake {'succeeded' if tls_success else 'failed'}",
        f"TLS 1.3 {'available' if tls13 else 'not observed'}",
        f"SAN/SNI compatibility {'matched' if san_match else 'did not match'}",
        f"TLS success ratio {tls_success_ratio:.3f}",
    ]
    if median is not None:
        reasons.append(f"Median latency {median} ms ({summarize_latency(median)})")
    if stdev is not None:
        reasons.append(f"Latency variability {stdev} ms ({summarize_stability(stdev)})")

    summary = (
        f"{policy['recommendation']}; "
        f"compatibility {policy['compatibility_result']}; "
        f"latency {summarize_latency(median)}; "
        f"stability {policy['stability_result']}; "
        f"policy {policy['warning_level']}."
    )

    return {
        "domain": normalized,
        "compatible": compatible,
        "valid": compatible,
        "score": score,
        "summary": summary,
        "reasons": reasons,
        "dns": {"addresses": addresses, "cname": cnames},
        "tcp_success": tcp_success,
        "tls_success": tls_success,
        "tls13": tls13,
        "san_match": san_match,
        "latency_median_ms": median,
        "latency_stdev_ms": stdev,
        "tls_success_ratio": tls_success_ratio,
        "likely_cdn": cdn_risk,
        "certificate_subject": cert.get("subject", []) if cert else [],
        "certificate_sans": sans,
        "compatibility_result": policy["compatibility_result"],
        "latency_result": policy["stability_result"],
        "policy": policy,
        "policy_warning_level": policy["warning_level"],
        "discouraged_patterns": policy["discouraged_patterns"],
        "apple_related": policy["apple_related"],
        "unresolved_warnings": policy["unresolved_warnings"],
        "attempts": [
            {
                "address": item.address,
                "tcp_success": item.tcp_ok,
                "tls_success": item.tls_ok,
                "latency_ms": item.latency_ms,
                "tls_version": item.tls_version,
                "cipher": item.cipher,
                "error": item.error,
            }
            for item in results
        ],
        "xray_tls_ping": call_xray_tls_ping(normalized),
    }


def recommendation_rank(value: str) -> int:
    return {
        "recommended": 0,
        "acceptable": 1,
        "discouraged": 2,
        "high-risk": 3,
        "incompatible": 4,
    }.get(value, 9)


def choose_recommended(candidates: List[dict]) -> Optional[str]:
    acceptable = [
        item for item in candidates
        if item["compatible"] and item["policy"]["recommendation"] in {"recommended", "acceptable"}
    ]
    if not acceptable:
        return None
    acceptable.sort(
        key=lambda item: (
            recommendation_rank(item["policy"]["recommendation"]),
            -item["score"],
            item["latency_median_ms"] if item["latency_median_ms"] is not None else 999999,
        )
    )
    return acceptable[0]["domain"]


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--attempts", type=int, default=3, help="Number of repeated TLS trials per domain")
    parser.add_argument("--timeout", type=float, default=5.0, help="Per-connection timeout")
    parser.add_argument("--public-port", type=int, default=443, help="Public REALITY listener port for policy linting")
    parser.add_argument("domains", nargs="+", help="Candidate domains or URLs")
    args = parser.parse_args(argv)

    candidates = [probe_domain(domain, args.attempts, args.timeout, args.public_port) for domain in args.domains]
    payload = {
        "generated_at": utc_now(),
        "public_port": args.public_port,
        "recommended": choose_recommended(candidates),
        "candidates": candidates,
    }

    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for item in candidates:
            print(f"{item['domain']}: {item['summary']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
