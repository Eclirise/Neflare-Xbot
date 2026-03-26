#!/usr/bin/env python3
import os
import re
import sys
import json
import time
import ipaddress
import calendar
import subprocess
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from urllib.parse import urlencode, quote
from urllib.request import Request, urlopen

APP_DIR = "/var/lib/neflare-bot"
OFFSET_FILE = os.path.join(APP_DIR, "offset")
QUOTA_FILE = os.path.join(APP_DIR, "quota.json")
SETTINGS_FILE = os.path.join(APP_DIR, "settings.json")
IPMETA_FILE = os.path.join(APP_DIR, "ipmeta-cache.json")
DAILY_SENT_FILE = os.path.join(APP_DIR, "last-daily-sent.txt")
ALERT_STATE_FILE = os.path.join(APP_DIR, "last-alert-sent.txt")
ALERT_HISTORY_FILE = os.path.join(APP_DIR, "alert-history.jsonl")
CHAT_CANDIDATES_FILE = os.path.join(APP_DIR, "chat-candidates.json")

IPMETA_TTL = 7 * 86400
VNSTAT_CACHE_TTL = 5.0
_VNSTAT_CACHE = {"ts": 0.0, "data": None}

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def load_env_file(path):
    data = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip().strip('"').strip("'")
    return data

def load_cfg():
    cfg = dict(os.environ)

    env_candidates = [
        os.environ.get("NEFLARE_BOT_ENV", "").strip(),
        "/etc/default/neflare-bot",
        os.path.join(SCRIPT_DIR, ".env"),
    ]

    for path in env_candidates:
        if path and os.path.isfile(path):
            cfg.update(load_env_file(path))
            cfg["_ENV_FILE"] = path
            break

    return cfg

CFG = load_cfg()

BOT_TOKEN = str(CFG.get("BOT_TOKEN", "")).strip()
CHAT_ID = str(CFG.get("CHAT_ID", "")).strip()
IFACE = str(CFG.get("IFACE", "")).strip()
SERVER_TZ = ZoneInfo(str(CFG.get("SERVER_TZ", "UTC")).strip() or "UTC")
REPORT_TZ = ZoneInfo(str(CFG.get("REPORT_TZ", "Asia/Shanghai")).strip() or "Asia/Shanghai")
MONTHLY_CAP_GB = float(CFG.get("MONTHLY_CAP_GB", "1000"))
RESET_DAY_UTC = int(CFG.get("RESET_DAY_UTC", "24"))
ALERT_COOLDOWN = int(CFG.get("ALERT_COOLDOWN", "300"))
SELF_PUBLIC_IP = str(CFG.get("SELF_PUBLIC_IP", "")).strip()

DEFAULT_ENABLE_IPMETA = str(CFG.get("ENABLE_IPMETA", "0")).strip() == "1"
DEFAULT_IPMETA_MAX_LOOKUPS = int(CFG.get("IPMETA_MAX_LOOKUPS", "3"))
DEFAULT_IPMETA_MODE = str(CFG.get("IPMETA_MODE", "manual")).strip().lower()
DEFAULT_DAILY_NOTIFY_TIME = str(CFG.get("DAILY_NOTIFY_TIME", "07:51")).strip()
SERVICE_NAME = str(CFG.get("SERVICE_NAME", "neflare-bot")).strip() or "neflare-bot"

if not BOT_TOKEN:
    raise SystemExit("BOT_TOKEN missing. Put it in /etc/default/neflare-bot or /opt/neflare-bot/.env")

if not IFACE:
    raise SystemExit("IFACE missing. Put it in /etc/default/neflare-bot or /opt/neflare-bot/.env")

if DEFAULT_IPMETA_MODE not in ("manual", "always"):
    DEFAULT_IPMETA_MODE = "manual"

DAILY_START_HOUR = 5

def ensure_dir():
    os.makedirs(APP_DIR, exist_ok=True)

def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, obj):
    ensure_dir()
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp, path)

def load_chat_candidates():
    data = load_json(CHAT_CANDIDATES_FILE, [])
    return data if isinstance(data, list) else []

def save_chat_candidates(rows):
    save_json(CHAT_CANDIDATES_FILE, rows)

def register_chat_candidate(msg):
    chat = msg.get("chat") or {}
    if not chat:
        return

    rec = {
        "chat_id": str(chat.get("id", "")).strip(),
        "type": str(chat.get("type", "")).strip(),
        "title": str(chat.get("title", "")).strip(),
        "username": str(chat.get("username", "")).strip(),
        "first_name": str(chat.get("first_name", "")).strip(),
        "last_name": str(chat.get("last_name", "")).strip(),
        "last_seen_text": datetime.now(REPORT_TZ).strftime("%Y-%m-%d %H:%M:%S"),
        "last_seen_utc": iso_utc(datetime.now(timezone.utc)),
    }
    if not rec["chat_id"]:
        return

    rows = load_chat_candidates()
    kept = [x for x in rows if str(x.get("chat_id", "")).strip() != rec["chat_id"]]
    kept.append(rec)
    kept.sort(key=lambda x: x.get("last_seen_utc", ""), reverse=True)
    save_chat_candidates(kept[:50])

def format_chat_candidate(row):
    parts = [f"chat_id={row.get('chat_id', '')}", f"type={row.get('type', '') or 'unknown'}"]
    title = row.get("title", "")
    if title:
        parts.append(f"title={title}")
    name = " ".join([x for x in [row.get("first_name", ""), row.get("last_name", "")] if x]).strip()
    if name:
        parts.append(f"name={name}")
    username = row.get("username", "")
    if username:
        parts.append(f"username=@{username}")
    seen = row.get("last_seen_text", "")
    if seen:
        parts.append(f"last_seen={seen}")
    return " | ".join(parts)

def list_chat_candidates_text():
    rows = load_chat_candidates()
    if not rows:
        return "No chat candidates recorded yet."
    return "\n".join(format_chat_candidate(x) for x in rows)

def update_env_value(path, key, value):
    value = str(value)
    lines = []
    found = False
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    new_lines = []
    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f"{key}={value}")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{key}={value}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(new_lines).rstrip() + "\n")

def bind_chat_id(chat_id):
    env_file = CFG.get("_ENV_FILE") or "/etc/default/neflare-bot"
    ensure_dir()
    update_env_value(env_file, "CHAT_ID", str(chat_id).strip())
    return env_file

def chat_is_authorized(chat_id):
    if not CHAT_ID:
        return False
    return str(chat_id).strip() == CHAT_ID

def api(method, params=None, timeout=70):
    data = urlencode(params or {}).encode()
    req = Request(f"https://api.telegram.org/bot{BOT_TOKEN}/{method}", data=data)
    with urlopen(req, timeout=timeout) as r:
        obj = json.load(r)
    if not obj.get("ok"):
        raise RuntimeError(obj)
    return obj["result"]

def send(text, chat_id=None):
    target_chat_id = str(chat_id or CHAT_ID).strip()
    if not target_chat_id:
        raise RuntimeError("CHAT_ID is not configured")
    return api("sendMessage", {
        "chat_id": target_chat_id,
        "text": text,
        "disable_web_page_preview": "true",
    })

