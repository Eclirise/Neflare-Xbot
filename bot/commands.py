#!/usr/bin/env python3

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict

from actions import queue_repo_update, reboot_server, require_confirmation, restart_xray, set_reality
from config import Config
from maintenance import (
    format_repo_log_text,
    format_test_log_text,
    format_tests_text,
    normalize_test_id,
    queue_network_test,
)
from reality import reality_test
from reports import (
    countdown_snapshot,
    countdown_text,
    daily_text,
    health_text,
    iso_utc,
    quota_set,
    quota_text,
    report_tz_label,
    status_text,
)
from state import (
    bind_chat_id,
    clear_countdown,
    list_chat_candidates,
    load_countdown,
    load_runtime_settings,
    register_chat_candidate,
    save_countdown,
    save_runtime_settings,
    valid_hhmm,
)


def is_zh(config: Config) -> bool:
    return str(getattr(config, "ui_lang", "en") or "en").strip().lower().startswith("zh")


def text_by_lang(config: Config, zh: str, en: str) -> str:
    return zh if is_zh(config) else en


def format_chat_candidates(config: Config) -> str:
    rows = list_chat_candidates(config)
    if not rows:
        return text_by_lang(config, "还没有记录到聊天候选。", "No chat candidates recorded yet.")
    lines = []
    for row in rows:
        parts = [
            f"chat_id={row.get('chat_id', '')}",
            f"type={row.get('type', '') or 'unknown'}",
        ]
        title = str(row.get("title", "")).strip()
        if title:
            parts.append(f"title={title}")
        name = " ".join(
            item for item in [str(row.get("first_name", "")).strip(), str(row.get("last_name", "")).strip()] if item
        ).strip()
        if name:
            parts.append(f"name={name}")
        username = str(row.get("username", "")).strip()
        if username:
            parts.append(f"username=@{username}")
        seen = str(row.get("last_seen_text", "")).strip() or str(row.get("last_seen_utc", "")).strip()
        if seen:
            parts.append(f"last_seen={seen}")
        lines.append(" | ".join(parts))
    return "\n".join(lines)


def chat_candidates_text(config: Config) -> str:
    return text_by_lang(
        config,
        "\n".join(["最近记录到的聊天候选", "", format_chat_candidates(config)]),
        "\n".join(["Seen chat candidates", "", format_chat_candidates(config)]),
    )


def help_text(config: Config) -> str:
    lines = [
        text_by_lang(config, "控制台", "Control Panel"),
        "",
        text_by_lang(config, "入口", "Entry"),
        "• /start",
        "• /help",
        "",
        text_by_lang(config, "概览", "Overview"),
        f"• /status      {text_by_lang(config, '状态总览', 'status overview')}",
        f"• /daily       {text_by_lang(config, '每日视图', 'daily view')}",
        f"• /quota       {text_by_lang(config, '配额详情', 'quota details')}",
        f"• /health      {text_by_lang(config, '系统状态', 'system health')}",
        "",
        text_by_lang(config, "设置", "Settings"),
        f"• /settings    {text_by_lang(config, '设置菜单', 'settings menu')}",
        f"• /notify      {text_by_lang(config, '通知设置', 'notification settings')}",
        f"• /countdown   {text_by_lang(config, '倒计时设置', 'countdown settings')}",
        f"• /calibrate   {text_by_lang(config, '流量校准', 'quota calibration')}",
        "",
        "REALITY",
        f"• /reality_test <domain>   {text_by_lang(config, '测试目标', 'test target')}",
        f"• /reality_set <domain>    {text_by_lang(config, '应用目标', 'apply target')}",
        "",
    ]
    if str(config.enable_docker_tests).strip().lower() == "yes":
        lines.extend(
            [
                text_by_lang(config, "测试", "Tests"),
                f"• /tests       {text_by_lang(config, '测试菜单', 'test menu')}",
                f"• /test <name> {text_by_lang(config, '运行网络测试', 'run network test')}",
                f"• /test_log    {text_by_lang(config, '测试记录', 'test history')}",
                "",
            ]
        )
    lines.extend(
        [
            text_by_lang(config, "运维", "Ops"),
            f"• /update_repo {text_by_lang(config, '强制同步更新', 'force sync update')}",
            f"• /update_log  {text_by_lang(config, '更新记录', 'update history')}",
            f"• /restart_xray {text_by_lang(config, '重启 Xray', 'restart Xray')}",
            "",
            text_by_lang(config, "绑定", "Binding"),
            f"• /chat_ids    {text_by_lang(config, '查看候选聊天', 'show candidate chats')}",
            f"• /claim <token> {text_by_lang(config, '绑定当前私聊', 'bind this private chat')}",
            "",
            text_by_lang(config, "控制", "Control"),
            f"• /reboot      {text_by_lang(config, '重启确认', 'reboot confirmation')}",
        ]
    )
    return "\n".join(lines)


