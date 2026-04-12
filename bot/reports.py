#!/usr/bin/env python3

from __future__ import annotations

import calendar
import json
import math
import os
import subprocess
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, Tuple

from config import Config
from state import load_countdown, load_json, quota_path, save_json

DAILY_START_HOUR = 5
XRAY_CONFIG_PATH = "/usr/local/etc/xray/config.json"


def is_zh(config: Config) -> bool:
    return str(getattr(config, "ui_lang", "en") or "en").strip().lower().startswith("zh")


def text_by_lang(config: Config, zh: str, en: str) -> str:
    return zh if is_zh(config) else en


def run_text(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()


def run_status(*args: str) -> str:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return ""
    return proc.stdout.strip()


def iso_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(timezone.utc)


def bytes_to_gb(value: float) -> float:
    return round(value / 1_000_000_000.0, 3)


def fmt_gb(value: float) -> str:
    return f"{value:.3f} GB"


def fmt_days(config: Config, value: float) -> str:
    if is_zh(config):
        return f"{value:.3f} 天"
    return f"{value:.3f} days"


def format_dt_local(config: Config, value: datetime) -> str:
    return value.astimezone(config.report_tz).strftime("%m-%d %H:%M")


def format_dt_local_full(config: Config, value: datetime) -> str:
    return value.astimezone(config.report_tz).strftime("%Y-%m-%d %H:%M")


def report_tz_label(config: Config) -> str:
    key = str(getattr(config.report_tz, "key", "") or config.report_tz)
    if key == "Asia/Shanghai":
        return text_by_lang(config, "北京时间", "Asia/Shanghai")
    return key


def add_month_same(dt: datetime) -> datetime:
    year = dt.year
    month = dt.month + 1
    if month == 13:
        year += 1
        month = 1
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


def sub_month_same(dt: datetime) -> datetime:
    year = dt.year
    month = dt.month - 1
    if month == 0:
        year -= 1
        month = 12
    day = min(dt.day, calendar.monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


def next_reset_from_day(day_of_month: int) -> datetime:
    now = datetime.now(timezone.utc)
    year, month = now.year, now.month
    day = min(day_of_month, calendar.monthrange(year, month)[1])
    candidate = datetime(year, month, day, 0, 0, tzinfo=timezone.utc)
    if candidate <= now:
        candidate = add_month_same(candidate)
    return candidate


def vnstat_data(config: Config) -> Dict[str, Any]:
    payload = json.loads(run_text("vnstat", "--json"))
    interfaces = payload.get("interfaces", [])
    if not interfaces:
        raise RuntimeError("vnStat returned no interfaces")
    for iface in interfaces:
        if iface.get("name") == config.network_interface or iface.get("alias") == config.network_interface:
            return iface
    return interfaces[0]


def server_tz():
    return datetime.now().astimezone().tzinfo or timezone.utc


def iter_daily_utc(config: Config) -> Iterable[Tuple[datetime, int, int]]:
    iface = vnstat_data(config)
    for rec in iface.get("traffic", {}).get("day", []):
        d = rec.get("date", {})
        dt_local = datetime(
            int(d["year"]),
            int(d["month"]),
            int(d["day"]),
            0,
            0,
            tzinfo=server_tz(),
        )
        yield dt_local.astimezone(timezone.utc), int(rec.get("rx", 0)), int(rec.get("tx", 0))


def iter_fiveminute_utc(config: Config) -> Iterable[Tuple[datetime, int, int]]:
    iface = vnstat_data(config)
    for rec in iface.get("traffic", {}).get("fiveminute", []):
        d = rec.get("date", {})
        t = rec.get("time", {})
        dt_local = datetime(
            int(d["year"]),
            int(d["month"]),
            int(d["day"]),
            int(t["hour"]),
            int(t["minute"]),
            tzinfo=server_tz(),
        )
        yield dt_local.astimezone(timezone.utc), int(rec.get("rx", 0)), int(rec.get("tx", 0))


def current_window_bounds(config: Config, now_local: datetime | None = None) -> Tuple[datetime, datetime]:
    now_local = now_local or datetime.now(config.report_tz)
    start = now_local.replace(hour=DAILY_START_HOUR, minute=0, second=0, microsecond=0)
    if now_local < start:
        start -= timedelta(days=1)
    return start, now_local


def traffic_between(
    records: Iterable[Tuple[datetime, int, int]],
    start_utc: datetime,
    end_utc: datetime,
) -> Tuple[float, float]:
    rx = tx = 0
    for dt_utc, rx_bytes, tx_bytes in records:
        if start_utc <= dt_utc < end_utc:
            rx += rx_bytes
            tx += tx_bytes
    return bytes_to_gb(rx), bytes_to_gb(tx)


def current_window_usage(config: Config) -> Tuple[datetime, datetime, float, float]:
    start_local, now_local = current_window_bounds(config)
    start_utc = start_local.astimezone(timezone.utc)
    now_utc = datetime.now(timezone.utc)
    rx_gb, tx_gb = traffic_between(iter_fiveminute_utc(config), start_utc, now_utc)
    return start_local, now_local, rx_gb, tx_gb


def yesterday_window_usage(config: Config) -> Tuple[datetime, datetime, float, float]:
    today_start, _ = current_window_bounds(config)
    start = today_start - timedelta(days=1)
    end = today_start
    rx_gb, tx_gb = traffic_between(iter_fiveminute_utc(config), start.astimezone(timezone.utc), end.astimezone(timezone.utc))
    return start, end, rx_gb, tx_gb


def default_quota_state(config: Config) -> Dict[str, Any]:
    next_reset = next_reset_from_day(config.quota_reset_day_utc)
    cycle_start = sub_month_same(next_reset)
    return {
        "cap_gb": config.quota_monthly_cap_gb,
        "next_reset_utc": iso_utc(next_reset),
        "cycle_start_utc": iso_utc(cycle_start),
        "offset_gb": 0.0,
        "calibrated_at_utc": None,
    }


def load_quota_state(config: Config) -> Dict[str, Any]:
    state = load_json(quota_path(config), default_quota_state(config))
    defaults = default_quota_state(config)
    changed = False
    for key, value in defaults.items():
        if key not in state:
            state[key] = value
            changed = True
    state["cap_gb"] = config.quota_monthly_cap_gb

    now_utc = datetime.now(timezone.utc)
    next_reset = parse_utc(state["next_reset_utc"])
    while now_utc >= next_reset:
        cycle_start = next_reset
        next_reset = add_month_same(next_reset)
        state["cycle_start_utc"] = iso_utc(cycle_start)
        state["next_reset_utc"] = iso_utc(next_reset)
        state["offset_gb"] = 0.0
        state["calibrated_at_utc"] = None
        changed = True
    if changed:
        save_json(quota_path(config), state)
    return state


def current_local_cycle_used_gb(config: Config, state: Dict[str, Any]) -> float:
    start_utc = parse_utc(state["cycle_start_utc"])
    now_utc = datetime.now(timezone.utc)
    current_day_start_server = datetime.now(server_tz()).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    rx = tx = 0
    for dt_utc, rx_bytes, tx_bytes in iter_daily_utc(config):
        if start_utc <= dt_utc < current_day_start_server:
            rx += rx_bytes
            tx += tx_bytes
    partial_start = max(start_utc, current_day_start_server)
    for dt_utc, rx_bytes, tx_bytes in iter_fiveminute_utc(config):
        if partial_start <= dt_utc < now_utc:
            rx += rx_bytes
            tx += tx_bytes
    return bytes_to_gb(rx + tx)


def quota_snapshot(config: Config) -> Dict[str, Any]:
    state = load_quota_state(config)
    cap = float(state["cap_gb"])
    local_used = current_local_cycle_used_gb(config, state)
    offset = float(state.get("offset_gb", 0.0))
    estimated_used = max(0.0, local_used + offset)
    if cap > 0:
        estimated_used = min(cap, estimated_used)
    next_reset = parse_utc(state["next_reset_utc"])
    now_utc = datetime.now(timezone.utc)
    days_left = max((next_reset - now_utc).total_seconds() / 86400.0, 0.01)
    remain = max(cap - estimated_used, 0.0) if cap > 0 else math.inf
    avg_day = remain / days_left if cap > 0 else math.inf
    avg_day_half = avg_day / 2.0 if cap > 0 else math.inf
    return {
        "cap_gb": cap,
        "used_gb": estimated_used,
        "remain_gb": remain,
        "days_left": days_left,
        "avg_day_gb": avg_day,
        "avg_day_half_gb": avg_day_half,
        "cycle_start_utc": state["cycle_start_utc"],
        "next_reset_utc": state["next_reset_utc"],
        "offset_gb": offset,
        "local_used_gb": local_used,
        "calibrated_at_utc": state.get("calibrated_at_utc"),
    }


def quota_set(config: Config, used_gb: float, remain_gb: float, next_reset_utc: str | None) -> Dict[str, Any]:
    if used_gb < 0 or remain_gb < 0:
        raise ValueError("used_gb and remain_gb must be non-negative")
    state = load_quota_state(config)
    cap = round(used_gb + remain_gb, 3)
    state["cap_gb"] = cap
    next_reset = parse_utc(next_reset_utc) if next_reset_utc else parse_utc(state["next_reset_utc"])
    if next_reset <= datetime.now(timezone.utc):
        raise ValueError("next_reset_utc must be in the future")
    state["next_reset_utc"] = iso_utc(next_reset)
    state["cycle_start_utc"] = iso_utc(sub_month_same(next_reset))
    local_used = current_local_cycle_used_gb(config, state)
    state["offset_gb"] = round(used_gb - local_used, 3)
    state["calibrated_at_utc"] = iso_utc(datetime.now(timezone.utc))
    save_json(quota_path(config), state)
    return quota_snapshot(config)


def quota_clear(config: Config) -> Dict[str, Any]:
    state = load_quota_state(config)
    state["offset_gb"] = 0.0
    state["calibrated_at_utc"] = None
    save_json(quota_path(config), state)
    return quota_snapshot(config)


def xray_status() -> Tuple[str, str]:
    active = run_status("systemctl", "is-active", "xray") or "unknown"
    version = run_status("xray", "version").splitlines()[:1]
    return active, version[0] if version else "unknown"


def xray_config_validation_error() -> str:
    if not os.path.isfile(XRAY_CONFIG_PATH):
        return f"{XRAY_CONFIG_PATH} is missing"
    try:
        proc = subprocess.run(
            ["xray", "run", "-test", "-c", XRAY_CONFIG_PATH],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except FileNotFoundError:
        return "xray binary is not installed"
    except Exception as exc:
        return str(exc)
    if proc.returncode == 0:
        return ""
    return (proc.stderr or proc.stdout or "xray config validation failed").strip()


def load_xray_config() -> Dict[str, Any]:
    try:
        with open(XRAY_CONFIG_PATH, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def inbound_port(inbound: Dict[str, Any]) -> str:
    return str(inbound.get("port", "")).strip()


def inbound_networks(inbound: Dict[str, Any]) -> set[str]:
    settings = inbound.get("settings", {})
    if not isinstance(settings, dict):
        return set()
    raw = str(settings.get("network", "") or "")
    return {item.strip().lower() for item in raw.split(",") if item.strip()}


def listener_present(protocol: str, port: str) -> bool:
    port_text = str(port or "").strip()
    if not port_text:
        return False
    args = ["ss", "-H", "-ltn", f"( sport = :{port_text} )"] if protocol == "tcp" else ["ss", "-H", "-lun", f"( sport = :{port_text} )"]
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=15, check=False)
    except Exception:
        return False
    return proc.returncode == 0 and bool((proc.stdout or "").strip())


def xray_runtime_state(config: Config) -> Dict[str, Any]:
    expected_vless = is_enabled(config.enable_vless_reality)
    expected_ss2022 = is_enabled(config.enable_ss2022)
    payload = load_xray_config()
    inbounds = payload.get("inbounds", [])
    if not isinstance(inbounds, list):
        inbounds = []

    rendered_vless = False
    rendered_ss2022 = False
    for inbound in inbounds:
        if not isinstance(inbound, dict):
            continue
        protocol = str(inbound.get("protocol", "")).strip().lower()
        port = inbound_port(inbound)
        if (
            protocol == "vless"
            and port == str(config.xray_listen_port).strip()
            and str(((inbound.get("streamSettings") or {}).get("security", ""))).strip().lower() == "reality"
        ):
            rendered_vless = True
        if protocol == "shadowsocks" and port == str(config.ss2022_listen_port).strip():
            if {"tcp", "udp"}.issubset(inbound_networks(inbound)):
                rendered_ss2022 = True

    return {
        "expected_vless": expected_vless,
        "expected_ss2022": expected_ss2022,
        "rendered_vless": rendered_vless,
        "rendered_ss2022": rendered_ss2022,
        "listening_vless_tcp": rendered_vless and listener_present("tcp", config.xray_listen_port),
        "listening_ss2022_tcp": rendered_ss2022 and listener_present("tcp", config.ss2022_listen_port),
        "listening_ss2022_udp": rendered_ss2022 and listener_present("udp", config.ss2022_listen_port),
        "validation_error": xray_config_validation_error() if expected_vless or expected_ss2022 else "",
    }


def hysteria2_status() -> str:
    return run_status("systemctl", "is-active", "neflare-hysteria2") or "inactive"


def time_sync_status() -> Tuple[str, str]:
    enabled = run_status("timedatectl", "show", "-p", "NTP", "--value") or "unknown"
    synchronized = (
        run_status("timedatectl", "show", "-p", "SystemClockSynchronized", "--value")
        or run_status("timedatectl", "show", "-p", "NTPSynchronized", "--value")
        or "unknown"
    )
    return enabled, synchronized


def is_enabled(value: str) -> bool:
    return str(value).strip().lower() == "yes"


def enabled_protocol_names(config: Config, runtime_state: Dict[str, Any]) -> list[str]:
    names: list[str] = []
    if runtime_state.get("expected_vless"):
        if runtime_state.get("rendered_vless") and runtime_state.get("listening_vless_tcp"):
            names.append("VLESS+REALITY")
        else:
            names.append("VLESS+REALITY (configured, not listening)")
    if is_enabled(config.enable_hysteria2):
        names.append("Hysteria 2")
    if runtime_state.get("expected_ss2022"):
        if runtime_state.get("rendered_ss2022") and runtime_state.get("listening_ss2022_tcp") and runtime_state.get("listening_ss2022_udp"):
            names.append("Shadowsocks 2022")
        else:
            names.append("Shadowsocks 2022 (configured, not listening)")
    return names


def listener_summary_lines(config: Config, runtime_state: Dict[str, bool]) -> list[str]:
    unset_text = text_by_lang(config, "未设置", "unset")
    disabled_text = text_by_lang(config, "未启用", "disabled")
    mismatch_text = text_by_lang(config, "env 已启用但 Xray 运行配置缺少 inbound", "enabled in env, but missing from xray runtime config")
    not_listening_prefix = text_by_lang(config, "已写入 Xray 但未监听", "configured in xray, but not listening on")
    lines = [f"- SSH: TCP {config.ssh_port or unset_text}"]
    if runtime_state.get("expected_vless") and runtime_state.get("rendered_vless") and runtime_state.get("listening_vless_tcp"):
        lines.append(f"- VLESS+REALITY: TCP {config.xray_listen_port}")
    elif runtime_state.get("expected_vless") and runtime_state.get("rendered_vless"):
        lines.append(f"- VLESS+REALITY: {not_listening_prefix} TCP {config.xray_listen_port}")
    elif runtime_state.get("expected_vless"):
        lines.append(f"- VLESS+REALITY: {mismatch_text}")
    else:
        lines.append(f"- VLESS+REALITY: {disabled_text}")
    if is_enabled(config.enable_hysteria2):
        lines.append(f"- Hysteria 2: UDP {config.hysteria2_listen_port}")
    else:
        lines.append(f"- Hysteria 2: {disabled_text}")
    if runtime_state.get("expected_ss2022") and runtime_state.get("rendered_ss2022") and runtime_state.get("listening_ss2022_tcp") and runtime_state.get("listening_ss2022_udp"):
        lines.append(f"- SS2022: TCP/UDP {config.ss2022_listen_port}")
    elif runtime_state.get("expected_ss2022") and runtime_state.get("rendered_ss2022"):
        missing = []
        if not runtime_state.get("listening_ss2022_tcp"):
            missing.append("TCP")
        if not runtime_state.get("listening_ss2022_udp"):
            missing.append("UDP")
        missing_ports = "/".join(missing) or "TCP/UDP"
        lines.append(f"- SS2022: {not_listening_prefix} {missing_ports} {config.ss2022_listen_port}")
    elif runtime_state.get("expected_ss2022"):
        lines.append(f"- SS2022: {mismatch_text}")
    else:
        lines.append(f"- SS2022: {disabled_text}")
    return lines


def bbr_status() -> str:
    return run_status("sysctl", "-n", "net.ipv4.tcp_congestion_control") or "unknown"


def health() -> Dict[str, Any]:
    info: Dict[str, Any] = {
        "load": "unknown",
        "mem_total": 0.0,
        "mem_avail": 0.0,
        "disk_used": "unknown",
        "disk_avail": "unknown",
        "disk_pct": "unknown",
        "uptime_h": 0.0,
    }
    try:
        info["load"] = " ".join(open("/proc/loadavg", "r", encoding="utf-8").read().split()[:3])
    except Exception:
        pass
    try:
        meminfo: Dict[str, int] = {}
        with open("/proc/meminfo", "r", encoding="utf-8") as handle:
            for line in handle:
                key, value = line.split(":", 1)
                meminfo[key] = int(value.strip().split()[0])
        info["mem_total"] = meminfo.get("MemTotal", 0) / 1024
        info["mem_avail"] = meminfo.get("MemAvailable", 0) / 1024
    except Exception:
        pass
    try:
        disk = run_text("df", "-h", "/").splitlines()[-1].split()
        info["disk_used"] = disk[2]
        info["disk_avail"] = disk[3]
        info["disk_pct"] = disk[4]
    except Exception:
        pass
    try:
        uptime_sec = float(open("/proc/uptime", "r", encoding="utf-8").read().split()[0])
        info["uptime_h"] = uptime_sec / 3600.0
    except Exception:
        pass
    return info


def countdown_snapshot(config: Config) -> Dict[str, Any]:
    payload = load_countdown(config)
    target_raw = str(payload.get("target_utc", "")).strip()
    message = str(payload.get("message", "")).strip()
    if not target_raw or not message:
        return {"active": False}
    try:
        target_utc = parse_utc(target_raw)
    except Exception:
        return {"active": False}
    now_local = datetime.now(config.report_tz)
    target_local = target_utc.astimezone(config.report_tz)
    remaining_seconds = (target_local - now_local).total_seconds()
    remaining_days = max(remaining_seconds / 86400.0, 0.0)
    due = now_local.date() >= target_local.date()
    return {
        "active": True,
        "message": message,
        "target_utc": target_raw,
        "target_local": target_local,
        "target_text": format_dt_local_full(config, target_local),
        "remaining_days": remaining_days,
        "due": due,
        "created_at_utc": str(payload.get("created_at_utc", "")).strip(),
        "updated_at_utc": str(payload.get("updated_at_utc", "")).strip(),
    }


def countdown_due_banner(config: Config) -> str:
    countdown = countdown_snapshot(config)
    if not countdown.get("active") or not countdown.get("due"):
        return ""
    if is_zh(config):
        return "\n".join(
            [
                "⏰ 倒计时提醒",
                f"• {countdown['message']}",
                f"• 目标时间：{countdown['target_text']}（{report_tz_label(config)}）",
            ]
        )
    return "\n".join(
        [
            "⏰ Countdown Reminder",
            f"• {countdown['message']}",
            f"• Target time: {countdown['target_text']} ({report_tz_label(config)})",
        ]
    )


def countdown_text(config: Config) -> str:
    countdown = countdown_snapshot(config)
    if not countdown.get("active"):
        return text_by_lang(
            config,
            "\n".join(
                [
                    "倒计时",
                    "",
                    "• 当前：未设置",
                    "• 设置方式：/countdown_set 2026-04-01 08:30 你的提醒内容",
                    "• 清除方式：/countdown_clear",
                ]
            ),
            "\n".join(
                [
                    "Countdown",
                    "",
                    "• Current: not configured",
                    "• Set with: /countdown_set 2026-04-01 08:30 your reminder text",
                    "• Clear with: /countdown_clear",
                ]
            ),
        )
    status = text_by_lang(config, "已到达", "reached") if countdown["due"] else text_by_lang(config, "进行中", "active")
    remaining_line = (
        f"• 剩余：{fmt_days(config, countdown['remaining_days'])}"
        if is_zh(config)
        else f"• Remaining: {fmt_days(config, countdown['remaining_days'])}"
    )
    if countdown["due"]:
        remaining_line = f"• 状态：{status}" if is_zh(config) else f"• Status: {status}"
    return text_by_lang(
        config,
        "\n".join(
            [
                "倒计时",
                "",
                f"• 内容：{countdown['message']}",
                f"• 目标时间：{countdown['target_text']}（{report_tz_label(config)}）",
                remaining_line,
                "• 设置方式：/countdown_set 2026-04-01 08:30 你的提醒内容",
                "• 清除方式：/countdown_clear",
            ]
        ),
        "\n".join(
            [
                "Countdown",
                "",
                f"• Message: {countdown['message']}",
                f"• Target time: {countdown['target_text']} ({report_tz_label(config)})",
                remaining_line,
                "• Set with: /countdown_set 2026-04-01 08:30 your reminder text",
                "• Clear with: /countdown_clear",
            ]
        ),
    )


def health_text(config: Config) -> str:
    info = health()
    return text_by_lang(
        config,
        "\n".join(
            [
                "系统状态",
                "",
                f"• Load：{info['load']}",
                f"• 内存：{info['mem_avail']:.0f} / {info['mem_total']:.0f} MB 可用",
                f"• 磁盘：{info['disk_used']} / {info['disk_avail']}（{info['disk_pct']}）",
                f"• 运行：{info['uptime_h']:.3f} 小时",
            ]
        ),
        "\n".join(
            [
                "System Health",
                "",
                f"• Load: {info['load']}",
                f"• Memory: {info['mem_avail']:.0f} / {info['mem_total']:.0f} MB available",
                f"• Disk: {info['disk_used']} / {info['disk_avail']} ({info['disk_pct']})",
                f"• Uptime: {info['uptime_h']:.3f} hours",
            ]
        ),
    )


def status_text(config: Config) -> str:
    today_start, today_now, today_rx, today_tx = current_window_usage(config)
    y_start, y_end, y_rx, y_tx = yesterday_window_usage(config)
    quota = quota_snapshot(config)
    countdown = countdown_snapshot(config)
    xray_active, xray_version = xray_status()
    runtime_state = xray_runtime_state(config)
    hy2_active = hysteria2_status()
    clock_enabled, clock_synchronized = time_sync_status()
    sys = health()
    next_reset_local = format_dt_local(config, parse_utc(quota["next_reset_utc"]))
    validation_error = str(runtime_state.get("validation_error", "") or "").strip()
    runtime_mismatch = (
        (runtime_state.get("expected_vless") and not runtime_state.get("rendered_vless"))
        or (runtime_state.get("expected_ss2022") and not runtime_state.get("rendered_ss2022"))
    )
    if validation_error:
        raise RuntimeError(
            text_by_lang(
                config,
                f"Xray 运行配置校验失败：{validation_error}",
                f"Xray runtime config validation failed: {validation_error}",
            )
        )
    if runtime_mismatch:
        raise RuntimeError(
            text_by_lang(
                config,
                f"Xray 运行配置与 {config.neflare_config_file} 不一致，请重新运行 bash ./install.sh --config {config.neflare_config_file} --non-interactive",
                f"Xray runtime config is out of sync with {config.neflare_config_file}; rerun bash ./install.sh --config {config.neflare_config_file} --non-interactive",
            )
        )
    enabled_protocols = ", ".join(enabled_protocol_names(config, runtime_state)) or text_by_lang(config, "无", "none")
    listener_lines = listener_summary_lines(config, runtime_state)
    xray_overview = (
        f"{xray_active}｜{xray_version}"
        if is_enabled(config.enable_vless_reality) or is_enabled(config.enable_ss2022)
        else "未启用"
    )
    xray_overview_en = (
        f"{xray_active} | {xray_version}"
        if is_enabled(config.enable_vless_reality) or is_enabled(config.enable_ss2022)
        else "disabled"
    )
    reality_line = (
        f"{config.xray_listen_port} → {config.reality_selected_domain or '未设置'}"
        if is_enabled(config.enable_vless_reality)
        else "未启用"
    )
    reality_line_en = (
        f"{config.xray_listen_port} -> {config.reality_selected_domain or 'unset'}"
        if is_enabled(config.enable_vless_reality)
        else "disabled"
    )
    xray_service_line = (
        f"- xray: {xray_active}"
        if is_enabled(config.enable_vless_reality) or is_enabled(config.enable_ss2022)
        else text_by_lang(config, "- xray: 未启用", "- xray: disabled")
    )
    xray_runtime_line = (
        text_by_lang(config, "- xray 运行配置: 已对齐", "- xray runtime config: aligned")
        if not runtime_mismatch
        else text_by_lang(config, "- xray 运行配置: 与 env 不一致", "- xray runtime config: mismatched with env")
    )
    hy2_service_line = (
        f"- hysteria2: {hy2_active}"
        if is_enabled(config.enable_hysteria2)
        else text_by_lang(config, "- hysteria2: 未启用", "- hysteria2: disabled")
    )
    clock_line = text_by_lang(
        config,
        f"- 时间同步: NTP={clock_enabled}，已同步={clock_synchronized}",
        f"- time sync: enabled={clock_enabled}, synchronized={clock_synchronized}",
    )
    lines = []
    lines.append(text_by_lang(config, "📊 状态总览", "📊 Status"))
    lines.append("")
    lines.extend(
        [
            text_by_lang(config, f"启用的协议：{enabled_protocols}", f"Enabled protocols: {enabled_protocols}"),
            text_by_lang(config, "监听摘要：", "Listener summary:"),
            *listener_lines,
            text_by_lang(config, "服务状态：", "Service status:"),
            xray_service_line,
            xray_runtime_line if is_enabled(config.enable_vless_reality) or is_enabled(config.enable_ss2022) else "",
            hy2_service_line,
            clock_line if is_enabled(config.enable_time_sync) else text_by_lang(config, "- 时间同步: 未启用", "- time sync: disabled"),
            "",
        ]
    )
    if countdown.get("active"):
        if is_zh(config):
            status_label = "已到达" if countdown["due"] else f"剩余 {fmt_days(config, countdown['remaining_days'])}"
            lines.extend(
                [
                    "倒计时",
                    f"• {countdown['message']}",
                    f"• 目标时间：{countdown['target_text']}（{report_tz_label(config)}）",
                    f"• 状态：{status_label}",
                    "",
                ]
            )
        else:
            status_label = "reached" if countdown["due"] else fmt_days(config, countdown["remaining_days"])
            lines.extend(
                [
                    "Countdown",
                    f"• {countdown['message']}",
                    f"• Target time: {countdown['target_text']} ({report_tz_label(config)})",
                    f"• Status: {status_label}",
                    "",
                ]
            )
    if is_zh(config):
        lines.extend(
            [
                "概览",
                f"• Xray：{xray_overview}",
                f"• REALITY：{reality_line}",
                f"• 月配额剩余：{fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else '不限'}",
                f"• 日均总量建议：{fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else '不限'}",
                f"• 日均单向建议：{fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else '不限'}",
                "",
                "本日统计窗口",
                f"• {report_tz_label(config)}：{format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)}",
                f"• 入站：{fmt_gb(today_rx)}",
                f"• 出站：{fmt_gb(today_tx)}",
                f"• 合计：{fmt_gb(today_rx + today_tx)}",
                "",
                "昨日统计窗口",
                f"• {report_tz_label(config)}：{format_dt_local(config, y_start)} -> {format_dt_local(config, y_end)}",
                f"• 入站：{fmt_gb(y_rx)}",
                f"• 出站：{fmt_gb(y_tx)}",
                f"• 合计：{fmt_gb(y_rx + y_tx)}",
                "",
                "月度配额",
                f"• 已用：{quota['used_gb']:.3f} / {quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else f"• 已用：{quota['used_gb']:.3f} GB（不限）",
                f"• 剩余：{fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else '不限'}",
                f"• 剩余天数：{fmt_days(config, quota['days_left'])}",
                f"• 下次重置：{next_reset_local}（{report_tz_label(config)}）",
                "",
                "系统",
                f"• Load：{sys['load']}",
                f"• 内存：{sys['mem_avail']:.0f} / {sys['mem_total']:.0f} MB 可用",
                f"• 磁盘：{sys['disk_used']} / {sys['disk_avail']}（{sys['disk_pct']}）",
                f"• 运行：{sys['uptime_h']:.3f} 小时",
            ]
        )
        return "\n".join(lines)
    lines.extend(
        [
            "Overview",
            f"• Xray: {xray_overview_en}",
            f"• REALITY: {reality_line_en}",
            f"• Quota remaining: {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else 'unlimited'}",
            f"• Suggested daily total: {fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else 'unlimited'}",
            f"• Suggested one-way daily: {fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else 'unlimited'}",
            "",
            "Today",
            f"• {report_tz_label(config)}: {format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)}",
            f"• RX: {fmt_gb(today_rx)}",
            f"• TX: {fmt_gb(today_tx)}",
            f"• Total: {fmt_gb(today_rx + today_tx)}",
            "",
            "Yesterday",
            f"• {report_tz_label(config)}: {format_dt_local(config, y_start)} -> {format_dt_local(config, y_end)}",
            f"• RX: {fmt_gb(y_rx)}",
            f"• TX: {fmt_gb(y_tx)}",
            f"• Total: {fmt_gb(y_rx + y_tx)}",
            "",
            "Quota",
            f"• Used: {quota['used_gb']:.3f} / {quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else f"• Used: {quota['used_gb']:.3f} GB (unlimited)",
            f"• Remaining: {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else 'unlimited'}",
            f"• Days left: {fmt_days(config, quota['days_left'])}",
            f"• Next reset: {next_reset_local} ({report_tz_label(config)})",
            "",
            "System",
            f"• Load: {sys['load']}",
            f"• Memory: {sys['mem_avail']:.0f} / {sys['mem_total']:.0f} MB available",
            f"• Disk: {sys['disk_used']} / {sys['disk_avail']} ({sys['disk_pct']})",
            f"• Uptime: {sys['uptime_h']:.3f} hours",
        ]
    )
    return "\n".join(lines)


def daily_text(config: Config) -> str:
    today_start, today_now, today_rx, today_tx = current_window_usage(config)
    y_start, y_end, y_rx, y_tx = yesterday_window_usage(config)
    quota = quota_snapshot(config)
    banner = countdown_due_banner(config)
    lines = []
    if banner:
        lines.extend([banner, ""])
    if is_zh(config):
        lines.extend(
            [
                "📅 每日视图",
                "",
                "概览",
                f"• 配额状态：剩余 {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else '不限'}",
                f"• 日均总量建议：{fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else '不限'}",
                f"• 日均单向建议：{fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else '不限'}",
                "",
                "本日统计窗口",
                f"• {report_tz_label(config)}：{format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)}",
                f"• 入站：{fmt_gb(today_rx)}",
                f"• 出站：{fmt_gb(today_tx)}",
                f"• 合计：{fmt_gb(today_rx + today_tx)}",
                "",
                "昨日统计窗口",
                f"• {report_tz_label(config)}：{format_dt_local(config, y_start)} -> {format_dt_local(config, y_end)}",
                f"• 入站：{fmt_gb(y_rx)}",
                f"• 出站：{fmt_gb(y_tx)}",
                f"• 合计：{fmt_gb(y_rx + y_tx)}",
                "",
                "月度配额",
                f"• 已用：{quota['used_gb']:.3f} / {quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else f"• 已用：{quota['used_gb']:.3f} GB（不限）",
                f"• 剩余：{fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else '不限'}",
                f"• 剩余天数：{fmt_days(config, quota['days_left'])}",
            ]
        )
        return "\n".join(lines)
    lines.extend(
        [
            "📅 Daily View",
            "",
            "Overview",
            f"• Quota remaining: {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else 'unlimited'}",
            f"• Suggested daily total: {fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else 'unlimited'}",
            f"• Suggested one-way daily: {fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else 'unlimited'}",
            "",
            "Today",
            f"• {report_tz_label(config)}: {format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)}",
            f"• RX: {fmt_gb(today_rx)}",
            f"• TX: {fmt_gb(today_tx)}",
            f"• Total: {fmt_gb(today_rx + today_tx)}",
            "",
            "Yesterday",
            f"• {report_tz_label(config)}: {format_dt_local(config, y_start)} -> {format_dt_local(config, y_end)}",
            f"• RX: {fmt_gb(y_rx)}",
            f"• TX: {fmt_gb(y_tx)}",
            f"• Total: {fmt_gb(y_rx + y_tx)}",
            "",
            "Quota",
            f"• Used: {quota['used_gb']:.3f} / {quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else f"• Used: {quota['used_gb']:.3f} GB (unlimited)",
            f"• Remaining: {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else 'unlimited'}",
            f"• Days left: {fmt_days(config, quota['days_left'])}",
        ]
    )
    return "\n".join(lines)


def quota_text(config: Config) -> str:
    quota = quota_snapshot(config)
    today_start, today_now, today_rx, today_tx = current_window_usage(config)
    cycle_start_local = format_dt_local(config, parse_utc(quota["cycle_start_utc"]))
    next_reset_local = format_dt_local(config, parse_utc(quota["next_reset_utc"]))
    calibrated = text_by_lang(config, "无", "none")
    if quota.get("calibrated_at_utc"):
        calibrated = format_dt_local(config, parse_utc(quota["calibrated_at_utc"]))
    if is_zh(config):
        return "\n".join(
            [
                "📦 配额详情",
                "",
                f"• 今日窗口：{format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)}（{report_tz_label(config)}）",
                f"• 今日入站：{fmt_gb(today_rx)}",
                f"• 今日出站：{fmt_gb(today_tx)}",
                f"• 今日合计：{fmt_gb(today_rx + today_tx)}",
                "",
                f"• 周期开始：{cycle_start_local}（{report_tz_label(config)}）",
                f"• 下次重置：{next_reset_local}（{report_tz_label(config)}）",
                f"• 总额：{quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else "• 总额：不限",
                f"• 已用：{quota['used_gb']:.3f} GB",
                f"• 剩余：{fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else '不限'}",
                f"• 建议总量：{fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else '不限'}",
                f"• 建议单向：{fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else '不限'}",
                f"• 剩余天数：{fmt_days(config, quota['days_left'])}",
                f"• 本地原始累计：{quota['local_used_gb']:.3f} GB",
                f"• 校准偏移：{quota['offset_gb']:+.3f} GB",
                f"• 上次校准：{calibrated}（{report_tz_label(config)}）" if calibrated != "无" else "• 上次校准：无",
            ]
        )
    return "\n".join(
        [
            "📦 Quota Details",
            "",
            f"• Today window: {format_dt_local(config, today_start)} -> {format_dt_local(config, today_now)} ({report_tz_label(config)})",
            f"• Today RX: {fmt_gb(today_rx)}",
            f"• Today TX: {fmt_gb(today_tx)}",
            f"• Today total: {fmt_gb(today_rx + today_tx)}",
            "",
            f"• Cycle start: {cycle_start_local} ({report_tz_label(config)})",
            f"• Next reset: {next_reset_local} ({report_tz_label(config)})",
            f"• Cap: {quota['cap_gb']:.3f} GB" if quota["cap_gb"] > 0 else "• Cap: unlimited",
            f"• Used: {quota['used_gb']:.3f} GB",
            f"• Remaining: {fmt_gb(quota['remain_gb']) if not math.isinf(quota['remain_gb']) else 'unlimited'}",
            f"• Suggested daily total: {fmt_gb(quota['avg_day_gb']) if not math.isinf(quota['avg_day_gb']) else 'unlimited'}",
            f"• Suggested one-way daily: {fmt_gb(quota['avg_day_half_gb']) if not math.isinf(quota['avg_day_half_gb']) else 'unlimited'}",
            f"• Days left: {fmt_days(config, quota['days_left'])}",
            f"• Local raw usage: {quota['local_used_gb']:.3f} GB",
            f"• Calibration offset: {quota['offset_gb']:+.3f} GB",
            f"• Last calibration: {calibrated} ({report_tz_label(config)})" if calibrated != "none" else "• Last calibration: none",
        ]
    )
