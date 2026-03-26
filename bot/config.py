#!/usr/bin/env python3

from __future__ import annotations

import os
import shlex
from dataclasses import dataclass
from typing import Dict
from zoneinfo import ZoneInfo


def load_env_file(path: str) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if not path or not os.path.isfile(path):
        return data
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            tokens = shlex.split(line, posix=True)
            if not tokens or "=" not in tokens[0]:
                continue
            key, value = tokens[0].split("=", 1)
            data[key.strip()] = value
    return data


@dataclass
class Config:
    ui_lang: str
    bot_token: str
    chat_id: str
    report_time: str
    report_tz: ZoneInfo
    network_interface: str
    quota_monthly_cap_gb: float
    quota_reset_day_utc: int
    neflare_config_file: str
    neflare_state_dir: str
    bot_state_dir: str
    ssh_port: str
    admin_user: str
    server_public_endpoint: str
    reality_selected_domain: str
    xray_listen_port: str
    xray_public_key: str
    xray_uuid: str
    xray_short_ids: str
    enable_ipv6: str
    enable_bot: str


def load_config() -> Config:
    merged: Dict[str, str] = dict(os.environ)
    bot_env = os.environ.get("NEFLARE_BOT_ENV", "/etc/neflare/bot.env")
    merged.update(load_env_file(bot_env))
    neflare_config = merged.get("NEFLARE_CONFIG_FILE", "/etc/neflare/neflare.env")
    merged.update(load_env_file(neflare_config))

    report_tz = merged.get("REPORT_TZ", "UTC") or "UTC"
    ui_lang = str(merged.get("UI_LANG", "en")).strip().lower() or "en"
    ui_lang = "zh" if ui_lang.startswith("zh") else "en"
    return Config(
        ui_lang=ui_lang,
        bot_token=str(merged.get("BOT_TOKEN", "")).strip(),
        chat_id=str(merged.get("CHAT_ID", "")).strip(),
        report_time=str(merged.get("REPORT_TIME", "08:00")).strip() or "08:00",
        report_tz=ZoneInfo(report_tz),
        network_interface=str(merged.get("NETWORK_INTERFACE", "")).strip(),
        quota_monthly_cap_gb=float(merged.get("QUOTA_MONTHLY_CAP_GB", "0") or "0"),
        quota_reset_day_utc=int(merged.get("QUOTA_RESET_DAY_UTC", "1") or "1"),
        neflare_config_file=neflare_config,
        neflare_state_dir=str(merged.get("NEFLARE_STATE_DIR", "/var/lib/neflare")).strip() or "/var/lib/neflare",
        bot_state_dir=str(merged.get("NEFLARE_BOT_STATE_DIR", "/var/lib/neflare-bot")).strip() or "/var/lib/neflare-bot",
        ssh_port=str(merged.get("SSH_PORT", "")).strip(),
        admin_user=str(merged.get("ADMIN_USER", "admin")).strip() or "admin",
        server_public_endpoint=str(merged.get("SERVER_PUBLIC_ENDPOINT", "")).strip(),
        reality_selected_domain=str(merged.get("REALITY_SELECTED_DOMAIN", "")).strip(),
        xray_listen_port=str(merged.get("XRAY_LISTEN_PORT", "443")).strip() or "443",
        xray_public_key=str(merged.get("XRAY_PUBLIC_KEY", "")).strip(),
        xray_uuid=str(merged.get("XRAY_UUID", "")).strip(),
        xray_short_ids=str(merged.get("XRAY_SHORT_IDS", "")).strip(),
        enable_ipv6=str(merged.get("ENABLE_IPV6", "yes")).strip() or "yes",
        enable_bot=str(merged.get("ENABLE_BOT", "no")).strip() or "no",
    )