def format_reality_candidate(config: Config, candidate: Dict[str, Any]) -> str:
    discouraged = ", ".join(candidate.get("discouraged_patterns") or []) or text_by_lang(config, "无", "none")
    unresolved = "; ".join(candidate.get("unresolved_warnings") or []) or text_by_lang(config, "无", "none")
    policy = candidate.get("policy", {}) if isinstance(candidate.get("policy"), dict) else {}
    if is_zh(config):
        return "\n".join(
            [
                "REALITY 测试结果",
                "",
                f"• 目标：{candidate.get('domain', '')}",
                f"• 兼容性：{candidate.get('compatibility_result', 'unknown')}",
                f"• 延迟/稳定性：{candidate.get('latency_result', 'unknown')}",
                f"• 风险级别：{policy.get('warning_level', 'unknown')}",
                f"• 策略建议：{policy.get('recommendation', 'unknown')}",
                f"• Apple/iCloud 相关：{'是' if candidate.get('apple_related') else '否'}",
                f"• 不建议模式：{discouraged}",
                f"• 未解决警告：{unresolved}",
                f"• 摘要：{candidate.get('summary', '')}",
            ]
        )
    return "\n".join(
        [
            "REALITY Test Result",
            "",
            f"• Target: {candidate.get('domain', '')}",
            f"• Compatibility: {candidate.get('compatibility_result', 'unknown')}",
            f"• Latency/Stability: {candidate.get('latency_result', 'unknown')}",
            f"• Warning level: {policy.get('warning_level', 'unknown')}",
            f"• Policy recommendation: {policy.get('recommendation', 'unknown')}",
            f"• Apple/iCloud related: {'yes' if candidate.get('apple_related') else 'no'}",
            f"• Discouraged patterns: {discouraged}",
            f"• Unresolved warnings: {unresolved}",
            f"• Summary: {candidate.get('summary', '')}",
        ]
    )


def settings_text(config: Config) -> str:
    settings = load_runtime_settings(config)
    countdown = countdown_snapshot(config)
    countdown_line = text_by_lang(config, "未设置", "not configured")
    if countdown.get("active"):
        countdown_line = (
            f"{countdown['target_text']}｜{countdown['message']}"
            if is_zh(config)
            else f"{countdown['target_text']} | {countdown['message']}"
        )
    if is_zh(config):
        return "\n".join(
            [
                "设置",
                "",
                "通知",
                f"• 每日报告：{settings['daily_notify_time']}（{report_tz_label(config)}）",
                "",
                "倒计时",
                f"• 当前：{countdown_line}",
                "",
                "流量与校准",
                "• /quota 查看配额详情",
                "• /calibrate 查看校准命令",
                "",
                "子菜单",
                "• /notify",
                "• /countdown",
                "• /calibrate",
            ]
        )
    return "\n".join(
        [
            "Settings",
            "",
            "Notifications",
            f"• Daily report: {settings['daily_notify_time']} ({report_tz_label(config)})",
            "",
            "Countdown",
            f"• Current: {countdown_line}",
            "",
            "Traffic & Calibration",
            "• /quota for quota details",
            "• /calibrate for calibration commands",
            "",
            "Submenus",
            "• /notify",
            "• /countdown",
            "• /calibrate",
        ]
    )


def notify_text(config: Config) -> str:
    settings = load_runtime_settings(config)
    return text_by_lang(
        config,
        "\n".join(
            [
                "通知设置",
                "",
                f"• 每日报告时间：{settings['daily_notify_time']}（{report_tz_label(config)}）",
                "",
                "修改方式",
                "• /set daily_time 07:51",
                "• /set daily_time 08:30",
            ]
        ),
        "\n".join(
            [
                "Notification Settings",
                "",
                f"• Daily report time: {settings['daily_notify_time']} ({report_tz_label(config)})",
                "",
                "Update with",
                "• /set daily_time 07:51",
                "• /set daily_time 08:30",
            ]
        ),
    )


