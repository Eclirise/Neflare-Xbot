#!/usr/bin/env python3

from __future__ import annotations

import calendar
import json
import math
import subprocess
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Iterable, Tuple

from config import Config
from i18n import tr
from state import load_json, quota_path, save_json


def run_text(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()


def run_status(*args: str) -> str:
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    return proc.stdout.strip()


def iso_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def bytes_to_gb(value: float) -> float:
    return round(value / (1024.0 ** 3), 3)


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
        if iface.get("name") == config.network_interface:
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


def current_window_bounds(config: Config) -> Tuple[datetime, datetime]:
    now = datetime.now(config.report_tz)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return start, now


def traffic_between(records: Iterable[Tuple[datetime, int, int]], start_utc: datetime, end_utc: datetime) -> Tuple[float, float]:
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
    estimated_used = max(0.0, min(cap, local_used + float(state.get("offset_gb", 0.0)))) if cap > 0 else local_used
    next_reset = parse_utc(state["next_reset_utc"])
    now_utc = datetime.now(timezone.utc)
    days_left = max((next_reset - now_utc).total_seconds() / 86400.0, 0.01)
    remain = max(cap - estimated_used, 0.0) if cap > 0 else math.inf
    avg_day = remain / days_left if cap > 0 else math.inf
    return {
        "cap_gb": cap,
        "used_gb": estimated_used,
        "remain_gb": remain,
        "days_left": days_left,
        "avg_day_gb": avg_day,
        "cycle_start_utc": state["cycle_start_utc"],
        "next_reset_utc": state["next_reset_utc"],
        "offset_gb": float(state.get("offset_gb", 0.0)),
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
    state["offset_gb"] = used_gb - local_used
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


def bbr_status() -> str:
    return run_status("sysctl", "-n", "net.ipv4.tcp_congestion_control") or "unknown"


def status_text(config: Config) -> str:
    today_start, today_now, today_rx, today_tx = current_window_usage(config)
    quota = quota_snapshot(config)
    xray_active, xray_version = xray_status()
    remain = tr(config, "unlimited") if math.isinf(quota["remain_gb"]) else f"{quota['remain_gb']:.3f} GB"
    cap = tr(config, "cap_disabled") if quota["cap_gb"] <= 0 else f"{quota['cap_gb']:.3f} GB"
    return "\n".join(
        [
            tr(config, "status_header"),
            tr(config, "status_xray", active=xray_active, version=xray_version),
            tr(config, "status_ssh", port=config.ssh_port, admin=config.admin_user),
            tr(config, "status_reality_port", port=config.xray_listen_port),
            tr(config, "status_reality_target", target=config.reality_selected_domain or tr(config, "reality_target_unset")),
            tr(config, "status_ipv6", value=tr(config, "yes") if str(config.enable_ipv6).strip().lower() == "yes" else tr(config, "no")),
            tr(config, "status_bbr", value=bbr_status()),
            tr(
                config,
                "status_today",
                start=f"{today_start:%Y-%m-%d %H:%M}",
                end=f"{today_now:%Y-%m-%d %H:%M}",
                rx=today_rx,
                tx=today_tx,
                total=(today_rx + today_tx),
            ),
            tr(config, "status_quota_cap", value=cap),
            tr(config, "status_quota_used", value=quota["used_gb"]),
            tr(config, "status_quota_remaining", value=remain),
            tr(config, "status_next_reset", value=quota["next_reset_utc"]),
        ]
    )


def daily_text(config: Config) -> str:
    today_start, today_now, today_rx, today_tx = current_window_usage(config)
    y_start, y_end, y_rx, y_tx = yesterday_window_usage(config)
    quota = quota_snapshot(config)
    remain = tr(config, "unlimited") if math.isinf(quota["remain_gb"]) else f"{quota['remain_gb']:.3f} GB"
    return "\n".join(
        [
            tr(config, "daily_header"),
            tr(
                config,
                "daily_today",
                start=f"{today_start:%Y-%m-%d %H:%M}",
                end=f"{today_now:%Y-%m-%d %H:%M}",
                rx=today_rx,
                tx=today_tx,
                total=(today_rx + today_tx),
            ),
            tr(
                config,
                "daily_yesterday",
                start=f"{y_start:%Y-%m-%d %H:%M}",
                end=f"{y_end:%Y-%m-%d %H:%M}",
                rx=y_rx,
                tx=y_tx,
                total=(y_rx + y_tx),
            ),
            tr(config, "daily_quota_remaining", value=remain),
            tr(config, "daily_next_reset", value=quota["next_reset_utc"]),
        ]
    )


def quota_text(config: Config) -> str:
    quota = quota_snapshot(config)
    if quota["cap_gb"] <= 0:
        cap_line = tr(config, "quota_cap_disabled")
        remain_line = tr(config, "quota_remaining", value=tr(config, "unlimited"))
    else:
        cap_line = tr(config, "quota_cap", value=quota["cap_gb"])
        remain_line = tr(config, "quota_remaining", value=f"{quota['remain_gb']:.3f} GB")
    return "\n".join(
        [
            tr(config, "quota_header"),
            cap_line,
            tr(config, "quota_local_used", value=quota["local_used_gb"]),
            tr(config, "quota_estimated_used", value=quota["used_gb"]),
            remain_line,
            tr(config, "quota_offset", value=quota["offset_gb"]),
            tr(config, "quota_cycle_start", value=quota["cycle_start_utc"]),
            tr(config, "quota_next_reset", value=quota["next_reset_utc"]),
        ]
    )
