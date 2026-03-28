#!/usr/bin/env python3

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from typing import Any, Dict, List


class TelegramAPI:
    def __init__(self, token: str):
        self.token = token

    def call(self, method: str, params: Dict[str, Any] | None = None, timeout: int = 70) -> Any:
        data = urllib.parse.urlencode(params or {}).encode()
        request = urllib.request.Request(f"https://api.telegram.org/bot{self.token}/{method}", data=data)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
        if not payload.get("ok"):
            raise RuntimeError(payload)
        return payload["result"]

    def send_message(self, chat_id: str, text: str) -> Any:
        return self.call(
            "sendMessage",
            {
                "chat_id": chat_id,
                "text": text,
                "disable_web_page_preview": "true",
            },
        )

    def send_text(self, chat_id: str, text: str, max_length: int = 3500) -> None:
        for chunk in split_text(text, max_length=max_length):
            self.send_message(chat_id, chunk)

    def get_updates(self, offset: int) -> List[Dict[str, Any]]:
        return self.call(
            "getUpdates",
            {
                "timeout": 50,
                "offset": offset,
                "allowed_updates": json.dumps(["message"]),
            },
            timeout=65,
        )


def split_text(text: str, max_length: int = 3500) -> List[str]:
    content = str(text or "").strip()
    if not content:
        return []
    if len(content) <= max_length:
        return [content]

    chunks: List[str] = []
    remaining = content
    while len(remaining) > max_length:
        split_at = remaining.rfind("\n", 0, max_length)
        if split_at <= 0:
            split_at = max_length
        chunks.append(remaining[:split_at].rstrip())
        remaining = remaining[split_at:].lstrip("\n")
    if remaining:
        chunks.append(remaining)
    return chunks