def calibrate_text(config: Config) -> str:
    return text_by_lang(
        config,
        "\n".join(
            [
                "流量校准",
                "",
                "用途",
                "• 用面板数据修正月度已用 / 剩余",
                "• 适合 vnStat 安装较晚、累计不完整时使用",
                "",
                "命令",
                "• /quota_set <已用GB> <剩余GB> [下次重置UTC]",
                "• /quota_clear",
            ]
        ),
        "\n".join(
            [
                "Quota Calibration",
                "",
                "Purpose",
                "• Correct used/remaining monthly quota with panel values",
                "• Useful when vnStat started late or the cycle is incomplete",
                "",
                "Commands",
                "• /quota_set <used_gb> <remain_gb> [next_reset_utc]",
                "• /quota_clear",
            ]
        ),
    )


def unbound_start_text(config: Config, message: Dict[str, Any]) -> str:
    register_chat_candidate(config, message)
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    chat_type = str(chat.get("type", "")).strip() or "unknown"
    title = str(chat.get("title", "")).strip()
    username = str(chat.get("username", "")).strip()
    first_name = str(chat.get("first_name", "")).strip()
    last_name = str(chat.get("last_name", "")).strip()
    display_name = " ".join(item for item in [first_name, last_name] if item).strip()

    lines = [
        text_by_lang(config, "当前还没有绑定管理员聊天。", "No admin chat is bound yet."),
        "",
        f"• chat_id: {chat_id}",
        f"• type: {chat_type}",
    ]
    if title:
        lines.append(f"• title: {title}")
    if display_name:
        lines.append(f"• name: {display_name}")
    if username:
        lines.append(f"• username: @{username}")
    lines.extend(["", chat_candidates_text(config)])
    if config.bot_bind_token:
        lines.extend(
            [
                "",
                text_by_lang(config, "绑定方式", "Binding"),
                f"• /claim {config.bot_bind_token}",
            ]
        )
    else:
        lines.extend(
            [
                "",
                text_by_lang(config, "未生成 BOT_BIND_TOKEN，可在 VPS 上手动绑定。", "BOT_BIND_TOKEN is missing; bind on the VPS manually."),
                "• sudo neflarectl list-chat-candidates",
                "• sudo neflarectl bind-chat <chat_id>",
                "• sudo systemctl restart neflare-bot",
            ]
        )
    return "\n".join(lines)


def claim_chat(config: Config, message: Dict[str, Any], token: str) -> str:
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    chat_type = str(chat.get("type", "")).strip().lower()
    if chat_type != "private":
        return text_by_lang(config, "请在私聊里完成绑定。", "Claiming must be done from a private chat.")
    if not config.bot_bind_token:
        return text_by_lang(config, "当前没有可用的绑定令牌。", "No bind token is available.")
    if str(token).strip() != str(config.bot_bind_token).strip():
        return text_by_lang(config, "绑定令牌不正确。", "Bind token is invalid.")
    bind_chat_id(config, chat_id)
    config.chat_id = chat_id
    config.bot_bind_token = ""
    settings = load_runtime_settings(config)
    return "\n".join(
        [
            text_by_lang(config, f"已绑定当前私聊为唯一管理员（CHAT_ID={chat_id}）。", f"Bound this private chat as admin (CHAT_ID={chat_id})."),
            text_by_lang(
                config,
                f"每日报告：{settings['daily_notify_time']}（{report_tz_label(config)}）",
                f"Daily report: {settings['daily_notify_time']} ({report_tz_label(config)})",
            ),
            "",
            help_text(config),
        ]
    )


def startup_text(config: Config) -> str:
    settings = load_runtime_settings(config)
    return "\n".join(
        [
            text_by_lang(config, "NeFlare Bot 已上线。", "NeFlare bot is online."),
            text_by_lang(config, f"当前绑定聊天：{config.chat_id or '未绑定'}", f"Authorized chat: {config.chat_id or 'none'}"),
            text_by_lang(
                config,
                f"每日报告：{settings['daily_notify_time']}（{report_tz_label(config)}）",
                f"Daily report: {settings['daily_notify_time']} ({report_tz_label(config)})",
            ),
            "",
            help_text(config),
        ]
    )


def is_authorized(config: Config, chat_id: str) -> bool:
    return bool(config.chat_id) and str(config.chat_id).strip() == str(chat_id).strip()