def sh(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()

def iso_utc(dt):
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def parse_utc(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)

def valid_hhmm(s):
    return bool(re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', s or ''))

def fmt_gb(v):
    return f"{v:.3f} GB"

def fmt_days(v):
    return f"{v:.3f} 天"

def add_month_same(dt):
    y = dt.year
    m = dt.month + 1
    if m == 13:
        y += 1
        m = 1
    d = min(dt.day, calendar.monthrange(y, m)[1])
    return dt.replace(year=y, month=m, day=d)

def sub_month_same(dt):
    y = dt.year
    m = dt.month - 1
    if m == 0:
        y -= 1
        m = 12
    d = min(dt.day, calendar.monthrange(y, m)[1])
    return dt.replace(year=y, month=m, day=d)

def next_reset_from_day(dom):
    now = datetime.now(timezone.utc)
    y, m = now.year, now.month
    d = min(dom, calendar.monthrange(y, m)[1])
    cand = datetime(y, m, d, 0, 0, tzinfo=timezone.utc)
    if cand <= now:
        cand = add_month_same(cand)
    return cand

def get_vnstat_data(force=False):
    now = time.time()
    if (not force and _VNSTAT_CACHE["data"] is not None
            and now - _VNSTAT_CACHE["ts"] < VNSTAT_CACHE_TTL):
        return _VNSTAT_CACHE["data"]
    data = json.loads(sh("vnstat", "--json"))
    _VNSTAT_CACHE["data"] = data
    _VNSTAT_CACHE["ts"] = now
    return data

def vnstat_interface_data():
    data = get_vnstat_data()
    for iface in data.get("interfaces", []):
        if iface.get("name") == IFACE or iface.get("alias") == IFACE:
            return iface
    raise RuntimeError(f"interface {IFACE} not found in vnstat")

def iter_hourly_utc():
    iface = vnstat_interface_data()
    out = []
    for rec in iface.get("traffic", {}).get("hour", []):
        d = rec["date"]
        t = rec["time"]
        local_dt = datetime(
            d["year"], d["month"], d["day"],
            t["hour"], t.get("minute", 0), tzinfo=SERVER_TZ
        )
        out.append((local_dt.astimezone(timezone.utc), int(rec.get("rx", 0)), int(rec.get("tx", 0))))
    return out

def iter_fiveminute_utc():
    iface = vnstat_interface_data()
    out = []
    for rec in iface.get("traffic", {}).get("fiveminute", []):
        d = rec["date"]
        t = rec["time"]
        local_dt = datetime(
            d["year"], d["month"], d["day"],
            t["hour"], t.get("minute", 0), tzinfo=SERVER_TZ
        )
        out.append((local_dt.astimezone(timezone.utc), int(rec.get("rx", 0)), int(rec.get("tx", 0))))
    return out

def iter_daily_utc():
    iface = vnstat_interface_data()
    out = []
    for rec in iface.get("traffic", {}).get("day", []):
        d = rec["date"]
        local_dt = datetime(d["year"], d["month"], d["day"], 0, 0, tzinfo=SERVER_TZ)
        out.append((local_dt.astimezone(timezone.utc), int(rec.get("rx", 0)), int(rec.get("tx", 0))))
    return out

def bytes_to_gb(n):
    return n / 1_000_000_000.0

def traffic_between_gb(start_utc, end_utc):
    rx = tx = 0
    for dt_utc, r, t in iter_hourly_utc():
        if start_utc <= dt_utc < end_utc:
            rx += r
            tx += t
    return bytes_to_gb(rx), bytes_to_gb(tx)

def traffic_between_fiveminute_gb(start_utc, end_utc):
    rx = tx = 0
    for dt_utc, r, t in iter_fiveminute_utc():
        if start_utc <= dt_utc < end_utc:
            rx += r
            tx += t
    return bytes_to_gb(rx), bytes_to_gb(tx)

def cn_window_bounds(now_cn=None):
    now_cn = now_cn or datetime.now(REPORT_TZ)
    start_cn = now_cn.replace(hour=DAILY_START_HOUR, minute=0, second=0, microsecond=0)
    if now_cn < start_cn:
        start_cn -= timedelta(days=1)
    return start_cn, now_cn

def current_cn_window():
    start_cn, now_cn = cn_window_bounds()
    start_utc = start_cn.astimezone(timezone.utc)
    now_utc = datetime.now(timezone.utc)
    rx_gb, tx_gb = traffic_between_fiveminute_gb(start_utc, now_utc)
    return start_cn, now_cn, rx_gb, tx_gb

def yesterday_cn_window():
    today_start_cn, _ = cn_window_bounds()
    start_cn = today_start_cn - timedelta(days=1)
    end_cn = today_start_cn
    start_utc = start_cn.astimezone(timezone.utc)
    end_utc = end_cn.astimezone(timezone.utc)
    rx_gb, tx_gb = traffic_between_fiveminute_gb(start_utc, end_utc)
    return start_cn, end_cn, rx_gb, tx_gb


def default_quota_state():
    next_reset = next_reset_from_day(RESET_DAY_UTC)
    cycle_start = sub_month_same(next_reset)
    return {
        "cap_gb": MONTHLY_CAP_GB,
        "next_reset_utc": iso_utc(next_reset),
        "cycle_start_utc": iso_utc(cycle_start),
        "offset_gb": 0.0,
        "panel_anchor_used_gb": 0.0,
        "panel_anchor_remain_gb": MONTHLY_CAP_GB,
        "local_anchor_used_gb": 0.0,
        "calibrated_at_utc": None,
    }

def load_quota_state():
    state = load_json(QUOTA_FILE, default_quota_state())
    changed = False
    for k, v in default_quota_state().items():
        if k not in state:
            state[k] = v
            changed = True

    now = datetime.now(timezone.utc)
    next_reset = parse_utc(state["next_reset_utc"])
    rolled = False

    while now >= next_reset:
        cycle_start = next_reset
        next_reset = add_month_same(next_reset)
        state["cycle_start_utc"] = iso_utc(cycle_start)
        state["next_reset_utc"] = iso_utc(next_reset)
        state["offset_gb"] = 0.0
        state["panel_anchor_used_gb"] = 0.0
        state["panel_anchor_remain_gb"] = state.get("cap_gb", MONTHLY_CAP_GB)
        state["local_anchor_used_gb"] = 0.0
        state["calibrated_at_utc"] = None
        rolled = True

    if changed or rolled:
        save_json(QUOTA_FILE, state)
    return state

def current_local_cycle_used_gb(state):
    start_utc = parse_utc(state["cycle_start_utc"])
    now_utc = datetime.now(timezone.utc)

    current_day_start_server = (
        now_utc.astimezone(SERVER_TZ)
        .replace(hour=0, minute=0, second=0, microsecond=0)
        .astimezone(timezone.utc)
    )

    rx = tx = 0

    # 历史完整日：用 day 桶
    for dt_utc, r, t in iter_daily_utc():
        if start_utc <= dt_utc < current_day_start_server:
            rx += r
            tx += t

    # 今天未结束部分：用 5 分钟桶
    partial_start = max(start_utc, current_day_start_server)
    for dt_utc, r, t in iter_fiveminute_utc():
        if partial_start <= dt_utc < now_utc:
            rx += r
            tx += t

    return bytes_to_gb(rx + tx)


def quota_snapshot():
    state = load_quota_state()
    now_utc = datetime.now(timezone.utc)
    local_used = current_local_cycle_used_gb(state)
    cap = float(state["cap_gb"])
    est_used = max(0.0, min(cap, local_used + float(state.get("offset_gb", 0.0))))
    remain = max(cap - est_used, 0.0)
    next_reset = parse_utc(state["next_reset_utc"])
    days_left = max((next_reset - now_utc).total_seconds() / 86400.0, 0.01)
    avg_day = remain / days_left
    avg_day_half = avg_day / 2.0
    return {
        "cap_gb": cap,
        "local_used_gb": local_used,
        "offset_gb": float(state.get("offset_gb", 0.0)),
        "used_gb": est_used,
        "remain_gb": remain,
        "days_left": days_left,
        "avg_day_gb": avg_day,
        "avg_day_half_gb": avg_day_half,
        "cycle_start_utc": state["cycle_start_utc"],
        "next_reset_utc": state["next_reset_utc"],
        "calibrated_at_utc": state.get("calibrated_at_utc"),
    }

def quota_set(panel_used_gb, panel_remain_gb, next_reset_utc_str=None):
    state = load_quota_state()
    cap = round(panel_used_gb + panel_remain_gb, 3)
    next_reset = parse_utc(next_reset_utc_str) if next_reset_utc_str else parse_utc(state["next_reset_utc"])
    now_utc = datetime.now(timezone.utc)
    if next_reset <= now_utc:
        raise ValueError("next_reset_utc must be in the future")

    cycle_start = sub_month_same(next_reset)
    state["cap_gb"] = cap
    state["next_reset_utc"] = iso_utc(next_reset)
    state["cycle_start_utc"] = iso_utc(cycle_start)

    local_used = current_local_cycle_used_gb(state)
    state["offset_gb"] = panel_used_gb - local_used
    state["panel_anchor_used_gb"] = panel_used_gb
    state["panel_anchor_remain_gb"] = panel_remain_gb
    state["local_anchor_used_gb"] = local_used
    state["calibrated_at_utc"] = iso_utc(now_utc)

    save_json(QUOTA_FILE, state)
    return quota_snapshot()

def quota_clear():
    state = load_quota_state()
    state["offset_gb"] = 0.0
    state["panel_anchor_used_gb"] = 0.0
    state["panel_anchor_remain_gb"] = state.get("cap_gb", MONTHLY_CAP_GB)
    state["local_anchor_used_gb"] = 0.0
    state["calibrated_at_utc"] = None
    save_json(QUOTA_FILE, state)
    return quota_snapshot()

def default_runtime_settings():
    return {
        "enable_ipmeta": DEFAULT_ENABLE_IPMETA,
        "ipmeta_max_lookups": DEFAULT_IPMETA_MAX_LOOKUPS,
        "ipmeta_mode": DEFAULT_IPMETA_MODE,
        "daily_notify_time": DEFAULT_DAILY_NOTIFY_TIME if valid_hhmm(DEFAULT_DAILY_NOTIFY_TIME) else "07:51",
        "alert_scan_enabled": True,
        "alert_cn_ssh": 3,
        "alert_probe": 5,
        "alert_unique_src": 3,
        "whitelist": []
    }

def load_runtime_settings():
    s = load_json(SETTINGS_FILE, default_runtime_settings())
    d = default_runtime_settings()
    changed = False

    for k, v in d.items():
        if k not in s:
            s[k] = v
            changed = True

    s["enable_ipmeta"] = bool(s.get("enable_ipmeta", d["enable_ipmeta"]))
    s["alert_scan_enabled"] = bool(s.get("alert_scan_enabled", d["alert_scan_enabled"]))

    try:
        s["ipmeta_max_lookups"] = max(1, min(10, int(s.get("ipmeta_max_lookups", d["ipmeta_max_lookups"]))))
    except Exception:
        s["ipmeta_max_lookups"] = d["ipmeta_max_lookups"]
        changed = True

    if s.get("ipmeta_mode") not in ("manual", "always"):
        s["ipmeta_mode"] = d["ipmeta_mode"]
        changed = True

    if not valid_hhmm(s.get("daily_notify_time", "")):
        s["daily_notify_time"] = d["daily_notify_time"]
        changed = True

    for k in ("alert_cn_ssh", "alert_probe", "alert_unique_src"):
        try:
            s[k] = max(1, min(99, int(s.get(k, d[k]))))
        except Exception:
            s[k] = d[k]
            changed = True

    if not isinstance(s.get("whitelist"), list):
        s["whitelist"] = []
        changed = True

    if changed:
        save_json(SETTINGS_FILE, s)
    return s

def save_runtime_settings(s):
    d = default_runtime_settings()
    s["enable_ipmeta"] = bool(s.get("enable_ipmeta", d["enable_ipmeta"]))
    s["alert_scan_enabled"] = bool(s.get("alert_scan_enabled", d["alert_scan_enabled"]))
    s["ipmeta_max_lookups"] = max(1, min(10, int(s.get("ipmeta_max_lookups", d["ipmeta_max_lookups"]))))
    if s.get("ipmeta_mode") not in ("manual", "always"):
        s["ipmeta_mode"] = d["ipmeta_mode"]
    if not valid_hhmm(s.get("daily_notify_time", "")):
        s["daily_notify_time"] = d["daily_notify_time"]
    for k in ("alert_cn_ssh", "alert_probe", "alert_unique_src"):
        s[k] = max(1, min(99, int(s.get(k, d[k]))))
    if not isinstance(s.get("whitelist"), list):
        s["whitelist"] = []
    save_json(SETTINGS_FILE, s)

def normalize_ip_or_cidr(kind, value):
    if kind == "ip":
        return str(ipaddress.ip_address(value))
    if kind == "cidr":
        return str(ipaddress.ip_network(value, strict=False))
    raise ValueError("kind must be ip or cidr")

def whitelist_entries():
    return load_runtime_settings().get("whitelist", [])

def whitelist_add(kind, value, label=""):
    s = load_runtime_settings()
    norm = normalize_ip_or_cidr(kind, value)
    entries = s.get("whitelist", [])
    for e in entries:
        if e.get("type") == kind and e.get("value") == norm:
            if label:
                e["label"] = label
                save_runtime_settings(s)
            return
    entries.append({"type": kind, "value": norm, "label": label.strip()})
    s["whitelist"] = entries
    save_runtime_settings(s)

def whitelist_remove(value):
    s = load_runtime_settings()
    kept = []
    removed = False
    for e in s.get("whitelist", []):
        if e.get("value") == value:
            removed = True
            continue
        kept.append(e)
    s["whitelist"] = kept
    save_runtime_settings(s)
    return removed

def is_whitelisted(ip):
    try:
        ip_obj = ipaddress.ip_address(ip)
    except Exception:
        return False
    if ip in {"127.0.0.1", "::1"}:
        return True
    if SELF_PUBLIC_IP and ip == SELF_PUBLIC_IP:
        return True
    for e in whitelist_entries():
        try:
            if e.get("type") == "ip" and ip_obj == ipaddress.ip_address(e.get("value")):
                return True
            if e.get("type") == "cidr" and ip_obj in ipaddress.ip_network(e.get("value"), strict=False):
                return True
        except Exception:
            continue
    return False

def whitelist_label(ip):
    try:
        ip_obj = ipaddress.ip_address(ip)
    except Exception:
        return ""
    if SELF_PUBLIC_IP and ip == SELF_PUBLIC_IP:
        return "服务器自身"
    for e in whitelist_entries():
        try:
            if e.get("type") == "ip" and ip_obj == ipaddress.ip_address(e.get("value")):
                return e.get("label", "")
            if e.get("type") == "cidr" and ip_obj in ipaddress.ip_network(e.get("value"), strict=False):
                return e.get("label", "")
        except Exception:
            continue
    return ""

def load_ipmeta_cache():
    return load_json(IPMETA_FILE, {})

def save_ipmeta_cache(cache):
    save_json(IPMETA_FILE, cache)

def ip_meta(ip):
    now = int(time.time())
    cache = load_ipmeta_cache()
    row = cache.get(ip)
    if row and now - int(row.get("ts", 0)) < IPMETA_TTL:
        return row

    url = f"http://ip-api.com/json/{quote(ip)}?fields=status,message,query,country,city,org,isp,as,proxy,hosting,mobile"
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=5) as r:
            data = json.load(r)
        if data.get("status") == "success":
            row = {
                "ts": now,
                "country": data.get("country") or "",
                "city": data.get("city") or "",
                "org": data.get("org") or "",
                "isp": data.get("isp") or "",
                "as": data.get("as") or "",
                "proxy": bool(data.get("proxy")),
                "hosting": bool(data.get("hosting")),
                "mobile": bool(data.get("mobile")),
            }
            cache[ip] = row
            save_ipmeta_cache(cache)
            return row
    except Exception:
        pass

    row = {"ts": now, "country": "", "city": "", "org": "", "isp": "", "as": "", "proxy": False, "hosting": False, "mobile": False}
    cache[ip] = row
    save_ipmeta_cache(cache)
    return row

def should_enrich(context):
    s = load_runtime_settings()
    if not s["enable_ipmeta"]:
        return False
    if context in ("recent", "loginip"):
        return True
    return s["ipmeta_mode"] == "always"

def format_ip_line(ip, context="recent"):
    label = whitelist_label(ip)
    trust_mark = f"（已信任：{label}）" if label else ("（已信任）" if is_whitelisted(ip) and context in ("loginip", "status") else "")
    if not should_enrich(context):
        return f"{ip}{trust_mark}"

    meta = ip_meta(ip)
    loc = "未知"
    if meta.get("country") or meta.get("city"):
        loc = (meta.get("country") or "未知") + ("/" + meta.get("city") if meta.get("city") else "")
    org = meta.get("org") or meta.get("isp") or "未知"
    asn = meta.get("as") or "未知"
    flags = []
    if meta.get("hosting"):
        flags.append("hosting")
    if meta.get("proxy"):
        flags.append("proxy")
    if meta.get("mobile"):
        flags.append("mobile")
    extra = f" [{' '.join(flags)}]" if flags else ""
    return f"{ip}｜{loc}｜{org}｜{asn}{extra}{trust_mark}"

def recent_hits(hours=24):
    try:
        txt = sh("journalctl", "-k", "--since", f"{hours} hours ago", "--no-pager", "-o", "short-iso")
    except Exception:
        return {"count": 0, "uniq": 0, "top": [], "cn_hits": 0, "probe_hits": 0}

    lines = [x for x in txt.splitlines() if ("SSH-CN-DROP" in x or "TCP-PROBE" in x)]
    counts = {}
    cn_hits = 0
    probe_hits = 0
    for line in lines:
        m = re.search(r"SRC=([^ ]+)", line)
        if not m:
            continue
        ip = m.group(1)
        if is_whitelisted(ip):
            continue
        counts[ip] = counts.get(ip, 0) + 1
        if "SSH-CN-DROP" in line:
            cn_hits += 1
        if "TCP-PROBE" in line:
            probe_hits += 1

    top = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:8]
    return {"count": sum(counts.values()), "uniq": len(counts), "top": top, "cn_hits": cn_hits, "probe_hits": probe_hits}

