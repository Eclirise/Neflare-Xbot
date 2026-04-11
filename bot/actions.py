#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import time
from typing import Tuple

from config import Config
from i18n import tr
from maintenance import queue_repo_sync
from reality import reality_set
from state import load_confirmations, save_confirmations

XRAY_CONFIG_PATH = "/usr/local/etc/xray/config.json"
SYSTEMD_RUN_PATH = "/usr/bin/systemd-run"


def confirmation_key(chat_id: str, action: str) -> str:
    return f"{chat_id}:{action}"


def require_confirmation(
    config: Config,
    chat_id: str,
    action: str,
    ttl_seconds: int = 60,
    confirm_command: str | None = None,
) -> Tuple[bool, str]:
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
    command_text = confirm_command or f"/{action}"
    return False, tr(config, "repeat_confirm_command", command=command_text, ttl=ttl_seconds)


def restart_xray(config: Config) -> str:
    if str(config.enable_vless_reality).strip().lower() != "yes" and str(config.enable_ss2022).strip().lower() != "yes":
        raise RuntimeError(tr(config, "xray_disabled"))
    validate = subprocess.run(
        ["xray", "run", "-test", "-c", XRAY_CONFIG_PATH],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if validate.returncode != 0:
        raise RuntimeError(validate.stderr.strip() or validate.stdout.strip() or "xray config validation failed")
    proc = subprocess.run(["systemctl", "restart", "xray"], capture_output=True, text=True, timeout=60, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "systemctl restart xray failed")
    return tr(config, "xray_restarted")


def delayed_systemctl(action: str, delay_seconds: int = 5) -> None:
    unit_name = f"neflare-{action}-{int(time.time())}"
    proc = subprocess.run(
        [
            SYSTEMD_RUN_PATH,
            "--unit",
            unit_name,
            "--collect",
            f"--on-active={int(delay_seconds)}s",
            "/usr/bin/systemctl",
            action,
        ],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"failed to queue systemctl {action}")


def reboot_server(config: Config) -> str:
    delayed_systemctl("reboot")
    return tr(config, "reboot_accepted")


def set_reality(config: Config, domain: str) -> str:
    return reality_set(config, domain, force=False)


def queue_repo_update(config: Config, chat_id: str) -> str:
    return queue_repo_sync(config, chat_id)