def handle_set(config: Config, parts: list[str]) -> str:
    if len(parts) < 3:
        return text_by_lang(
            config,
            "\n".join(
                [
                    "用法",
                    "• /set daily_time 07:51",
                ]
            ),
            "\n".join(
                [
                    "Usage",
                    "• /set daily_time 07:51",
                ]
            ),
        )
    key = parts[1].lower()
    if key != "daily_time":
        return text_by_lang(config, "未知设置项。输入 /settings 查看设置菜单。", "Unknown setting. Use /settings.")
    value = parts[2]
    if not valid_hhmm(value):
        return text_by_lang(config, "用法：/set daily_time 07:51", "Usage: /set daily_time 07:51")
    settings = load_runtime_settings(config)
    settings["daily_notify_time"] = value
    save_runtime_settings(config, settings)
    return "\n".join(
        [
            text_by_lang(config, "已更新通知设置。", "Notification settings updated."),
            "",
            notify_text(config),
        ]
    )


def parse_countdown_target(config: Config, parts: list[str]) -> tuple[datetime, str]:
    if len(parts) < 3:
        raise ValueError(
            text_by_lang(
                config,
                "用法：/countdown_set 2026-04-01 08:30 你的提醒内容",
                "Usage: /countdown_set 2026-04-01 08:30 your reminder text",
            )
        )
    raw_dt = parts[1]
    message_index = 3
    if "T" in raw_dt and valid_hhmm(raw_dt.split("T", 1)[1][:5]):
        raw_target = raw_dt
        message_index = 2
    else:
        if len(parts) < 4:
            raise ValueError(
                text_by_lang(
                    config,
                    "用法：/countdown_set 2026-04-01 08:30 你的提醒内容",
                    "Usage: /countdown_set 2026-04-01 08:30 your reminder text",
                )
            )
        if not valid_hhmm(parts[2]):
            raise ValueError(
                text_by_lang(
                    config,
                    "时间格式应为 HH:MM，例如 08:30。",
                    "Time must use HH:MM, for example 08:30.",
                )
        )
        raw_target = f"{parts[1]}T{parts[2]}"
    if len(parts) <= message_index:
        raise ValueError(text_by_lang(config, "请提供提醒内容。", "Please provide a reminder message."))
    try:
        naive = datetime.strptime(raw_target, "%Y-%m-%dT%H:%M")
    except ValueError as exc:
        raise ValueError(
            text_by_lang(
                config,
                "日期格式应为 YYYY-MM-DD HH:MM。",
                "Date format must be YYYY-MM-DD HH:MM.",
            )
        ) from exc
    target_local = naive.replace(tzinfo=config.report_tz)
    message = " ".join(parts[message_index:]).strip()
    if not message:
        raise ValueError(text_by_lang(config, "请提供提醒内容。", "Please provide a reminder message."))
    if target_local <= datetime.now(config.report_tz):
        raise ValueError(text_by_lang(config, "倒计时目标必须晚于当前时间。", "Countdown target must be in the future."))
    return target_local, message


def handle_countdown_set(config: Config, parts: list[str]) -> str:
    target_local, message = parse_countdown_target(config, parts)
    previous = load_countdown(config)
    created_at = str(previous.get("created_at_utc", "")).strip() or iso_utc(datetime.now(timezone.utc))
    save_countdown(
        config,
        {
            "target_utc": iso_utc(target_local.astimezone(timezone.utc)),
            "message": message,
            "created_at_utc": created_at,
            "updated_at_utc": iso_utc(datetime.now(timezone.utc)),
        },
    )
    return "\n".join(
        [
            text_by_lang(config, "已更新倒计时。", "Countdown updated."),
            "",
            countdown_text(config),
        ]
    )