def recent_login_ips(limit=8):
    try:
        txt = sh("last", "-ai")
    except Exception:
        return []
    out = []
    seen = set()
    for line in txt.splitlines():
        s = line.strip()
        if not s or s.startswith("wtmp begins") or s.startswith("reboot") or s.startswith("shutdown"):
            continue
        m = re.search(r'((?:\d{1,3}\.){3}\d{1,3}|[0-9a-fA-F:]{2,})\s*$', s)
        if not m:
            continue
        ip = m.group(1)
        if ip in seen or ip in {".", "0.0.0.0", "::", "::1", "127.0.0.1"}:
            continue
        seen.add(ip)
        out.append(ip)
        if len(out) >= limit:
            break
    return out

def health():
    load = open("/proc/loadavg").read().split()[:3]
    meminfo = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            meminfo[k] = int(v.strip().split()[0])
    mem_total = meminfo.get("MemTotal", 0) / 1024
    mem_avail = meminfo.get("MemAvailable", 0) / 1024
    disk = sh("df", "-h", "/").splitlines()[-1].split()
    uptime_sec = int(float(open("/proc/uptime").read().split()[0]))
    return {
        "load": " ".join(load),
        "mem_total": mem_total,
        "mem_avail": mem_avail,
        "disk_used": disk[2],
        "disk_avail": disk[3],
        "disk_pct": disk[4],
        "uptime_h": uptime_sec / 3600.0,
    }

