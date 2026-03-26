#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import time
from typing import Tuple

from config import Config
from i18n import tr
from reality import reality_set
from state import load_confirmations, save_confirmations


def confirmation_key(chat_id: str, action: str) -> str:
    return f"{chat_id}:{action}"


def require_confirmation(config: Config, chat_id: str, action: str, ttl_seconds: int = 60) -> Tuple[bool, str]:
    now = time.time()
    confirmations = load_confirmations(config)
    key = confirmation_key(chat_id, action)
    expires = float(confirmations.get(key, 0))
    if expires > now:
        confirmations.pop(key, None)
        save_confirmations(config, confirmations)
        return True, ""
    confirmations[key] = now + ttl_seconds
    save_confirmations(config, confirmations)
    return False, tr(config, "repeat_confirm", action=action, ttl=ttl_seconds)


def restart_xray(config: Config) -> str:
    proc = subprocess.run(["systemctl", "restart", "xray"], capture_output=True, text=True, timeout=60, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "systemctl restart xray failed")
    return tr(config, "xray_restarted")


def reboot_server(config: Config) -> str:
    proc = subprocess.run(["systemctl", "reboot"], capture_output=True, text=True, timeout=30, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "systemctl reboot failed")
    return tr(config, "reboot_accepted")


def set_reality(config: Config, domain: str) -> str:
    return reality_set(config, domain, force=False)
