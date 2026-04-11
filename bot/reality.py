#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
from typing import Any, Dict

from config import Config
from i18n import tr


def run_neflarectl(*args: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/usr/local/bin/neflarectl", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def reality_test(domain: str) -> Dict[str, Any]:
    proc = run_neflarectl("reality-test", "--json", domain)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "reality-test failed")
    return json.loads(proc.stdout)


def reality_set(config: Config, domain: str, force: bool = False) -> str:
    args = ["reality-set", domain]
    if force:
        args.append("--force")
    proc = run_neflarectl(*args, timeout=180)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "reality-set failed")
    return proc.stdout.strip() or tr(config, "reality_switched", domain=domain)


def client_snippet(config: Config) -> str:
    proc = run_neflarectl("print-client", timeout=60)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "print-client failed")
    return proc.stdout.strip()
