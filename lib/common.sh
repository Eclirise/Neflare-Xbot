#!/usr/bin/env bash

if [[ -n "${NEFLARE_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
readonly NEFLARE_COMMON_SH_LOADED=1

COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${NEFLARE_SOURCE_ROOT:-}" ]]; then
  NEFLARE_SOURCE_ROOT="$(cd "${COMMON_SH_DIR}/.." && pwd)"
fi

readonly NEFLARE_SOURCE_ROOT
readonly NEFLARE_INSTALL_ROOT="${NEFLARE_INSTALL_ROOT:-/usr/local/lib/neflare}"
readonly NEFLARE_RUNTIME_LIB_DIR="${NEFLARE_RUNTIME_LIB_DIR:-${NEFLARE_INSTALL_ROOT}/lib}"
readonly NEFLARE_RUNTIME_BIN_DIR="${NEFLARE_RUNTIME_BIN_DIR:-/usr/local/bin}"
readonly NEFLARE_BOT_INSTALL_DIR="${NEFLARE_BOT_INSTALL_DIR:-/usr/local/lib/neflare-bot}"
readonly NEFLARE_CONFIG_DIR="${NEFLARE_CONFIG_DIR:-/etc/neflare}"
readonly NEFLARE_CONFIG_FILE="${NEFLARE_CONFIG_FILE:-${NEFLARE_CONFIG_DIR}/neflare.env}"
readonly NEFLARE_STATE_DIR="${NEFLARE_STATE_DIR:-/var/lib/neflare}"
readonly NEFLARE_BOT_STATE_DIR="${NEFLARE_BOT_STATE_DIR:-/var/lib/neflare-bot}"
readonly NEFLARE_BACKUP_ROOT="${NEFLARE_BACKUP_ROOT:-/var/backups/neflare}"
readonly NEFLARE_LOCK_DIR="${NEFLARE_LOCK_DIR:-/run/neflare}"

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(timestamp_utc)" "${level}" "$*" >&2
}

info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }
success() { log OK "$@"; }

die() {
  error "$@"
  exit 1
}

bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON|y|Y|是|开|开启|启用) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_yes_no() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON|y|Y|是|开|开启|启用) printf 'yes\n' ;;
    0|false|FALSE|no|NO|off|OFF|n|N|否|关|关闭|禁用) printf 'no\n' ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