def should_send_daily_now():
    if not CHAT_ID:
        return False
    s = load_runtime_settings()
    now = datetime.now(REPORT_TZ)
    hhmm = now.strftime("%H:%M")
    if hhmm != s["daily_notify_time"]:
        return False
    today = now.strftime("%Y-%m-%d")
    try:
        with open(DAILY_SENT_FILE, "r", encoding="utf-8") as f:
            if f.read().strip() == today:
                return False
    except Exception:
        pass
    ensure_dir()
    with open(DAILY_SENT_FILE, "w", encoding="utf-8") as f:
        f.write(today)
    return True

def append_alert_history(rec):
    ensure_dir()
    with open(ALERT_HISTORY_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

def read_alert_history(limit=10):
    try:
        with open(ALERT_HISTORY_FILE, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except Exception:
        return []
    out = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except Exception:
            continue
    return out[::-1]

def check_and_send_alerts():
    if not CHAT_ID:
        return
    s = load_runtime_settings()
    if not s["alert_scan_enabled"]:
        return

    try:
        txt = sh("journalctl", "-k", "--since", "10 minutes ago", "--no-pager", "-o", "short-iso")
    except Exception:
        return

    lines = [x for x in txt.splitlines() if ("SSH-CN-DROP" in x or "TCP-PROBE" in x)]
    counts = {}
    cn_hits = 0
    probe_hits = 0
    for line in lines:
        m = re.search(r"SRC=([^ ]+)", line)
        if not m:
            continue
        ip = m.group(1)
        if is_whitelisted(ip):
            continue
        counts[ip] = counts.get(ip, 0) + 1
        if "SSH-CN-DROP" in line:
            cn_hits += 1
        if "TCP-PROBE" in line:
            probe_hits += 1

    uniq_src = len(counts)
    top_ips = [ip for ip, _ in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:5]]

    should_alert = (
        cn_hits >= s["alert_cn_ssh"] or
        probe_hits >= s["alert_probe"] or
        uniq_src >= s["alert_unique_src"]
    )
    if not should_alert:
        return

    now_ts = int(time.time())
    try:
        with open(ALERT_STATE_FILE, "r", encoding="utf-8") as f:
            last = int(f.read().strip())
            if now_ts - last < ALERT_COOLDOWN:
                return
    except Exception:
        pass

    ensure_dir()
    with open(ALERT_STATE_FILE, "w", encoding="utf-8") as f:
        f.write(str(now_ts))

    rec = {
        "time": datetime.now(REPORT_TZ).strftime("%Y-%m-%d %H:%M:%S"),
        "cn_hits": cn_hits,
        "probe_hits": probe_hits,
        "uniq_src": uniq_src,
        "top_ips": top_ips[:3]
    }
    append_alert_history(rec)
    send(probe_alert_text(cn_hits, probe_hits, uniq_src, top_ips[:3]))

def help_text():
    return (
        "控制台\n\n"
        "入口\n"
        "• /start       显示帮助\n\n"
        "概览\n"
        "• /status      状态总览\n"
        "• /daily       每日视图\n"
        "• /quota       配额详情\n"
        "• /update      拉取 GitHub 更新\n\n"
        "安全\n"
        "• /security    安全菜单\n"
        "• /health      系统状态\n\n"
        "设置\n"
        "• /settings    设置菜单\n\n"
        "控制\n"
        "• /reboot      重启确认\n"
        "• /poweroff    关机确认"
    )

def unbound_start_text(msg):
    chat = msg.get("chat") or {}
    chat_id = str(chat.get("id", "")).strip()
    chat_type = str(chat.get("type", "")).strip() or "unknown"
    title = str(chat.get("title", "")).strip()
    username = str(chat.get("username", "")).strip()
    first_name = str(chat.get("first_name", "")).strip()
    last_name = str(chat.get("last_name", "")).strip()

    lines = [
        "机器人已记录当前聊天。",
        "",
        f"• chat_id: {chat_id}",
        f"• type: {chat_type}",
    ]
    if title:
        lines.append(f"• title: {title}")
    full_name = " ".join([x for x in [first_name, last_name] if x]).strip()
    if full_name:
        lines.append(f"• name: {full_name}")
    if username:
        lines.append(f"• username: @{username}")
    lines += [
        "",
        "请回到 VPS 执行：",
        "python3 /opt/neflare-bot/neflare-bot.py --list-chat-candidates",
        "然后绑定你要的 chat_id：",
        "python3 /opt/neflare-bot/neflare-bot.py --bind-chat <chat_id>",
        "绑定后执行：systemctl restart neflare-bot",
    ]
    return "\n".join(lines)
def security_text():
    return (
        "安全菜单\n\n"
        "来源\n"
        "• /recent      近期探测来源\n"
        "• /loginip     近期登录来源\n"
        "• /alerts      告警历史\n"
        "• /whitelist   可信来源\n\n"
        "策略\n"
        "• /scan        告警扫描设置\n"
        "• /threshold   告警阈值\n"
        "• /alerttest   告警预览\n\n"
        "管理\n"
        "• /allow ip <IP> [备注]\n"
        "• /allow cidr <CIDR> [备注]\n"
        "• /remove <IP|CIDR>"
    )

def settings_text():
    s = load_runtime_settings()
    return (
        "设置\n\n"
        "通知\n"
        f"• 每日报告：{s['daily_notify_time']}（北京时间）\n\n"
        "流量\n"
        "• /calibrate   流量校准\n\n"
        "IP 元数据\n"
        f"• 在线查询：{'开启' if s['enable_ipmeta'] else '关闭'}\n"
        f"• 触发方式：{'仅手动页面' if s['ipmeta_mode'] == 'manual' else '所有页面'}\n"
        f"• 单次上限：{s['ipmeta_max_lookups']} 个 IP\n\n"
        "告警扫描\n"
        f"• 当前状态：{'开启' if s['alert_scan_enabled'] else '关闭'}\n\n"
        "子菜单\n"
        "• /notify      通知设置\n"
        "• /ipmeta      IP 元数据设置\n"
        "• /scan        告警扫描设置\n"
        "• /threshold   告警阈值\n"
        "• /whitelist   可信来源\n"
        "• /calibrate   流量校准"
    )

def notify_text():
    s = load_runtime_settings()
    return (
        "通知设置\n\n"
        f"• 每日报告时间：{s['daily_notify_time']}（北京时间）\n\n"
        "修改方式\n"
        "• /set daily_time 07:51\n"
        "• /set daily_time 08:30"
    )

def ipmeta_text():
    s = load_runtime_settings()
    return (
        "IP 元数据设置\n\n"
        f"• 在线查询：{'开启' if s['enable_ipmeta'] else '关闭'}\n"
        f"• 查询模式：{'仅手动页面' if s['ipmeta_mode'] == 'manual' else '所有页面'}\n"
        f"• 单次上限：{s['ipmeta_max_lookups']} 个 IP\n\n"
        "修改方式\n"
        "• /set ipmeta on\n"
        "• /set ipmeta off\n"
        "• /set ipmeta_mode manual\n"
        "• /set ipmeta_mode always\n"
        "• /set ipmeta_max 3"
    )

def scan_text():
    s = load_runtime_settings()
    return (
        "告警扫描设置\n\n"
        f"• 当前状态：{'开启' if s['alert_scan_enabled'] else '关闭'}\n"
        f"• CN SSH 阈值：≥ {s['alert_cn_ssh']}\n"
        f"• 端口探测阈值：≥ {s['alert_probe']}\n"
        f"• 可疑来源阈值：≥ {s['alert_unique_src']}\n\n"
        "修改方式\n"
        "• /set alert_scan on\n"
        "• /set alert_scan off\n"
        "• /threshold\n\n"
        "说明\n"
        "• 关闭后会停止日志扫描与告警推送\n"
        "• 可减少周期性 journalctl 读取"
    )

def threshold_text():
    s = load_runtime_settings()
    return (
        "告警阈值\n\n"
        f"• CN SSH 命中：≥ {s['alert_cn_ssh']}\n"
        f"• 端口探测命中：≥ {s['alert_probe']}\n"
        f"• 可疑来源数量：≥ {s['alert_unique_src']}\n\n"
        "修改方式\n"
        f"• /set alert_cn_ssh {s['alert_cn_ssh']}\n"
        f"• /set alert_probe {s['alert_probe']}\n"
        f"• /set alert_unique_src {s['alert_unique_src']}"
    )

def whitelist_text():
    lines = [f"• {SELF_PUBLIC_IP}（服务器自身，自动忽略）"] if SELF_PUBLIC_IP else []
    for e in whitelist_entries():
        label = f"｜{e.get('label')}" if e.get("label") else ""
        lines.append(f"• {e.get('type')}｜{e.get('value')}{label}")
    if not lines:
        lines = ["• 无"]
    body = "\n".join(lines[:30])
    return (
        "可信来源\n\n"
        f"{body}\n\n"
        "管理方式\n"
        "• /allow ip <IP> [备注]\n"
        "• /allow cidr <CIDR> [备注]\n"
        "• /remove <IP|CIDR>"
    )

def calibrate_text():
    return (
        "流量校准\n\n"
        "用途\n"
        "• 用面板数据修正月度已用 / 剩余\n"
        "• 适合 vnStat 安装较晚、月累计不完整时使用\n\n"
        "命令\n"
        "• /quota_set <已用GB> <剩余GB> [下次重置UTC]\n"
        "• /quota_clear"
    )

def alerts_text():
    rows = read_alert_history(10)
    if not rows:
        return "告警历史\n\n• 暂无记录"
    body = []
    for r in rows:
        ips = ", ".join(r.get("top_ips", [])[:3]) if r.get("top_ips") else "无"
        body.append(
            f"• {r.get('time')}｜CN SSH {r.get('cn_hits')}｜探测 {r.get('probe_hits')}｜来源 {r.get('uniq_src')}｜{ips}"
        )
    return "告警历史\n\n" + "\n".join(body)

def status_text():
    start_cn, now_cn, rx_gb, tx_gb = current_cn_window()
    y_start_cn, y_end_cn, y_rx_gb, y_tx_gb = yesterday_cn_window()
    q = quota_snapshot()
    hits = recent_hits(24)
    h = health()

    probe_lines = [format_ip_line(ip, "status") for ip, _ in hits["top"][:3]]
    login_lines = [format_ip_line(ip, "status") for ip in recent_login_ips(3)]
    probe_block = "\n".join([f"  - {x}" for x in probe_lines]) if probe_lines else "  - 无"
    login_block = "\n".join([f"  - {x}" for x in login_lines]) if login_lines else "  - 无"

    safety = "24 小时未见异常探测" if hits["count"] == 0 else f"24 小时内有 {hits['count']} 次可疑命中"

    return (
        "📊 状态总览\n\n"
        "概览\n"
        f"• 月配额剩余：{q['remain_gb']:.3f} GB\n"
        f"• 日均单向建议：≤ {q['avg_day_half_gb']:.3f} GB\n"
        f"• 安全状态：{safety}\n\n"
        "本日统计窗口\n"
        f"• 北京时间：{start_cn:%m-%d %H:%M} -> {now_cn:%m-%d %H:%M}\n"
        f"• 月配额重置：{parse_utc(q['next_reset_utc']).astimezone(REPORT_TZ):%m-%d %H:%M}（北京时间）\n\n"
        "本日接口流量（双向）\n"
        f"• 入站  {fmt_gb(rx_gb)}\n"
        f"• 出站  {fmt_gb(tx_gb)}\n"
        f"• 合计  {fmt_gb(rx_gb + tx_gb)}\n\n"
        "昨日统计周期\n"
        f"• 北京时间：{y_start_cn:%m-%d %H:%M} -> {y_end_cn:%m-%d %H:%M}\n"
        f"• 入站  {fmt_gb(y_rx_gb)}\n"
        f"• 出站  {fmt_gb(y_tx_gb)}\n"
        f"• 合计  {fmt_gb(y_rx_gb + y_tx_gb)}\n\n"
        "月度配额\n"
        f"• 已用  {q['used_gb']:.3f} / {q['cap_gb']:.3f} GB\n"
        f"• 剩余  {q['remain_gb']:.3f} GB\n"
        f"• 日均总量建议  {q['avg_day_gb']:.3f} GB\n"
        f"• 日均单向建议  {q['avg_day_half_gb']:.3f} GB\n"
        f"• 剩余  {fmt_days(q['days_left'])}\n\n"
        "安全\n"
        f"• 异常命中  {hits['count']} 次 / 24h\n"
        f"• 可疑来源  {hits['uniq']} 个 / 24h\n"
        "• 近期探测\n"
        f"{probe_block}\n"
        "• 近期登录来源\n"
        f"{login_block}\n\n"
        "系统\n"
        f"• Load   {h['load']}\n"
        f"• 内存   {h['mem_avail']:.0f} / {h['mem_total']:.0f} MB 可用\n"
        f"• 磁盘   {h['disk_used']} / {h['disk_avail']}（{h['disk_pct']}）\n"
        f"• 运行   {h['uptime_h']:.3f} 小时"
    )
def daily_text():
    start_cn, now_cn, rx_gb, tx_gb = current_cn_window()
    y_start_cn, y_end_cn, y_rx_gb, y_tx_gb = yesterday_cn_window()
    q = quota_snapshot()
    hits = recent_hits(24)
    safety = "未见异常探测" if hits["count"] == 0 else f"发现 {hits['count']} 次可疑命中"

    return (
        "📅 每日视图\n\n"
        "概览\n"
        f"• 配额状态：剩余 {q['remain_gb']:.3f} GB\n"
        f"• 日均单向建议：≤ {q['avg_day_half_gb']:.3f} GB\n"
        f"• 安全状态：{safety}\n\n"
        "本日统计窗口\n"
        f"• 北京时间：{start_cn:%m-%d %H:%M} -> {now_cn:%m-%d %H:%M}\n\n"
        "本日接口流量（双向）\n"
        f"• 入站  {fmt_gb(rx_gb)}\n"
        f"• 出站  {fmt_gb(tx_gb)}\n"
        f"• 合计  {fmt_gb(rx_gb + tx_gb)}\n\n"
        "昨日统计周期\n"
        f"• 北京时间：{y_start_cn:%m-%d %H:%M} -> {y_end_cn:%m-%d %H:%M}\n"
        f"• 入站  {fmt_gb(y_rx_gb)}\n"
        f"• 出站  {fmt_gb(y_tx_gb)}\n"
        f"• 合计  {fmt_gb(y_rx_gb + y_tx_gb)}\n\n"
        "月度配额\n"
        f"• 已用  {q['used_gb']:.3f} / {q['cap_gb']:.3f} GB\n"
        f"• 剩余  {q['remain_gb']:.3f} GB\n"
        f"• 日均总量建议  {q['avg_day_gb']:.3f} GB\n"
        f"• 日均单向建议  {q['avg_day_half_gb']:.3f} GB\n"
        f"• 剩余  {fmt_days(q['days_left'])}\n\n"
        "安全\n"
        f"• 异常命中  {hits['count']} 次 / 24h\n"
        f"• 可疑来源  {hits['uniq']} 个 / 24h"
    )
def quota_text():
    q = quota_snapshot()
    start_cn, now_cn, rx_gb, tx_gb = current_cn_window()
    calibrated = "无"
    if q["calibrated_at_utc"]:
        calibrated = parse_utc(q["calibrated_at_utc"]).astimezone(REPORT_TZ).strftime("%m-%d %H:%M")

    return (
        "📦 配额详情\n\n"
        f"• 今日窗口：{start_cn:%m-%d %H:%M} → {now_cn:%m-%d %H:%M}（北京时间）\n"
        f"• 今日入站：{fmt_gb(rx_gb)}\n"
        f"• 今日出站：{fmt_gb(tx_gb)}\n"
        f"• 今日合计：{fmt_gb(rx_gb + tx_gb)}\n\n"
        f"• 周期开始：{parse_utc(q['cycle_start_utc']).astimezone(REPORT_TZ):%m-%d %H:%M}（北京时间）\n"
        f"• 下次重置：{parse_utc(q['next_reset_utc']).astimezone(REPORT_TZ):%m-%d %H:%M}（北京时间）\n"
        f"• 总额：{q['cap_gb']:.3f} GB\n"
        f"• 已用：{q['used_gb']:.3f} GB\n"
        f"• 剩余：{q['remain_gb']:.3f} GB\n"
        f"• 建议总量：{q['avg_day_gb']:.3f} GB\n"
        f"• 建议单向：{q['avg_day_half_gb']:.3f} GB\n"
        f"• 剩余天数：{q['days_left']:.3f}\n"
        f"• 本地原始累计：{q['local_used_gb']:.3f} GB\n"
        f"• 校准偏移：{q['offset_gb']:+.3f} GB\n"
        f"• 上次校准：{calibrated}（北京时间）"
    )

def recent_text():
    hits = recent_hits(24)
    if not hits["top"]:
        return "近期探测来源\n\n• 过去 24 小时未见异常来源。"
    body = "\n".join([f"• {format_ip_line(ip, 'recent')} × {n}" for ip, n in hits["top"][:8]])
    return (
        "近期探测来源\n\n"
        f"• 命中次数：{hits['count']}\n"
        f"• 来源数量：{hits['uniq']}\n\n"
        f"{body}"
    )

def loginip_text():
    ips = recent_login_ips(8)
    if not ips:
        return "近期登录来源\n\n• 无"
    body = "\n".join([f"• {format_ip_line(ip, 'loginip')}" for ip in ips])
    return "近期登录来源\n\n" + body

def health_text():
    h = health()
    return (
        "系统状态\n\n"
        f"• Load   {h['load']}\n"
        f"• 内存   {h['mem_avail']:.0f} / {h['mem_total']:.0f} MB 可用\n"
        f"• 磁盘   {h['disk_used']} / {h['disk_avail']}（{h['disk_pct']}）\n"
        f"• 运行   {h['uptime_h']:.3f} 小时"
    )

def probe_alert_text(cn_hits, probe_hits, uniq_src, ips):
    lines = [format_ip_line(ip, "recent") for ip in ips[:3] if ip]
    block = "\n".join([f"• {x}" for x in lines]) if lines else "• 无"
    level = "建议关注"
    if probe_hits >= 10 or uniq_src >= 5:
        level = "建议尽快检查"

    return (
        "可疑探测告警\n\n"
        "结论\n"
        f"• {level}\n"
        f"• CN SSH 命中：{cn_hits}\n"
        f"• 端口探测命中：{probe_hits}\n"
        f"• 可疑来源：{uniq_src} 个\n\n"
        "重点来源\n"
        f"{block}\n\n"
        "建议\n"
        "• 先看 /recent\n"
        "• 再看 /loginip\n"
        "• 必要时执行 /poweroff\n\n"
        f"时间\n• {datetime.now(REPORT_TZ):%Y-%m-%d %H:%M:%S}（北京时间）"
    )

def delayed_systemctl(action):
    subprocess.Popen(["/bin/sh", "-c", f"sleep 3; systemctl {action}"])

def trigger_update():
    script_path = os.path.join(SCRIPT_DIR, "scripts", "update.sh")
    if not os.path.isfile(script_path):
        raise RuntimeError(f"update script not found: {script_path}")

    unit_name = f"{SERVICE_NAME}-update-{int(time.time())}"
    cmd = [
        "systemd-run",
        "--unit", unit_name,
        "--property=Type=oneshot",
        "--collect",
        script_path,
        "--notify",
    ]
    env = dict(os.environ)
    env_file = CFG.get("_ENV_FILE", "")
    if env_file:
        env["NEFLARE_BOT_ENV"] = env_file

    subprocess.Popen(
        cmd,
        cwd=SCRIPT_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return unit_name

def handle_set(parts):
    if len(parts) < 3:
        return (
            "用法\n"
            "• /set daily_time 07:51\n"
            "• /set ipmeta on|off\n"
            "• /set ipmeta_mode manual|always\n"
            "• /set ipmeta_max 3\n"
            "• /set alert_scan on|off\n"
            "• /set alert_cn_ssh 3\n"
            "• /set alert_probe 5\n"
            "• /set alert_unique_src 3"
        )

    s = load_runtime_settings()
    key = parts[1].lower()

    if key == "daily_time":
        if not valid_hhmm(parts[2]):
            return "用法：/set daily_time 07:51"
        s["daily_notify_time"] = parts[2]
        save_runtime_settings(s)
        return "已更新通知设置\n\n" + notify_text()

    if key == "ipmeta":
        val = parts[2].lower()
        if val not in ("on", "off"):
            return "用法：/set ipmeta on|off"
        s["enable_ipmeta"] = (val == "on")
        save_runtime_settings(s)
        return "已更新 IP 元数据设置\n\n" + ipmeta_text()

    if key == "ipmeta_mode":
        val = parts[2].lower()
        if val not in ("manual", "always"):
            return "用法：/set ipmeta_mode manual|always"
        s["ipmeta_mode"] = val
        save_runtime_settings(s)
        return "已更新 IP 元数据设置\n\n" + ipmeta_text()

    if key == "ipmeta_max":
        try:
            n = int(parts[2])
        except Exception:
            return "用法：/set ipmeta_max <1-10>"
        if not 1 <= n <= 10:
            return "ipmeta_max 必须在 1 到 10 之间"
        s["ipmeta_max_lookups"] = n
        save_runtime_settings(s)
        return "已更新 IP 元数据设置\n\n" + ipmeta_text()

    if key == "alert_scan":
        val = parts[2].lower()
        if val not in ("on", "off"):
            return "用法：/set alert_scan on|off"
        s["alert_scan_enabled"] = (val == "on")
        save_runtime_settings(s)
        return "已更新告警扫描设置\n\n" + scan_text()

    if key in ("alert_cn_ssh", "alert_probe", "alert_unique_src"):
        try:
            n = int(parts[2])
        except Exception:
            return f"用法：/set {key} <1-99>"
        if not 1 <= n <= 99:
            return f"{key} 必须在 1 到 99 之间"
        s[key] = n
        save_runtime_settings(s)
        return "已更新告警阈值\n\n" + threshold_text()

    return "未知设置项。输入 /settings 查看设置菜单。"

def handle_allow(parts):
    if len(parts) < 3:
        return (
            "用法\n"
            "• /allow ip <IP> [备注]\n"
            "• /allow cidr <CIDR> [备注]"
        )
    kind = parts[1].lower()
    if kind not in ("ip", "cidr"):
        return "仅支持 ip 或 cidr"
    value = parts[2]
    label = " ".join(parts[3:]).strip()
    try:
        whitelist_add(kind, value, label)
        return "已加入可信来源\n\n" + whitelist_text()
    except Exception as e:
        return f"加入失败：{e}"

def handle_remove(parts):
    if len(parts) != 2:
        return "用法：/remove <IP|CIDR>"
    value = parts[1]
    ok = whitelist_remove(value)
    return ("已移除可信来源\n\n" if ok else "未找到该项\n\n") + whitelist_text()

def handle(text):
    parts = text.strip().split()
    cmd = parts[0].lower() if parts else "/"

    if cmd in ("/", "/start", "/help"):
        return help_text()
    if cmd == "/status":
        return status_text()
    if cmd == "/daily":
        return daily_text()
    if cmd == "/quota":
        return quota_text()
    if cmd == "/security":
        return security_text()
    if cmd == "/settings":
        return settings_text()
    if cmd == "/notify":
        return notify_text()
    if cmd == "/ipmeta":
        return ipmeta_text()
    if cmd == "/scan":
        return scan_text()
    if cmd == "/threshold":
        return threshold_text()
    if cmd == "/whitelist":
        return whitelist_text()
    if cmd == "/calibrate":
        return calibrate_text()
    if cmd == "/alerts":
        return alerts_text()
    if cmd == "/recent":
        return recent_text()
    if cmd == "/loginip":
        return loginip_text()
    if cmd == "/health":
        return health_text()
    if cmd == "/update":
        try:
            unit_name = trigger_update()
            return (
                "已开始拉取 GitHub 最新代码。\n\n"
                f"• 仓库：{CFG.get('REPO_URL', 'https://github.com/Eclirise/neflare-bot')}\n"
                f"• 后台任务：{unit_name}\n"
                f"• 服务：{SERVICE_NAME}\n"
                "• 如检测到新提交，只会重启机器人服务，不会重启整台 VPS。"
            )
        except Exception as e:
            return f"启动更新失败：{e}"
    if cmd == "/set":
        return handle_set(parts)
    if cmd == "/allow":
        return handle_allow(parts)
    if cmd == "/remove":
        return handle_remove(parts)
    if cmd == "/alerttest":
        sample_ips = [ip for ip, _ in recent_hits(24)["top"][:3]]
        if not sample_ips:
            sample_ips = [ip for ip in recent_login_ips(3) if not is_whitelisted(ip)]
        return probe_alert_text(3, 8, max(len(sample_ips), 1), sample_ips)
    if cmd == "/reboot":
        if len(parts) == 2 and parts[1].lower() == "now":
            send("已收到重启指令，3 秒后执行。", chat_id=CHAT_ID)
            delayed_systemctl("reboot")
            return "正在重启…"
        return "确认请发送：/reboot now"
    if cmd == "/poweroff":
        if len(parts) == 2 and parts[1].lower() == "now":
            send("已收到关机指令，3 秒后执行。", chat_id=CHAT_ID)
            delayed_systemctl("poweroff")
            return "正在关机…"
        return "确认请发送：/poweroff now"
    if cmd == "/quota_clear":
        quota_clear()
        return "已清除配额校准偏移\n\n" + quota_text()
    if cmd == "/quota_set":
        if len(parts) not in (3, 4):
            return "用法：/quota_set <已用GB> <剩余GB> [下次重置UTC]"
        try:
            used = float(parts[1])
            remain = float(parts[2])
            next_reset = parts[3] if len(parts) == 4 else None
            quota_set(used, remain, next_reset)
            return "已按面板完成校准\n\n" + quota_text()
        except Exception as e:
            return f"quota_set 失败：{e}"

    return "未识别命令。输入 / 查看控制台。"

def load_offset():
    try:
        return int(open(OFFSET_FILE).read().strip())
    except Exception:
        return 0

def save_offset(v):
    ensure_dir()
    with open(OFFSET_FILE, "w") as f:
        f.write(str(v))

def run_poll():
    try:
        api("deleteWebhook", {"drop_pending_updates": "false"})
    except Exception:
        pass

    offset = load_offset()
    while True:
        try:
            if should_send_daily_now():
                send(daily_text())

            updates = api("getUpdates", {
                "timeout": 50,
                "offset": offset,
                "allowed_updates": json.dumps(["message"]),
            }, timeout=65)

            for upd in updates:
                offset = upd["update_id"] + 1
                save_offset(offset)
                msg = upd.get("message") or {}
                chat = msg.get("chat") or {}
                text = msg.get("text") or ""
                if not text:
                    continue
                chat_id = str(chat.get("id", "")).strip()
                register_chat_candidate(msg)
                if not chat_is_authorized(chat_id):
                    if not CHAT_ID and text.strip().split() and text.strip().split()[0].lower() == "/start":
                        send(unbound_start_text(msg), chat_id=chat_id)
                    continue
                send(handle(text), chat_id=CHAT_ID)
        except Exception:
            time.sleep(3)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "--list-chat-candidates":
            print(list_chat_candidates_text()); sys.exit(0)
        if sys.argv[1] == "--bind-chat":
            if len(sys.argv) != 3:
                print("usage: --bind-chat <chat_id>", file=sys.stderr)
                sys.exit(2)
            env_file = bind_chat_id(sys.argv[2])
            print(f"CHAT_ID saved to {env_file}")
            sys.exit(0)
        if sys.argv[1] == "--send-daily":
            send(daily_text()); sys.exit(0)
        if sys.argv[1] == "--send-status":
            send(status_text()); sys.exit(0)
        if sys.argv[1] == "--send-probe-test":
            sample_ips = [ip for ip, _ in recent_hits(24)["top"][:3]]
            if not sample_ips:
                sample_ips = [ip for ip in recent_login_ips(3) if not is_whitelisted(ip)]
            send(probe_alert_text(3, 8, max(len(sample_ips), 1), sample_ips)); sys.exit(0)
        if sys.argv[1] == "--quota-set":
            if len(sys.argv) not in (4, 5):
                print("usage: --quota-set <used_gb> <remain_gb> [next_reset_utc]", file=sys.stderr)
                sys.exit(2)
            used = float(sys.argv[2]); remain = float(sys.argv[3]); next_reset = sys.argv[4] if len(sys.argv) == 5 else None
            quota_set(used, remain, next_reset); print(quota_text()); sys.exit(0)
        if sys.argv[1] == "--quota-clear":
            quota_clear(); print(quota_text()); sys.exit(0)
        if sys.argv[1] == "--check-alerts":
            check_and_send_alerts(); sys.exit(0)

    run_poll()