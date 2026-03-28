#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import shlex
from datetime import datetime, timezone
from typing import Any, Dict, List

from config import Config


def ensure_dir(path: str) -> None:
    os.makedirs(path, mode=0o700, exist_ok=True)


def json_path(config: Config, name: str) -> str:
    ensure_dir(config.bot_state_dir)
    return os.path.join(config.bot_state_dir, name)


def quota_path(config: Config) -> str:
    ensure_dir(config.neflare_state_dir)
    return os.path.join(config.neflare_state_dir, "quota.json")


def runtime_override_path(config: Config) -> str:
    return json_path(config, "runtime.env")


def load_json(path: str, default: Any) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def save_json(path: str, payload: Any) -> None:
    ensure_dir(os.path.dirname(path))
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp_path, path)
    os.chmod(path, 0o600)


def load_offset(config: Config) -> int:
    path = json_path(config, "offset.txt")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return int(handle.read().strip())
    except Exception:
        return 0


def save_offset(config: Config, value: int) -> None:
    path = json_path(config, "offset.txt")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(str(value))
    os.chmod(path, 0o600)


def chat_candidates_path(config: Config) -> str:
    return json_path(config, "chat-candidates.json")


def register_chat_candidate(config: Config, message: Dict[str, Any]) -> None:
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    if not chat_id:
        return
    rows = load_json(chat_candidates_path(config), [])
    record = {
        "chat_id": chat_id,
        "type": str(chat.get("type", "")).strip(),
        "title": str(chat.get("title", "")).strip(),
        "username": str(chat.get("username", "")).strip(),
        "first_name": str(chat.get("first_name", "")).strip(),
        "last_name": str(chat.get("last_name", "")).strip(),
        "last_seen_text": datetime.now(config.report_tz).strftime("%Y-%m-%d %H:%M:%S"),
        "last_seen_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    rows = [row for row in rows if str(row.get("chat_id", "")).strip() != chat_id]
    rows.insert(0, record)
    save_json(chat_candidates_path(config), rows[:50])


def list_chat_candidates(config: Config) -> List[Dict[str, Any]]:
    return load_json(chat_candidates_path(config), [])


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def update_env_value(path: str, key: str, value: str) -> None:
    lines: List[str] = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    rendered = f"{key}={shell_quote(str(value))}"
    updated: List[str] = []
    found = False
    for line in lines:
        if line.startswith(f"{key}="):
            updated.append(rendered)
            found = True
        else:
            updated.append(line)
    if not found:
        updated.append(rendered)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(updated).rstrip() + "\n")
    os.replace(tmp, path)
    os.chmod(path, 0o600)


def try_update_env_value(path: str, key: str, value: str) -> bool:
    try:
        update_env_value(path, key, value)
        return True
    except OSError:
        return False


def bind_chat_id(config: Config, chat_id: str) -> None:
    try_update_env_value(config.neflare_config_file, "CHAT_ID", chat_id)
    try_update_env_value(config.neflare_config_file, "BOT_BIND_TOKEN", "")
    bot_env = os.environ.get("NEFLARE_BOT_ENV", "/etc/neflare/bot.env")
    if os.path.isfile(bot_env):
        try_update_env_value(bot_env, "CHAT_ID", chat_id)
        try_update_env_value(bot_env, "BOT_BIND_TOKEN", "")
    update_env_value(runtime_override_path(config), "CHAT_ID", chat_id)
    update_env_value(runtime_override_path(config), "BOT_BIND_TOKEN", "")


def valid_hhmm(value: str) -> bool:
    return bool(re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", str(value or "").strip()))


def settings_path(config: Config) -> str:
    return json_path(config, "settings.json")


def default_runtime_settings(config: Config) -> Dict[str, Any]:
    fallback_time = str(getattr(config, "report_time", "") or "").strip()
    if not valid_hhmm(fallback_time):
        fallback_time = "08:00"
    return {
        "daily_notify_time": fallback_time,
    }


def load_runtime_settings(config: Config) -> Dict[str, Any]:
    payload = load_json(settings_path(config), default_runtime_settings(config))
    defaults = default_runtime_settings(config)
    changed = False
    if not isinstance(payload, dict):
        payload = dict(defaults)
        changed = True
    for key, value in defaults.items():
        if key not in payload:
            payload[key] = value
            changed = True
    if not valid_hhmm(str(payload.get("daily_notify_time", ""))):
        payload["daily_notify_time"] = defaults["daily_notify_time"]
        changed = True
    if changed:
        save_json(settings_path(config), payload)
    return payload


def save_runtime_settings(config: Config, payload: Dict[str, Any]) -> Dict[str, Any]:
    defaults = default_runtime_settings(config)
    merged = dict(defaults)
    merged.update(payload or {})
    if not valid_hhmm(str(merged.get("daily_notify_time", ""))):
        merged["daily_notify_time"] = defaults["daily_notify_time"]
    save_json(settings_path(config), merged)
    return merged


def countdown_path(config: Config) -> str:
    return json_path(config, "countdown.json")


def load_countdown(config: Config) -> Dict[str, Any]:
    payload = load_json(countdown_path(config), {})
    if not isinstance(payload, dict):
        return {}
    return payload


def save_countdown(config: Config, payload: Dict[str, Any]) -> Dict[str, Any]:
    save_json(countdown_path(config), payload)
    return payload


def clear_countdown(config: Config) -> None:
    path = countdown_path(config)
    if os.path.isfile(path):
        os.remove(path)


def confirmations_path(config: Config) -> str:
    return json_path(config, "confirmations.json")


def load_confirmations(config: Config) -> Dict[str, float]:
    return load_json(confirmations_path(config), {})


def save_confirmations(config: Config, payload: Dict[str, float]) -> None:
    save_json(confirmations_path(config), payload)


def last_daily_path(config: Config) -> str:
    return json_path(config, "last-daily-sent.txt")


def load_last_daily_marker(config: Config) -> str:
    try:
        with open(last_daily_path(config), "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except Exception:
        return ""


def save_last_daily_marker(config: Config, value: str) -> None:
    with open(last_daily_path(config), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(value)
    os.chmod(last_daily_path(config), 0o600)
