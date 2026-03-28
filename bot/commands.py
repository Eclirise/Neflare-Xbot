#!/usr/bin/env python3

from __future__ import annotations

from typing import Any, Dict

from actions import queue_repo_update, reboot_server, require_confirmation, restart_xray, set_reality
from config import Config
from i18n import bool_text, tr
from maintenance import (
    format_lint_log_text,
    format_repo_log_text,
    format_test_log_text,
    format_tests_text,
    normalize_test_id,
    queue_network_test,
)
from reality import reality_test
from reports import daily_text, quota_text, status_text
from state import bind_chat_id, list_chat_candidates, register_chat_candidate


def help_text(config: Config) -> str:
    lines = [
        tr(config, "help_header"),
        "/start",
        "/help",
        "/chat_ids",
        "/status",
        "/daily",
        "/quota",
        "/reality_test <domain>",
        "/reality_set <domain>",
        "/lint_log",
        "/update_repo",
        "/update_log",
        "/restart_xray",
        "/reboot",
    ]
    if str(config.enable_docker_tests).strip().lower() == "yes":
        lines.extend(
            [
                "/tests",
                "/test <name>",
                "/test_log",
            ]
        )
    return "\n".join(lines)


def format_chat_candidates(config: Config) -> str:
    rows = list_chat_candidates(config)
    if not rows:
        return tr(config, "no_chat_candidates")
    lines = []
    for row in rows:
        parts = [
            f"{tr(config, 'chat_id_label')}={row.get('chat_id', '')}",
            f"{tr(config, 'type_label')}={row.get('type', '') or 'unknown'}",
        ]
        if row.get("title"):
            parts.append(f"{tr(config, 'title_label')}={row['title']}")
        if row.get("username"):
            parts.append(f"{tr(config, 'username_label')}=@{row['username']}")
        if row.get("last_seen_utc"):
            parts.append(f"{tr(config, 'last_seen_label')}={row['last_seen_utc']}")
        lines.append(" | ".join(parts))
    return "\n".join(lines)


def chat_candidates_text(config: Config) -> str:
    return "\n".join([tr(config, "chat_candidates_header"), format_chat_candidates(config)])


def format_reality_candidate(config: Config, candidate: Dict[str, Any]) -> str:
    discouraged = ", ".join(candidate.get("discouraged_patterns") or []) or tr(config, "none")
    unresolved = "; ".join(candidate.get("unresolved_warnings") or []) or tr(config, "none")
    return "\n".join(
        [
            tr(config, "reality_target", domain=candidate["domain"]),
            tr(config, "compatibility_result", value=candidate.get("compatibility_result", "unknown")),
            tr(config, "latency_result", value=candidate.get("latency_result", "unknown")),
            tr(config, "policy_warning_level", value=candidate.get("policy_warning_level", "unknown")),
            tr(config, "policy_recommendation", value=candidate.get("policy", {}).get("recommendation", "unknown")),
            tr(config, "discouraged_patterns", value=discouraged),
            tr(config, "apple_related", value=bool_text(config, bool(candidate.get("apple_related")))),
            tr(config, "summary_label", value=candidate.get("summary", "")),
            tr(config, "unresolved_warnings", value=unresolved),
        ]
    )


def report_tz_label(config: Config) -> str:
    return str(getattr(config.report_tz, "key", "") or config.report_tz)


def unbound_start_text(config: Config, message: Dict[str, Any]) -> str:
    register_chat_candidate(config, message)
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    chat_type = str(chat.get("type", "")).strip().lower()
    if chat_type != "private":
        return "\n".join(
            [
                tr(config, "unbound_intro"),
                tr(config, "unbound_private_required"),
                tr(config, "current_chat_id", chat_id=chat_id),
                "",
                chat_candidates_text(config),
            ]
        )
    lines = [
        tr(config, "unbound_intro"),
        tr(config, "current_chat_id", chat_id=chat_id),
        "",
        chat_candidates_text(config),
    ]
    if config.bot_bind_token:
        lines.extend(["", tr(config, "unbound_claim_hint", token=config.bot_bind_token)])
    else:
        lines.extend(["", tr(config, "unbound_claim_missing")])
    return "\n".join(lines)


