#!/usr/bin/env python3

from __future__ import annotations

from typing import Any


MESSAGES = {
    "en": {
        "bot_token_missing": "BOT_TOKEN is not configured; bot service will exit safely.",
        "reality_switched": "REALITY domain switched to {domain}",
        "repeat_confirm": "Repeat /{action} within {ttl} seconds to confirm.",
        "repeat_confirm_command": "Repeat {command} within {ttl} seconds to confirm.",
        "xray_restarted": "Xray restarted successfully.",
        "xray_disabled": "Xray-backed protocols are disabled.",
        "reboot_accepted": "Reboot command accepted and queued.",
        "yes": "yes",
        "no": "no",
    },
    "zh": {
        "bot_token_missing": "未配置 BOT_TOKEN；Bot 服务将安全退出。",
        "reality_switched": "REALITY 域名已切换为 {domain}",
        "repeat_confirm": "请在 {ttl} 秒内再次发送 /{action} 以确认。",
        "repeat_confirm_command": "请在 {ttl} 秒内再次发送 {command} 以确认。",
        "xray_restarted": "Xray 已成功重启。",
        "xray_disabled": "当前未启用由 Xray 承载的协议。",
        "reboot_accepted": "重启命令已提交并进入队列。",
        "yes": "是",
        "no": "否",
    },
}


def lang(config: Any) -> str:
    value = str(getattr(config, "ui_lang", "en") or "en").strip().lower()
    return "zh" if value.startswith("zh") else "en"


def tr(config: Any, key: str, **kwargs: Any) -> str:
    locale = lang(config)
    template = MESSAGES.get(locale, MESSAGES["en"]).get(key, MESSAGES["en"].get(key, key))
    return template.format(**kwargs)


def bool_text(config: Any, value: bool) -> str:
    return tr(config, "yes" if value else "no")