def handle_message(config: Config, message: Dict[str, Any]) -> str | None:
    text = str(message.get("text", "")).strip()
    if not text:
        return None
    register_chat_candidate(config, message)
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    parts = text.split()
    command = parts[0].lower()

    if not config.chat_id:
        if command == "/chat_ids":
            return chat_candidates_text(config)
        if command in {"/start", "/help"}:
            return unbound_start_text(config, message)
        if command == "/claim":
            if len(parts) != 2:
                return text_by_lang(config, "用法：/claim <token>", "Usage: /claim <token>")
            return claim_chat(config, message, parts[1])
        return None

    if not is_authorized(config, chat_id):
        return None

    if command in {"/", "/start", "/help"}:
        return help_text(config)
    if command == "/chat_ids":
        return chat_candidates_text(config)
    if command == "/status":
        return status_text(config)
    if command == "/daily":
        return daily_text(config)
    if command == "/quota":
        return quota_text(config)
    if command == "/health":
        return health_text(config)
    if command == "/settings":
        return settings_text(config)
    if command == "/notify":
        return notify_text(config)
    if command == "/countdown":
        return countdown_text(config)
    if command == "/calibrate":
        return calibrate_text(config)
    if command == "/set":
        return handle_set(config, parts)
    if command == "/countdown_set":
        try:
            return handle_countdown_set(config, parts)
        except Exception as exc:
            return str(exc)
    if command == "/countdown_clear":
        clear_countdown(config)
        return "\n".join([text_by_lang(config, "已清除倒计时。", "Countdown cleared."), "", countdown_text(config)])
    if command == "/quota_clear":
        from reports import quota_clear

        quota_clear(config)
        return "\n".join([text_by_lang(config, "已清除流量校准偏移。", "Quota calibration offset cleared."), "", quota_text(config)])
    if command == "/quota_set":
        if len(parts) not in {3, 4}:
            return text_by_lang(
                config,
                "用法：/quota_set <已用GB> <剩余GB> [下次重置UTC]",
                "Usage: /quota_set <used_gb> <remain_gb> [next_reset_utc]",
            )
        try:
            used = float(parts[1])
            remain = float(parts[2])
            next_reset = parts[3] if len(parts) == 4 else None
            quota_set(config, used, remain, next_reset)
            return "\n".join([text_by_lang(config, "已完成流量校准。", "Quota calibrated."), "", quota_text(config)])
        except Exception as exc:
            return text_by_lang(config, f"quota_set 失败：{exc}", f"quota_set failed: {exc}")
    if command == "/reality_test":
        if len(parts) != 2:
            return text_by_lang(config, "用法：/reality_test <domain>", "Usage: /reality_test <domain>")
        try:
            result = reality_test(parts[1])
            candidate = result["candidates"][0]
            return format_reality_candidate(config, candidate)
        except Exception as exc:
            return text_by_lang(config, f"/reality_test 失败：{exc}", f"/reality_test failed: {exc}")
    if command == "/reality_set":
        if len(parts) != 2:
            return text_by_lang(config, "用法：/reality_set <domain>", "Usage: /reality_set <domain>")
        try:
            result = reality_test(parts[1])
            candidate = result["candidates"][0]
            try:
                outcome = set_reality(config, parts[1])
                return "\n".join([outcome, "", format_reality_candidate(config, candidate)])
            except Exception as exc:
                return "\n".join(
                    [
                        text_by_lang(config, f"/reality_set 失败：{exc}", f"/reality_set failed: {exc}"),
                        "",
                        format_reality_candidate(config, candidate),
                    ]
                )
        except Exception as exc:
            return text_by_lang(config, f"/reality_set 失败：{exc}", f"/reality_set failed: {exc}")
    if command == "/tests":
        return format_tests_text(config)
    if command == "/test":
        if len(parts) != 2:
            return text_by_lang(config, "用法：/test <name>\n先用 /tests 查看可用测试。", "Usage: /test <name>\nUse /tests first.")
        test_id = normalize_test_id(parts[1])
        confirmed, prompt = require_confirmation(config, chat_id, f"test:{test_id}", confirm_command=f"/test {test_id}")
        if not confirmed:
            return prompt
        try:
            return queue_network_test(config, test_id, chat_id)
        except Exception as exc:
            return text_by_lang(config, f"/test 失败：{exc}", f"/test failed: {exc}")
    if command == "/test_log":
        return format_test_log_text(config)
    if command == "/update_log":
        return format_repo_log_text(config)
    if command == "/update_repo":
        try:
            return queue_repo_update(config, chat_id)
        except Exception as exc:
            return text_by_lang(config, f"/update_repo 失败：{exc}", f"/update_repo failed: {exc}")
    if command == "/restart_xray":
        confirmed, prompt = require_confirmation(config, chat_id, "restart_xray", confirm_command="/restart_xray")
        if not confirmed:
            return prompt
        try:
            return restart_xray(config)
        except Exception as exc:
            return text_by_lang(config, f"/restart_xray 失败：{exc}", f"/restart_xray failed: {exc}")
    if command == "/reboot":
        confirmed, prompt = require_confirmation(config, chat_id, "reboot", confirm_command="/reboot")
        if not confirmed:
            return prompt
        try:
            return reboot_server(config)
        except Exception as exc:
            return text_by_lang(config, f"/reboot 失败：{exc}", f"/reboot failed: {exc}")
    return text_by_lang(config, "未识别命令。输入 /help 查看控制台。", "Unknown command. Use /help.")


def bind_chat(config: Config, chat_id: str) -> str:
    bind_chat_id(config, chat_id)
    config.chat_id = str(chat_id).strip()
    return text_by_lang(config, f"已绑定 CHAT_ID={chat_id}", f"Bound CHAT_ID={chat_id}")