def claim_chat(config: Config, message: Dict[str, Any], token: str) -> str:
    chat = message.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    chat_type = str(chat.get("type", "")).strip().lower()
    if chat_type != "private":
        return tr(config, "claim_private_required")
    if not config.bot_bind_token:
        return tr(config, "unbound_claim_missing")
    if str(token).strip() != str(config.bot_bind_token).strip():
        return tr(config, "claim_token_invalid")
    bind_chat_id(config, chat_id)
    config.chat_id = chat_id
    config.bot_bind_token = ""
    return "\n".join(
        [
            tr(config, "claim_success", chat_id=chat_id),
            tr(config, "daily_schedule", time=config.report_time, tz=report_tz_label(config)),
            "",
            help_text(config),
        ]
    )


def startup_text(config: Config) -> str:
    return "\n".join(
        [
            tr(config, "startup_notice"),
            tr(config, "authorized_chat", chat_id=config.chat_id or tr(config, "none")),
            tr(config, "daily_schedule", time=config.report_time, tz=report_tz_label(config)),
            "",
            help_text(config),
        ]
    )


def is_authorized(config: Config, chat_id: str) -> bool:
    return bool(config.chat_id) and str(config.chat_id).strip() == str(chat_id).strip()


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
        if command == "/start":
            return unbound_start_text(config, message)
        if command == "/claim":
            if len(parts) != 2:
                return tr(config, "claim_usage")
            return claim_chat(config, message, parts[1])
        return None

    if not is_authorized(config, chat_id):
        return None

    if command in {"/start", "/help"}:
        return help_text(config)
    if command == "/chat_ids":
        return chat_candidates_text(config)
    if command == "/status":
        return status_text(config)
    if command == "/daily":
        return daily_text(config)
    if command == "/quota":
        return quota_text(config)
    if command == "/reality_test":
        if len(parts) != 2:
            return tr(config, "usage_reality_test")
        try:
            result = reality_test(parts[1])
            candidate = result["candidates"][0]
            return format_reality_candidate(config, candidate)
        except Exception as exc:
            return tr(config, "reality_test_failed", error=exc)
    if command == "/reality_set":
        if len(parts) != 2:
            return tr(config, "usage_reality_set")
        try:
            result = reality_test(parts[1])
            candidate = result["candidates"][0]
            try:
                outcome = set_reality(config, parts[1])
                return "\n".join([outcome, "", format_reality_candidate(config, candidate)])
            except Exception as exc:
                return "\n".join([tr(config, "reality_set_failed", error=exc), "", format_reality_candidate(config, candidate)])
        except Exception as exc:
            return tr(config, "reality_set_failed", error=exc)
    if command == "/tests":
        return format_tests_text(config)
    if command == "/test":
        if len(parts) != 2:
            return "Usage: /test <name>\nUse /tests to list supported checks."
        test_id = normalize_test_id(parts[1])
        confirmed, prompt = require_confirmation(
            config,
            chat_id,
            f"test:{test_id}",
            confirm_command=f"/test {test_id}",
        )
        if not confirmed:
            return prompt
        try:
            return queue_network_test(config, test_id, chat_id)
        except Exception as exc:
            return f"/test failed: {exc}"
    if command == "/lint_log":
        return format_lint_log_text(config)
    if command == "/update_log":
        return format_repo_log_text(config)
    if command == "/update_repo":
        confirmed, prompt = require_confirmation(config, chat_id, "update_repo", confirm_command="/update_repo")
        if not confirmed:
            return prompt
        try:
            return queue_repo_update(config, chat_id)
        except Exception as exc:
            return f"/update_repo failed: {exc}"
    if command == "/test_log":
        return format_test_log_text(config)
    if command == "/restart_xray":
        confirmed, prompt = require_confirmation(config, chat_id, "restart_xray", confirm_command="/restart_xray")
        if not confirmed:
            return prompt
        try:
            return restart_xray(config)
        except Exception as exc:
            return tr(config, "restart_failed", error=exc)
    if command == "/reboot":
        confirmed, prompt = require_confirmation(config, chat_id, "reboot", confirm_command="/reboot")
        if not confirmed:
            return prompt
        try:
            return reboot_server(config)
        except Exception as exc:
            return tr(config, "reboot_failed", error=exc)
    return tr(config, "unknown_command")


def bind_chat(config: Config, chat_id: str) -> str:
    bind_chat_id(config, chat_id)
    config.chat_id = str(chat_id).strip()
    return tr(config, "bound_chat", chat_id=chat_id)
