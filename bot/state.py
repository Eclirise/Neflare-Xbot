#!/usr/bin/env python3

from __future__ import annotations

import json
import os
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


def bind_chat_id(config: Config, chat_id: str) -> None:
    update_env_value(config.neflare_config_file, "CHAT_ID", chat_id)
    bot_env = os.environ.get("NEFLARE_BOT_ENV", "/etc/neflare/bot.env")
    if os.path.isfile(bot_env):
        update_env_value(bot_env, "CHAT_ID", chat_id)


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
