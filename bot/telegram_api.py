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