ensure_root() {
  [[ "${EUID}" -eq 0 ]] || die "This command must be run as root."
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_commands() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    if ! command_exists "${cmd}"; then
      missing+=("${cmd}")
    fi
  done
  [[ "${#missing[@]}" -eq 0 ]] || die "Missing required commands: ${missing[*]}"
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

join_by() {
  local delimiter="$1"
  shift || true
  local first=1
  local item
  for item in "$@"; do
    if [[ "${first}" -eq 1 ]]; then
      printf '%s' "${item}"
      first=0
    else
      printf '%s%s' "${delimiter}" "${item}"
    fi
  done
  printf '\n'
}

mkdir_root_only() {
  local dir="$1"
  install -d -m 0700 -o root -g root "${dir}"
}

mkdir_system_dir() {
  local dir="$1"
  local mode="${2:-0755}"
  install -d -m "${mode}" -o root -g root "${dir}"
}

shell_quote_env_value() {
  printf '%q' "${1:-}"
}

write_env_file() {
  local destination="$1"
  shift
  local tmp
  tmp="$(mktemp "${destination}.tmp.XXXXXX")"
  local pair key value
  : > "${tmp}"
  for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    printf '%s=%q\n' "${key}" "${value}" >> "${tmp}"
  done
  install -m 0600 -o root -g root "${tmp}" "${destination}"
  rm -f "${tmp}"
}

source_env_file() {
  local path="$1"
  [[ -f "${path}" ]] || return 0
  local parsed
  parsed="$(mktemp)"
  python3 - "${path}" > "${parsed}" <<'PY'
import pathlib
import re
import shlex
import sys

env_path = pathlib.Path(sys.argv[1])
key_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

for raw_line in env_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    tokens = shlex.split(line, posix=True)
    if not tokens or "=" not in tokens[0]:
        continue
    key, value = tokens[0].split("=", 1)
    key = key.strip()
    if not key_re.match(key):
        continue
    print(f"{key}={shlex.quote(value)}")
PY
  # shellcheck disable=SC1090
  set -a && source "${parsed}" && set +a
  rm -f "${parsed}"
}

set_env_value() {
  local path="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp "${path}.tmp.XXXXXX")"
  if [[ -f "${path}" ]]; then
    awk -v key="${key}" 'BEGIN { found=0 }
      $0 ~ ("^" key "=") { found=1; next }
      { print }
      END { if (!found) { } }
    ' "${path}" > "${tmp}"
  else
    : > "${tmp}"
  fi
  printf '%s=%q\n' "${key}" "${value}" >> "${tmp}"
  install -m 0600 -o root -g root "${tmp}" "${path}"
  rm -f "${tmp}"
}

render_template_to() {
  local source="$1"
  local destination="$2"
  shift 2
  local tmp_render tmp_pairs pair
  tmp_render="$(mktemp)"
  tmp_pairs="$(mktemp)"
  : > "${tmp_pairs}"
  for pair in "$@"; do
    printf '%s\0' "${pair}" >> "${tmp_pairs}"
  done
  python3 - "${source}" "${tmp_render}" "${tmp_pairs}" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
pairs_file = pathlib.Path(sys.argv[3])
text = source.read_text(encoding="utf-8")
for raw_pair in pairs_file.read_bytes().split(b"\0"):
    if not raw_pair:
        continue
    pair = raw_pair.decode("utf-8")
    key, value = pair.split("=", 1)
    text = text.replace(f"__{key}__", value)
dest.write_text(text, encoding="utf-8", newline="\n")
PY
  install_file_atomic "${tmp_render}" "${destination}"
  rm -f "${tmp_render}" "${tmp_pairs}"
}

install_text() {
  local destination="$1"
  local content="$2"
  local mode="${3:-0600}"
  local owner="${4:-root}"
  local group="${5:-root}"
  local tmp
  tmp="$(mktemp "${destination}.tmp.XXXXXX")"
  printf '%s' "${content}" > "${tmp}"
  install -m "${mode}" -o "${owner}" -g "${group}" "${tmp}" "${destination}"
  rm -f "${tmp}"
}

install_file_atomic() {
  local source="$1"
  local destination="$2"
  local mode="${3:-0600}"
  local owner="${4:-root}"
  local group="${5:-root}"
  local tmp
  tmp="$(mktemp "${destination}.tmp.XXXXXX")"
  cat "${source}" > "${tmp}"
  install -m "${mode}" -o "${owner}" -g "${group}" "${tmp}" "${destination}"
  rm -f "${tmp}"
}

copy_tree_contents() {
  local source_dir="$1"
  local target_dir="$2"
  mkdir_system_dir "${target_dir}" 0755
  local file
  while IFS= read -r -d '' file; do
    local rel="${file#"${source_dir}/"}"
    local dest="${target_dir}/${rel}"
    mkdir_system_dir "$(dirname "${dest}")" 0755
    install -m 0644 -o root -g root "${file}" "${dest}"
  done < <(find "${source_dir}" -type f -print0)
}

read_prompt() {
  local prompt="$1"
  local default_value="${2:-}"
  local required="${3:-no}"
  local secret="${4:-no}"
  local result=""

  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    if [[ -n "${default_value}" || "${required}" != "yes" ]]; then
      printf '%s\n' "${default_value}"
      return 0
    fi
    die "Required interactive value missing for prompt: ${prompt}"
  fi

  if [[ "${secret}" == "yes" ]]; then
    if [[ -n "${default_value}" ]]; then
      read -r -s -p "${prompt} [hidden, press Enter to keep existing]: " result
      printf '\n' >&2
      if [[ -z "${result}" ]]; then
        printf '%s\n' "${default_value}"
      else
        printf '%s\n' "${result}"
      fi
    else
      while [[ -z "${result}" ]]; do
        read -r -s -p "${prompt}: " result
        printf '\n' >&2
        if [[ "${required}" != "yes" ]]; then
          break
        fi
      done
      printf '%s\n' "${result}"
    fi
    return 0
  fi

  if [[ -n "${default_value}" ]]; then
    read -r -p "${prompt} [${default_value}]: " result
    if [[ -z "${result}" ]]; then
      result="${default_value}"
    fi
  else
    while [[ -z "${result}" && "${required}" == "yes" ]]; do
      read -r -p "${prompt}: " result
    done
  fi
  printf '%s\n' "${result}"
}

confirm_or_die() {
  local message="$1"
  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    die "Non-interactive mode requires explicit confirmation for: ${message}"
  fi
  local answer suffix
  if declare -F i18n_text >/dev/null 2>&1; then
    suffix="$(i18n_text confirm_continue)"
  else
    suffix="Type 'yes' to continue: "
  fi
  read -r -p "${message} ${suffix}" answer
  case "${answer}" in
    yes|YES|y|Y|是|确认|確認) return 0 ;;
  esac
  die "Confirmation not granted."
}

json_quote() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

csv_to_json_array() {
  python3 - "$1" <<'PY'
import json
import sys
items = [x.strip() for x in sys.argv[1].split(",") if x.strip()]
print(json.dumps(items))
PY
}

newline_list_to_json_array() {
  python3 <<'PY'
import json
import sys
items = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(items))
PY
}

json_get() {
  local file="$1"
  local key="$2"
  python3 - "${file}" "${key}" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data
for part in sys.argv[2].split("."):
    if not part:
        continue
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

detect_primary_interface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

detect_route_source_ip() {
  local family="${1:-4}"
  if [[ "${family}" == "6" ]]; then
    ip -6 route get 2001:4860:4860::8888 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  else
    ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  fi
}

generate_random_high_port() {
  local candidate
  while true; do
    candidate="$(shuf -i 40000-59999 -n 1)"
    if [[ "${candidate}" != "443" ]] && ! ss -H -ltn "( sport = :${candidate} )" | grep -q .; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
}

generate_hex() {
  local length="$1"
  openssl rand -hex "${length}"
}

parse_comma_list() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
for item in [x.strip() for x in sys.argv[1].split(",") if x.strip()]:
    print(item)
PY
}
