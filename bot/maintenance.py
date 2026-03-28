#!/usr/bin/env python3

from __future__ import annotations

import os
import secrets
import shutil
import subprocess
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List

from config import Config
from state import json_path, load_json, save_json

NEFLARECTL_PATH = "/usr/local/bin/neflarectl"
REALITY_POLICY_STATE_FILE = "reality-policy.json"
REALITY_LINT_SNAPSHOT_FILE = "reality-lint-snapshot.json"
REALITY_LINT_LOG_FILE = "reality-lint-log.json"
NETWORK_TEST_LOG_FILE = "network-test-log.json"
NETWORK_TEST_ACTIVE_FILE = "network-test-active.json"
REPO_SYNC_LOG_FILE = "repo-sync-log.json"
REPO_SYNC_ACTIVE_FILE = "repo-sync-active.json"
DEFAULT_DOCKER_IMAGE = "debian:bookworm-slim"
SYSTEMD_RUN_PATH = "/usr/bin/systemd-run"
BOT_MAIN_PATH = "/usr/local/lib/neflare-bot/main.py"
DEFAULT_LOG_ENTRY_LIMIT = 50

TEST_CATALOG: Dict[str, Dict[str, str]] = {
    "unlock_media": {
        "id": "unlock_media",
        "title": "check.unlock.media",
        "command": "bash <(curl -L -s check.unlock.media)",
    },
    "media_check_place": {
        "id": "media_check_place",
        "title": "Media.Check.Place",
        "command": "bash <(curl -sL Media.Check.Place)",
    },
    "region_restriction": {
        "id": "region_restriction",
        "title": "RegionRestrictionCheck",
        "command": "bash <(curl -L -s https://github.com/1-stream/RegionRestrictionCheck/raw/main/check.sh)",
    },
    "ip_quality": {
        "id": "ip_quality",
        "title": "IP.Check.Place",
        "command": "bash <(curl -sL IP.Check.Place)",
    },
}


def is_zh(config: Config) -> bool:
    return str(getattr(config, "ui_lang", "en") or "en").strip().lower().startswith("zh")


def ui_text(config: Config, zh: str, en: str) -> str:
    return zh if is_zh(config) else en


def docker_bin() -> str:
    candidate = shutil.which("docker")
    if candidate:
        return candidate
    for raw in ("/usr/bin/docker", "/usr/local/bin/docker", "/bin/docker"):
        if os.path.isfile(raw) and os.access(raw, os.X_OK):
            return raw
    raise RuntimeError(
        "docker CLI is not installed or not reachable in PATH. "
        "Install a package that provides the docker client binary and rerun install.sh."
    )


def docker_argv(*args: str) -> List[str]:
    return [docker_bin(), *args]


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def trim_text(value: str, limit: int = 2000) -> str:
    text = (value or "").strip()
    if len(text) <= limit:
        return text
    return text[: limit - 20].rstrip() + "\n...[truncated]"


def stable_unique(values: List[str]) -> List[str]:
    seen = set()
    result: List[str] = []
    for value in values:
        item = str(value or "").strip()
        if not item or item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def append_log(config: Config, file_name: str, entry: Dict[str, Any], limit: int = 50) -> None:
    path = json_path(config, file_name)
    rows = load_json(path, [])
    rows.insert(0, entry)
    persist_bounded_log(config, file_name, rows[:limit])


def read_recent_log(config: Config, file_name: str) -> List[Dict[str, Any]]:
    return prune_log_file(config, file_name)


def parse_logged_timestamp(value: Any) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def bounded_non_negative_int(value: Any, default: int) -> int:
    try:
        parsed = int(value)
    except Exception:
        return max(default, 0)
    return max(parsed, 0)


def retention_days(config: Config) -> int:
    return bounded_non_negative_int(getattr(config, "bot_log_retention_days", 14), 14)


def log_max_bytes(config: Config) -> int:
    return bounded_non_negative_int(getattr(config, "bot_log_max_bytes", 65536), 65536)


def bounded_log_rows(config: Config, rows: List[Dict[str, Any]], limit: int = DEFAULT_LOG_ENTRY_LIMIT) -> List[Dict[str, Any]]:
    bounded = list(rows[:limit])
    keep_days = retention_days(config)
    if keep_days <= 0:
        return bounded

    cutoff = datetime.now(timezone.utc) - timedelta(days=keep_days)
    filtered: List[Dict[str, Any]] = []
    for row in bounded:
        stamp = parse_logged_timestamp(row.get("finished_at") or row.get("started_at"))
        if stamp is None or stamp >= cutoff:
            filtered.append(row)
    return filtered


