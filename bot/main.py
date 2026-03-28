#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime

from commands import bind_chat, format_chat_candidates, handle_message
from config import load_config
from i18n import tr
from maintenance import (
    format_lint_log_text,
    format_repo_log_text,
    format_test_log_text,
    format_tests_text,
    run_repo_sync,
    run_repo_sync_and_notify,
    run_network_test,
    run_network_test_and_notify,
    run_reality_lint_watch,
)
from reports import daily_text, quota_clear, quota_set, quota_text, status_text
from state import load_last_daily_marker, load_offset, save_last_daily_marker, save_offset
from telegram_api import TelegramAPI


def pending_daily_marker(config) -> str | None:
    if not config.chat_id:
        return None
    now = datetime.now(config.report_tz)
    marker = now.strftime("%Y-%m-%d")
    if now.strftime("%H:%M") != config.report_time:
        return None
    if load_last_daily_marker(config) == marker:
        return None
    return marker


def run_poll_loop(config) -> int:
    if not config.bot_token:
        print(tr(config, "bot_token_missing"), file=sys.stderr)
        return 0

    api = TelegramAPI(config.bot_token)
    try:
        api.call("deleteWebhook", {"drop_pending_updates": "false"})
    except Exception:
        pass

    offset = load_offset(config)
    while True:
        try:
            daily_marker = pending_daily_marker(config)
            if daily_marker:
                api.send_text(config.chat_id, daily_text(config))
                save_last_daily_marker(config, daily_marker)

            updates = api.get_updates(offset)
            for update in updates:
                offset = int(update["update_id"]) + 1
                save_offset(config, offset)
                message = update.get("message") or {}
                response = handle_message(config, message)
                if response:
                    chat_id = str((message.get("chat") or {}).get("id", "")).strip() or config.chat_id
                    if chat_id:
                        api.send_text(chat_id, response)
        except Exception as exc:
            print(f"bot loop error: {exc}", file=sys.stderr)
            time.sleep(3)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="NeFlare Telegram bot")
    parser.add_argument("--list-chat-candidates", action="store_true")
    parser.add_argument("--bind-chat", metavar="CHAT_ID")
    parser.add_argument("--send-daily", action="store_true")
    parser.add_argument("--status-text", action="store_true")
    parser.add_argument("--daily-text", action="store_true")
    parser.add_argument("--quota-text", action="store_true")
    parser.add_argument("--quota-set", nargs="+")
    parser.add_argument("--quota-clear", action="store_true")
    parser.add_argument("--tests-text", action="store_true")
    parser.add_argument("--run-network-test", metavar="TEST_ID")
    parser.add_argument("--run-network-test-and-notify", nargs=2, metavar=("TEST_ID", "CHAT_ID"))
    parser.add_argument("--test-log-text", action="store_true")
    parser.add_argument("--repo-log-text", action="store_true")
    parser.add_argument("--run-repo-sync", action="store_true")
    parser.add_argument("--run-repo-sync-and-notify", nargs=1, metavar=("CHAT_ID",))
    parser.add_argument("--lint-log-text", action="store_true")
    parser.add_argument("--run-reality-lint-watch", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config()

    if args.list_chat_candidates:
        print(format_chat_candidates(config))
        return 0
    if args.bind_chat:
        print(bind_chat(config, args.bind_chat))
        return 0
    if args.send_daily:
        if not config.bot_token or not config.chat_id:
            raise SystemExit("BOT_TOKEN and CHAT_ID are required for --send-daily")
        TelegramAPI(config.bot_token).send_text(config.chat_id, daily_text(config))
        return 0
    if args.status_text:
        print(status_text(config))
        return 0
    if args.daily_text:
        print(daily_text(config))
        return 0
    if args.quota_text:
        print(quota_text(config))
        return 0
    if args.quota_set:
        if len(args.quota_set) not in {2, 3}:
            raise SystemExit("usage: --quota-set <used_gb> <remain_gb> [next_reset_utc]")
        used = float(args.quota_set[0])
        remain = float(args.quota_set[1])
        next_reset = args.quota_set[2] if len(args.quota_set) == 3 else None
        quota_set(config, used, remain, next_reset)
        print(quota_text(config))
        return 0
    if args.quota_clear:
        quota_clear(config)
        print(quota_text(config))
        return 0
    if args.tests_text:
        print(format_tests_text(config))
        return 0
    if args.run_network_test:
        try:
            print(run_network_test(config, args.run_network_test)["text"])
            return 0
        except Exception as exc:
            print(f"network test failed: {exc}", file=sys.stderr)
            return 1
    if args.run_network_test_and_notify:
        test_id, chat_id = args.run_network_test_and_notify
        try:
            print(run_network_test_and_notify(config, test_id, chat_id)["text"])
            return 0
        except Exception as exc:
            print(f"network test notify job failed: {exc}", file=sys.stderr)
            return 1
    if args.test_log_text:
        print(format_test_log_text(config))
        return 0
    if args.repo_log_text:
        print(format_repo_log_text(config))
        return 0
    if args.run_repo_sync:
        try:
            print(run_repo_sync(config)["text"])
            return 0
        except Exception as exc:
            print(f"repo sync failed: {exc}", file=sys.stderr)
            return 1
    if args.run_repo_sync_and_notify:
        try:
            print(run_repo_sync_and_notify(config, args.run_repo_sync_and_notify[0])["text"])
            return 0
        except Exception as exc:
            print(f"repo sync notify job failed: {exc}", file=sys.stderr)
            return 1
    if args.lint_log_text:
        print(format_lint_log_text(config))
        return 0
    if args.run_reality_lint_watch:
        result = run_reality_lint_watch(config)
        if result.get("notify") and config.bot_token and config.chat_id:
            TelegramAPI(config.bot_token).send_text(config.chat_id, result["notify_text"])
        print(result["log_text"])
        return 0 if result["exit_code"] == 0 else result["exit_code"]
    return run_poll_loop(config)


if __name__ == "__main__":
    raise SystemExit(main())