def persist_bounded_log(config: Config, file_name: str, rows: List[Dict[str, Any]], limit: int = DEFAULT_LOG_ENTRY_LIMIT) -> List[Dict[str, Any]]:
    path = json_path(config, file_name)
    bounded = bounded_log_rows(config, rows, limit=limit)
    max_bytes = log_max_bytes(config)

    if not bounded:
        if os.path.isfile(path):
            os.remove(path)
        return []

    while True:
        save_json(path, bounded)
        if max_bytes <= 0 or len(bounded) <= 1 or os.path.getsize(path) <= max_bytes:
            return bounded
        bounded = bounded[:-1]


def prune_log_file(config: Config, file_name: str, limit: int = DEFAULT_LOG_ENTRY_LIMIT) -> List[Dict[str, Any]]:
    path = json_path(config, file_name)
    rows = load_json(path, [])
    if not rows:
        return []
    return persist_bounded_log(config, file_name, rows, limit=limit)


def prune_test_containers() -> None:
    subprocess.run(
        docker_argv("container", "prune", "-f", "--filter", "label=neflare.ephemeral-test=1"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=False,
    )


def cleanup_bot_state(config: Config) -> None:
    prune_log_file(config, REALITY_LINT_LOG_FILE)
    prune_log_file(config, NETWORK_TEST_LOG_FILE)
    prune_log_file(config, REPO_SYNC_LOG_FILE)
    load_active_network_test(config)
    load_active_repo_sync(config)


def available_network_tests() -> List[Dict[str, str]]:
    return [TEST_CATALOG[key] for key in sorted(TEST_CATALOG.keys())]


def normalize_test_id(raw: str) -> str:
    candidate = str(raw or "").strip().lower()
    for old in ("-", ".", "/", " "):
        candidate = candidate.replace(old, "_")
    if candidate in TEST_CATALOG:
        return candidate
    for item in TEST_CATALOG.values():
        title_value = item["title"].lower()
        for old in ("-", ".", "/", " "):
            title_value = title_value.replace(old, "_")
        if candidate == title_value:
            return item["id"]
    return candidate


def require_known_test(raw: str) -> Dict[str, str]:
    test_id = normalize_test_id(raw)
    if test_id not in TEST_CATALOG:
        known = ", ".join(item["id"] for item in available_network_tests())
        raise ValueError(f"Unknown test '{raw}'. Known tests: {known}")
    return TEST_CATALOG[test_id]


def docker_tests_enabled(config: Config) -> bool:
    return str(getattr(config, "enable_docker_tests", "no") or "no").strip().lower() == "yes"


def require_docker_tests_enabled(config: Config) -> None:
    if not docker_tests_enabled(config):
        raise RuntimeError(
            "Disposable Docker-backed tests are disabled. Set ENABLE_DOCKER_TESTS=yes and rerun install.sh."
        )


def active_network_test_path(config: Config) -> str:
    return json_path(config, NETWORK_TEST_ACTIVE_FILE)


def systemd_unit_state(unit_name: str) -> str:
    if not unit_name:
        return ""
    proc = subprocess.run(
        ["systemctl", "show", "--property=ActiveState", "--value", unit_name],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=15,
        check=False,
    )
    if proc.returncode != 0:
        return ""
    return str(proc.stdout or "").strip().lower()


def load_active_network_test(config: Config) -> Dict[str, Any]:
    payload = load_json(active_network_test_path(config), {})
    unit_name = str(payload.get("unit_name", "")).strip()
    if not unit_name:
        return {}
    if systemd_unit_state(unit_name) in {"active", "activating", "reloading"}:
        return payload
    clear_active_network_test(config)
    return {}


def save_active_network_test(config: Config, payload: Dict[str, Any]) -> None:
    save_json(active_network_test_path(config), payload)


def clear_active_network_test(config: Config) -> None:
    path = active_network_test_path(config)
    if os.path.isfile(path):
        os.remove(path)


def active_repo_sync_path(config: Config) -> str:
    return json_path(config, REPO_SYNC_ACTIVE_FILE)


def load_active_repo_sync(config: Config) -> Dict[str, Any]:
    payload = load_json(active_repo_sync_path(config), {})
    unit_name = str(payload.get("unit_name", "")).strip()
    if not unit_name:
        return {}
    if systemd_unit_state(unit_name) in {"active", "activating", "reloading"}:
        return payload
    clear_active_repo_sync(config)
    return {}


def save_active_repo_sync(config: Config, payload: Dict[str, Any]) -> None:
    save_json(active_repo_sync_path(config), payload)


def clear_active_repo_sync(config: Config) -> None:
    path = active_repo_sync_path(config)
    if os.path.isfile(path):
        os.remove(path)


def format_tests_text(config: Config) -> str:
    cleanup_bot_state(config)
    if not docker_tests_enabled(config):
        return ui_text(
            config,
            "\n".join(
                [
                    "网络测试",
                    "",
                    "• 当前未启用一次性 Docker 测试。",
                    "• 将 ENABLE_DOCKER_TESTS=yes 后重新运行 install.sh，即可启用 /test。",
                ]
            ),
            "\n".join(
                [
                    "Network Tests",
                    "",
                    "• Disposable Docker-backed tests are disabled.",
                    "• Set ENABLE_DOCKER_TESTS=yes and rerun install.sh to enable /test.",
                ]
            ),
        )

    lines = [
        ui_text(config, "测试菜单", "Available Tests"),
        "",
        ui_text(config, "• 使用 /test <name> 运行一项测试。", "• Run one with /test <name>."),
        ui_text(
            config,
            "• 每项测试都会在一次性 Docker 容器中执行，使用 host 网络并关闭 Docker 自身防火墙管理。",
            "• Each test runs in a disposable Docker container with host networking and Docker firewall management disabled.",
        ),
        "",
    ]
    active = load_active_network_test(config)
    if active:
        lines.extend(
            [
                ui_text(
                    config,
                    f"• 正在运行：{active.get('title', active.get('test_id', 'unknown'))}",
                    f"• Active job: {active.get('title', active.get('test_id', 'unknown'))}",
                ),
                ui_text(
                    config,
                    f"• 入队时间：{active.get('started_at', 'unknown')}",
                    f"• Queued at: {active.get('started_at', 'unknown')}",
                ),
                "",
            ]
        )
    for item in available_network_tests():
        lines.append(f"• {item['id']}: {item['title']}")
    return "\n".join(lines)


def format_lint_log_text(config: Config, limit: int = 10) -> str:
    cleanup_bot_state(config)
    rows = read_recent_log(config, REALITY_LINT_LOG_FILE)[:limit]
    if not rows:
        return "No reality-lint runs recorded yet."
    lines = ["Recent reality-lint runs"]
    for row in rows:
        status = f"rc={row.get('exit_code', 1)}"
        if row.get("changed"):
            status += ", changed=yes"
        else:
            status += ", changed=no"
        if row.get("warning_level"):
            status += f", level={row['warning_level']}"
        if row.get("recommendation"):
            status += f", rec={row['recommendation']}"
        lines.append(f"- {row.get('started_at', 'unknown')}: {status}")
    return "\n".join(lines)


def format_test_log_text(config: Config, limit: int = 10) -> str:
    cleanup_bot_state(config)
    rows = read_recent_log(config, NETWORK_TEST_LOG_FILE)[:limit]
    active = load_active_network_test(config)
    lines = [ui_text(config, "最近网络测试", "Recent network tests")]
    if active:
        lines.append(
            ui_text(
                config,
                f"• 运行中：{active.get('title', active.get('test_id', 'unknown'))}｜入队 {active.get('started_at', 'unknown')}",
                f"• Running: {active.get('title', active.get('test_id', 'unknown'))}, queued_at={active.get('started_at', 'unknown')}",
            )
        )
    if not rows:
        if len(lines) == 1:
            return ui_text(config, "最近还没有网络测试记录。", "No network tests recorded yet.")
        return "\n".join(lines)
    for row in rows:
        title = row.get("title") or row.get("test_id") or "unknown"
        cleanup = row.get("cleanup_status", "unknown")
        lines.append(
            ui_text(
                config,
                f"• {row.get('started_at', 'unknown')}｜{title}｜退出码 {row.get('exit_code', 1)}｜清理 {cleanup}",
                f"• {row.get('started_at', 'unknown')}: {title}, rc={row.get('exit_code', 1)}, cleanup={cleanup}",
            )
        )
    return "\n".join(lines)


def format_repo_log_text(config: Config, limit: int = 10) -> str:
    cleanup_bot_state(config)
    rows = read_recent_log(config, REPO_SYNC_LOG_FILE)[:limit]
    active = load_active_repo_sync(config)
    lines = [ui_text(config, "最近更新记录", "Recent repo sync jobs")]
    if active:
        lines.append(
            ui_text(
                config,
                f"• 运行中：{active.get('repo_url', 'unknown')}｜分支 {active.get('branch', 'unknown')}｜入队 {active.get('started_at', 'unknown')}",
                f"• Running: {active.get('branch', 'unknown')} from {active.get('repo_url', 'unknown')}, queued_at={active.get('started_at', 'unknown')}",
            )
        )
    if not rows:
        if len(lines) == 1:
            return ui_text(config, "最近还没有更新记录。", "No repo sync jobs recorded yet.")
        return "\n".join(lines)
    for row in rows:
        summary = row.get("summary") or "unknown"
        commit_after = row.get("commit_after") or row.get("commit_before") or "unknown"
        lines.append(
            ui_text(
                config,
                f"• {row.get('started_at', 'unknown')}｜退出码 {row.get('exit_code', 1)}｜提交 {commit_after}｜结果 {summary}",
                f"• {row.get('started_at', 'unknown')}: rc={row.get('exit_code', 1)}, commit={commit_after}, result={summary}",
            )
        )
    return "\n".join(lines)


def extract_policy_snapshot(payload: Dict[str, Any]) -> Dict[str, Any]:
    selected = payload.get("selected") or {}
    dns = selected.get("dns") or {}
    policy = selected.get("policy") or {}
    return {
        "domain": str(selected.get("domain", "")).strip(),
        "public_port": payload.get("public_port"),
        "compatibility_result": str(selected.get("compatibility_result", "")).strip(),
        "latency_result": str(selected.get("latency_result", "")).strip(),
        "warning_level": str(policy.get("warning_level", "")).strip(),
        "recommendation": str(policy.get("recommendation", "")).strip(),
        "apple_related": bool(policy.get("apple_related", False)),
        "likely_cdn": bool(selected.get("likely_cdn", False)),
        "tls13": bool(selected.get("tls13", False)),
        "san_match": bool(selected.get("san_match", False)),
        "unresolved_warnings": stable_unique([str(item) for item in policy.get("unresolved_warnings", [])]),
        "discouraged_patterns": stable_unique([str(item) for item in policy.get("discouraged_patterns", [])]),
        "certificate_sans": stable_unique([str(item) for item in selected.get("certificate_sans", [])]),
        "dns_cname": stable_unique([str(item) for item in dns.get("cname", [])]),
    }


def load_policy_snapshot(config: Config) -> Dict[str, Any]:
    path = Path(config.neflare_state_dir) / REALITY_POLICY_STATE_FILE
    payload = load_json(str(path), {})
    if not payload:
        return {}
    return extract_policy_snapshot(payload)


def diff_snapshots(previous: Dict[str, Any], current: Dict[str, Any]) -> List[str]:
    keys = [
        "domain",
        "public_port",
        "compatibility_result",
        "latency_result",
        "warning_level",
        "recommendation",
        "apple_related",
        "likely_cdn",
        "tls13",
        "san_match",
        "unresolved_warnings",
        "discouraged_patterns",
        "certificate_sans",
        "dns_cname",
    ]
    lines: List[str] = []
    for key in keys:
        if previous.get(key) != current.get(key):
            lines.append(f"- {key}: {previous.get(key, 'none')} -> {current.get(key, 'none')}")
    return lines


def format_lint_notification(result: Dict[str, Any]) -> str:
    lines = [
        "reality-lint watcher",
        f"Started: {result['started_at']}",
        f"Finished: {result['finished_at']}",
        f"Exit code: {result['exit_code']}",
    ]
    if result.get("domain"):
        lines.append(f"Domain: {result['domain']}")
    if result.get("warning_level"):
        lines.append(f"Warning level: {result['warning_level']}")
    if result.get("recommendation"):
        lines.append(f"Recommendation: {result['recommendation']}")
    if result.get("changed"):
        lines.append("Detected meaningful policy drift:")
        lines.extend(result.get("diff_lines") or ["- snapshot changed"])
    if result.get("stderr"):
        lines.extend(["", "stderr:", trim_text(result["stderr"], limit=1200)])
    return "\n".join(lines)


def run_reality_lint_watch(config: Config) -> Dict[str, Any]:
    cleanup_bot_state(config)
    started_at = utc_now()
    previous = load_json(json_path(config, REALITY_LINT_SNAPSHOT_FILE), {})
    proc = subprocess.run(
        [NEFLARECTL_PATH, "reality-lint"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=240,
        check=False,
    )
    current = load_policy_snapshot(config)
    if current:
        save_json(json_path(config, REALITY_LINT_SNAPSHOT_FILE), current)
    initialized = bool(current) and not previous
    changed = bool(previous) and bool(current) and current != previous
    diff_lines = diff_snapshots(previous, current) if changed else []
    entry = {
        "started_at": started_at,
        "finished_at": utc_now(),
        "exit_code": proc.returncode,
        "initialized": initialized,
        "changed": changed,
        "domain": current.get("domain", ""),
        "warning_level": current.get("warning_level", ""),
        "recommendation": current.get("recommendation", ""),
        "compatibility_result": current.get("compatibility_result", ""),
        "latency_result": current.get("latency_result", ""),
    }
    append_log(config, REALITY_LINT_LOG_FILE, entry)
    notify = proc.returncode != 0 or changed
    message_entry = {
        **entry,
        "stderr": trim_text(proc.stderr, limit=1600),
        "diff_lines": diff_lines,
    }
    return {
        **message_entry,
        "notify": notify,
        "notify_text": format_lint_notification(message_entry) if notify else "",
        "log_text": format_lint_notification(message_entry),
    }


def ensure_docker_runtime(config: Config) -> None:
    require_docker_tests_enabled(config)
    deadline = time.monotonic() + 60
    last_error = ""
    while True:
        proc = subprocess.run(
            docker_argv("version", "--format", "{{.Server.Version}}"),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            check=False,
        )
        if proc.returncode == 0:
            return
        last_error = trim_text(proc.stderr or proc.stdout, limit=500)
        if time.monotonic() >= deadline:
            raise RuntimeError(last_error or "docker is not installed or the daemon is not reachable")
        time.sleep(2)


def image_exists(image: str) -> bool:
    proc = subprocess.run(
        docker_argv("image", "inspect", image),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=False,
    )
    return proc.returncode == 0


def cleanup_container(container_name: str) -> None:
    subprocess.run(
        docker_argv("rm", "-f", container_name),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        check=False,
    )


def cleanup_image_if_pulled(image: str, existed_before: bool) -> str:
    if existed_before:
        return "left pre-existing image untouched"
    if not image_exists(image):
        return "no pulled image remained"
    proc = subprocess.run(
        docker_argv("image", "rm", "-f", image),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        check=False,
    )
    if proc.returncode == 0:
        return "removed pulled image"
    return "failed to remove pulled image"


def run_network_test(config: Config, raw_test_id: str) -> Dict[str, Any]:
    test = require_known_test(raw_test_id)
    cleanup_bot_state(config)
    active_repo = load_active_repo_sync(config)
    if active_repo:
        raise RuntimeError(
            f"repo sync is already running from {active_repo.get('repo_url', 'unknown')} (queued at {active_repo.get('started_at', 'unknown')})"
        )
    ensure_docker_runtime(config)
    started_at = utc_now()
    container_name = f"neflare-test-{test['id']}-{secrets.token_hex(4)}"
    image = DEFAULT_DOCKER_IMAGE
    existed_before = image_exists(image)
    prune_test_containers()
    shell_script = "\n".join(
        [
            "set -Eeuo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update -y >/dev/null",
            "apt-get install -y --no-install-recommends bash ca-certificates curl dnsutils iproute2 jq procps python3 >/dev/null",
            test["command"],
        ]
    )
    output = ""
    exit_code = 1
    timeout_hit = False
    try:
        proc = subprocess.run(
            docker_argv(
                "run",
                "--name",
                container_name,
                "--rm",
                "--network",
                "host",
                "--label",
                "neflare.ephemeral-test=1",
                "--log-driver",
                "none",
                "--security-opt",
                "no-new-privileges",
                "--cap-drop",
                "ALL",
                "--pids-limit",
                "256",
                "--memory",
                "768m",
                "--cpus",
                "1.0",
                image,
                "bash",
                "-lc",
                shell_script,
            ),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=1800,
            check=False,
        )
        output = proc.stdout or ""
        exit_code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        timeout_hit = True
        output = (exc.stdout or "") + "\n[host] docker test timed out"
        exit_code = 124
    finally:
        cleanup_container(container_name)
        prune_test_containers()
        cleanup_status = cleanup_image_if_pulled(image, existed_before)

    finished_at = utc_now()
    trimmed_output = trim_text(output, limit=32000) or "(no output)"
    entry = {
        "started_at": started_at,
        "finished_at": finished_at,
        "test_id": test["id"],
        "title": test["title"],
        "exit_code": exit_code,
        "cleanup_status": cleanup_status,
        "timeout": timeout_hit,
    }
    append_log(config, NETWORK_TEST_LOG_FILE, entry)

    header_lines = [
        ui_text(config, f"网络测试：{test['title']} ({test['id']})", f"Network test: {test['title']} ({test['id']})"),
        ui_text(config, f"开始时间：{started_at}", f"Started: {started_at}"),
        ui_text(config, f"结束时间：{finished_at}", f"Finished: {finished_at}"),
        ui_text(config, f"退出码：{exit_code}", f"Exit code: {exit_code}"),
        ui_text(config, f"清理结果：已移除临时容器；{cleanup_status}", f"Cleanup: removed temp container; {cleanup_status}"),
    ]
    if timeout_hit:
        header_lines.append(
            ui_text(
                config,
                "宿主机提示：容器在完成前超时退出。",
                "Host note: the container timed out before completion.",
            )
        )
    header_lines.extend(["", trimmed_output])
    return {
        **entry,
        "text": "\n".join(header_lines),
    }


def queue_network_test(config: Config, raw_test_id: str, chat_id: str) -> str:
    test = require_known_test(raw_test_id)
    cleanup_bot_state(config)
    active_repo = load_active_repo_sync(config)
    if active_repo:
        return ui_text(
            config,
            f"当前已有更新任务正在运行：{active_repo.get('repo_url', 'unknown')}｜入队时间 {active_repo.get('started_at', 'unknown')}。",
            f"Repo sync is already running from {active_repo.get('repo_url', 'unknown')} (queued at {active_repo.get('started_at', 'unknown')}).",
        )
    ensure_docker_runtime(config)
    active = load_active_network_test(config)
    if active:
        title = active.get("title") or active.get("test_id") or "unknown"
        started = active.get("started_at", "unknown")
        return ui_text(
            config,
            f"当前已有测试在运行：{title}｜入队时间 {started}。",
            f"Another network test is already running: {title} (queued at {started}).",
        )

    unit_name = f"neflare-network-test-{test['id']}-{secrets.token_hex(4)}"
    started_at = utc_now()
    save_active_network_test(
        config,
        {
            "unit_name": unit_name,
            "started_at": started_at,
            "test_id": test["id"],
            "title": test["title"],
            "chat_id": str(chat_id).strip(),
        },
    )
    proc = subprocess.run(
        [
            SYSTEMD_RUN_PATH,
            "--unit",
            unit_name,
            "--collect",
            "--property=WorkingDirectory=/usr/local/lib/neflare-bot",
            "/usr/bin/python3",
            BOT_MAIN_PATH,
            "--run-network-test-and-notify",
            test["id"],
            str(chat_id).strip(),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        clear_active_network_test(config)
        raise RuntimeError(trim_text(proc.stderr or proc.stdout, limit=800) or "failed to queue network test")

    return "\n".join(
        [
            ui_text(config, f"已加入测试队列：{test['title']} ({test['id']})", f"Queued network test: {test['title']} ({test['id']})"),
            ui_text(config, f"入队时间：{started_at}", f"Queued at: {started_at}"),
            ui_text(config, "后台任务完成后，结果会自动回传到当前聊天。", "The result will be sent back here when the background job finishes."),
        ]
    )


def run_network_test_and_notify(config: Config, raw_test_id: str, chat_id: str) -> Dict[str, Any]:
    from telegram_api import TelegramAPI

    cleanup_bot_state(config)
    api = TelegramAPI(config.bot_token) if config.bot_token and chat_id else None
    try:
        result = run_network_test(config, raw_test_id)
        if api:
            api.send_text(str(chat_id).strip(), result["text"])
        return result
    except Exception as exc:
        if api:
            api.send_text(
                str(chat_id).strip(),
                ui_text(config, f"网络测试失败：{exc}", f"Network test failed: {exc}"),
            )
        raise
    finally:
        clear_active_network_test(config)


def run_checked(argv: List[str], cwd: str | None = None, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        argv,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(trim_text((proc.stdout or "") + ("\n" if proc.stdout and proc.stderr else "") + (proc.stderr or ""), limit=3000))
    return proc


def git_head(repo_dir: str) -> str:
    proc = subprocess.run(
        ["git", "-C", repo_dir, "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        return ""
    return str(proc.stdout or "").strip()


def git_subject(repo_dir: str) -> str:
    proc = subprocess.run(
        ["git", "-C", repo_dir, "log", "-1", "--pretty=%s"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        return ""
    return str(proc.stdout or "").strip()


def ensure_repo_checkout(config: Config) -> str:
    repo_url = str(config.repo_sync_url or "").strip()
    branch = str(config.repo_sync_branch or "main").strip() or "main"
    repo_dir = Path(str(config.repo_sync_dir or "/opt/Neflare-Xbot").strip() or "/opt/Neflare-Xbot")
    if not repo_url:
        raise RuntimeError("REPO_SYNC_URL is empty")
    if not branch:
        raise RuntimeError("REPO_SYNC_BRANCH is empty")
    if not repo_dir.is_absolute() or str(repo_dir) == "/":
        raise RuntimeError("REPO_SYNC_DIR must be an absolute non-root path")

    if repo_dir.exists():
        if not (repo_dir / ".git").is_dir():
            raise RuntimeError(f"{repo_dir} exists but is not a git checkout")
        remote = run_checked(["git", "-C", str(repo_dir), "remote", "get-url", "origin"], timeout=30).stdout.strip()
        if remote != repo_url:
            raise RuntimeError(f"existing origin {remote} does not match configured REPO_SYNC_URL {repo_url}")
        run_checked(["git", "-C", str(repo_dir), "fetch", "--depth=1", "origin", branch], timeout=300)
        run_checked(["git", "-C", str(repo_dir), "checkout", "-f", "-B", branch, f"origin/{branch}"], timeout=60)
        run_checked(["git", "-C", str(repo_dir), "reset", "--hard", f"origin/{branch}"], timeout=60)
        run_checked(["git", "-C", str(repo_dir), "clean", "-fd"], timeout=60)
    else:
        repo_dir.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        run_checked(
            ["git", "clone", "--depth=1", "--branch", branch, repo_url, str(repo_dir)],
            timeout=600,
        )
    return str(repo_dir)


def format_repo_sync_notification(result: Dict[str, Any]) -> str:
    config = result["config"]
    lines = [
        ui_text(config, "仓库更新任务", "Repo Sync Job"),
        ui_text(config, f"开始时间：{result['started_at']}", f"Started: {result['started_at']}"),
        ui_text(config, f"结束时间：{result['finished_at']}", f"Finished: {result['finished_at']}"),
        ui_text(config, f"退出码：{result['exit_code']}", f"Exit code: {result['exit_code']}"),
        ui_text(config, f"仓库：{result.get('repo_url', 'unknown')}", f"Repo: {result.get('repo_url', 'unknown')}"),
        ui_text(config, f"分支：{result.get('branch', 'unknown')}", f"Branch: {result.get('branch', 'unknown')}"),
        ui_text(config, f"目录：{result.get('repo_dir', 'unknown')}", f"Directory: {result.get('repo_dir', 'unknown')}"),
    ]
    if result.get("commit_before"):
        lines.append(ui_text(config, f"更新前提交：{result['commit_before']}", f"Commit before: {result['commit_before']}"))
    if result.get("commit_after"):
        lines.append(ui_text(config, f"更新后提交：{result['commit_after']}", f"Commit after: {result['commit_after']}"))
    if result.get("summary"):
        lines.append(ui_text(config, f"摘要：{result['summary']}", f"Summary: {result['summary']}"))
    if result.get("stdout"):
        lines.extend(
            [
                "",
                ui_text(config, "输出日志：", "stdout/stderr:"),
                trim_text(result["stdout"], limit=10000),
            ]
        )
    return "\n".join(lines)


def run_repo_sync(config: Config) -> Dict[str, Any]:
    cleanup_bot_state(config)
    active_test = load_active_network_test(config)
    if active_test:
        raise RuntimeError(
            f"network test {active_test.get('title', active_test.get('test_id', 'unknown'))} is still running"
        )

    started_at = utc_now()
    repo_url = str(config.repo_sync_url or "").strip()
    branch = str(config.repo_sync_branch or "main").strip() or "main"
    repo_dir = str(config.repo_sync_dir or "/opt/Neflare-Xbot").strip() or "/opt/Neflare-Xbot"
    stdout_chunks: List[str] = []
    commit_before = ""
    commit_after = ""
    exit_code = 1
    summary = "failed"

    try:
        existing_dir = Path(repo_dir)
        if existing_dir.is_dir() and (existing_dir / ".git").is_dir():
            commit_before = git_head(repo_dir)
            subject_before = git_subject(repo_dir)
            if commit_before:
                stdout_chunks.append(f"[repo] current HEAD before sync: {commit_before} {subject_before}".strip())
        repo_dir = ensure_repo_checkout(config)
        if not commit_before:
            commit_before = git_head(repo_dir)

        install_proc = subprocess.run(
            [
                "bash",
                "./install.sh",
                "--config",
                config.neflare_config_file or "/etc/neflare/neflare.env",
                "--non-interactive",
            ],
            cwd=repo_dir,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=1800,
            check=False,
        )
        stdout_chunks.append((install_proc.stdout or "").strip())
        if install_proc.stderr:
            stdout_chunks.append((install_proc.stderr or "").strip())
        exit_code = install_proc.returncode
        commit_after = git_head(repo_dir)
        subject_after = git_subject(repo_dir)
        summary = (
            ui_text(config, "已强制同步并成功重新应用配置", "force-synced and reapplied successfully")
            if exit_code == 0
            else ui_text(config, "仓库已同步，但 install.sh 重新执行失败", "repo synced, but install.sh rerun failed")
        )
        if commit_after:
            summary = f"{summary}; HEAD={commit_after} {subject_after}".strip()
    except Exception as exc:
        stdout_chunks.append(str(exc))
        exit_code = 1
        if Path(repo_dir).is_dir():
            commit_after = git_head(repo_dir)
        summary = ui_text(config, "仓库更新失败", "repo sync failed")

    finished_at = utc_now()
    log_entry = {
        "started_at": started_at,
        "finished_at": finished_at,
        "exit_code": exit_code,
        "repo_url": repo_url,
        "branch": branch,
        "repo_dir": repo_dir,
        "commit_before": commit_before,
        "commit_after": commit_after,
        "summary": summary,
    }
    append_log(config, REPO_SYNC_LOG_FILE, log_entry)
    message_entry = {
        **log_entry,
        "config": config,
        "stdout": trim_text("\n\n".join(chunk for chunk in stdout_chunks if chunk), limit=12000),
    }
    return {
        **message_entry,
        "text": format_repo_sync_notification(message_entry),
    }


def queue_repo_sync(config: Config, chat_id: str) -> str:
    cleanup_bot_state(config)
    active = load_active_repo_sync(config)
    if active:
        return ui_text(
            config,
            f"当前已有更新任务在运行：{active.get('repo_url', 'unknown')}｜入队时间 {active.get('started_at', 'unknown')}。",
            f"Another repo sync job is already running from {active.get('repo_url', 'unknown')} (queued at {active.get('started_at', 'unknown')}).",
        )
    active_test = load_active_network_test(config)
    if active_test:
        return ui_text(
            config,
            f"网络测试仍在运行：{active_test.get('title', active_test.get('test_id', 'unknown'))}｜入队时间 {active_test.get('started_at', 'unknown')}。",
            f"Network test {active_test.get('title', active_test.get('test_id', 'unknown'))} is still running (queued at {active_test.get('started_at', 'unknown')}).",
        )

    unit_name = f"neflare-repo-sync-{secrets.token_hex(4)}"
    started_at = utc_now()
    save_active_repo_sync(
        config,
        {
            "unit_name": unit_name,
            "started_at": started_at,
            "repo_url": str(config.repo_sync_url or "").strip(),
            "branch": str(config.repo_sync_branch or "main").strip() or "main",
            "chat_id": str(chat_id).strip(),
        },
    )
    proc = subprocess.run(
        [
            SYSTEMD_RUN_PATH,
            "--unit",
            unit_name,
            "--collect",
            "--property=WorkingDirectory=/usr/local/lib/neflare-bot",
            "/usr/bin/python3",
            BOT_MAIN_PATH,
            "--run-repo-sync-and-notify",
            str(chat_id).strip(),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        clear_active_repo_sync(config)
        raise RuntimeError(trim_text(proc.stderr or proc.stdout, limit=800) or "failed to queue repo sync")

    return "\n".join(
        [
            ui_text(
                config,
                f"已加入强制更新队列：{str(config.repo_sync_url or '').strip() or 'unknown'}",
                f"Queued force-sync update from {str(config.repo_sync_url or '').strip() or 'unknown'}",
            ),
            ui_text(
                config,
                f"• 分支：{str(config.repo_sync_branch or 'main').strip() or 'main'}",
                f"• Branch: {str(config.repo_sync_branch or 'main').strip() or 'main'}",
            ),
            ui_text(config, f"• 入队时间：{started_at}", f"• Queued at: {started_at}"),
            ui_text(
                config,
                "• 本次会强制对齐远端分支，并覆盖服务器 checkout 中的本地改动。",
                "• This run force-aligns the checkout to the remote branch and overwrites local checkout changes.",
            ),
            ui_text(config, "• 后台任务完成后，结果会自动回传到当前聊天。", "• The result will be sent back here when the background job finishes."),
        ]
    )


def run_repo_sync_and_notify(config: Config, chat_id: str) -> Dict[str, Any]:
    from telegram_api import TelegramAPI

    cleanup_bot_state(config)
    api = TelegramAPI(config.bot_token) if config.bot_token and chat_id else None
    try:
        result = run_repo_sync(config)
        if api:
            api.send_text(str(chat_id).strip(), result["text"])
        return result
    except Exception as exc:
        if api:
            api.send_text(
                str(chat_id).strip(),
                ui_text(config, f"仓库更新失败：{exc}", f"Repo sync failed: {exc}"),
            )
        raise
    finally:
        clear_active_repo_sync(config)
