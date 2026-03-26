#!/usr/bin/env bash

readonly REALITY_POLICY_STATE_FILE="${NEFLARE_STATE_DIR}/reality-policy.json"
REALITY_PROBE_RESULT_FILE="${REALITY_PROBE_RESULT_FILE:-}"

reality_candidate_list() {
  [[ -n "${REALITY_CANDIDATES}" ]] || die "REALITY_CANDIDATES is required. No built-in camouflage target list is provided."
  parse_comma_list "${REALITY_CANDIDATES}"
}

run_reality_probe() {
  local output_file="$1"
  shift
  python3 "${NEFLARE_RUNTIME_LIB_DIR}/reality_probe.py" \
    --json \
    --public-port "${XRAY_LISTEN_PORT}" \
    "$@" > "${output_file}"
}

print_reality_probe_report() {
  local json_file="$1"
  jq -r '.candidates[] | [
      .domain,
      .compatibility_result,
      .latency_result,
      .policy.recommendation,
      .policy.warning_level,
      ("score=" + ((.score // 0)|tostring)),
      ("summary=" + .summary)
    ] | @tsv' "${json_file}" | while IFS=$'\t' read -r domain compatibility latency recommendation level score summary; do
      info "REALITY candidate ${domain}: compatibility=${compatibility}; latency=${latency}; recommendation=${recommendation}; policy=${level}; ${score}; ${summary}"
    done
}

persist_selected_reality_state() {
  local json_file="$1"
  local domain="$2"
  mkdir_root_only "${NEFLARE_STATE_DIR}"
  jq --arg domain "${domain}" --argjson port "${XRAY_LISTEN_PORT}" '
    {
      selected_at: .generated_at,
      public_port: $port,
      selected: (.candidates[] | select(.domain == $domain))
    }
  ' "${json_file}" > "${REALITY_POLICY_STATE_FILE}.tmp"
  install_file_atomic "${REALITY_POLICY_STATE_FILE}.tmp" "${REALITY_POLICY_STATE_FILE}" 0600 root root
  rm -f "${REALITY_POLICY_STATE_FILE}.tmp"
}

require_reality_selection_allowed() {
  local json_file="$1"
  local domain="$2"
  local recommendation warning_level
  recommendation="$(jq -r --arg domain "${domain}" '.candidates[] | select(.domain == $domain) | .policy.recommendation' "${json_file}")"
  warning_level="$(jq -r --arg domain "${domain}" '.candidates[] | select(.domain == $domain) | .policy.warning_level' "${json_file}")"

  if [[ "${recommendation}" == "recommended" || "${recommendation}" == "acceptable" ]]; then
    return 0
  fi

  warn "Selected REALITY target ${domain} is ${recommendation} with policy level '${warning_level}'."
  jq -r --arg domain "${domain}" '.candidates[] | select(.domain == $domain) | .policy.unresolved_warnings[]?' "${json_file}" >&2 || true

  if [[ "${ALLOW_DISCOURAGED_REALITY_TARGET:-no}" == "yes" ]]; then
    return 0
  fi
  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    die "Selection of discouraged/high-risk REALITY targets requires ALLOW_DISCOURAGED_REALITY_TARGET=yes."
  fi
  confirm_or_die "Proceed with discouraged/high-risk REALITY target ${domain}."
  ALLOW_DISCOURAGED_REALITY_TARGET="yes"
}

select_reality_candidate() {
  local json_file="$1"
  local recommended choice current_selected default_choice
  recommended="$(jq -r '.recommended // empty' "${json_file}")"

  print_reality_probe_report "${json_file}"

  if [[ -z "${recommended}" && "${REALITY_AUTO_RECOMMEND}" == "yes" ]]; then
    die "No REALITY candidate reached the recommended/acceptable policy threshold. Provide better candidates or explicitly choose a discouraged target."
  fi

  current_selected=""
  if [[ -n "${REALITY_SELECTED_DOMAIN}" ]] && jq -e --arg domain "${REALITY_SELECTED_DOMAIN}" '.candidates[] | select(.domain == $domain and .compatible == true)' "${json_file}" >/dev/null; then
    current_selected="${REALITY_SELECTED_DOMAIN}"
    if [[ -n "${recommended}" && "${recommended}" != "${current_selected}" ]]; then
      info "Current REALITY domain ${current_selected} remains compatible. Probe recommendation is ${recommended}."
    fi
  fi

  if bool_is_true "${NON_INTERACTIVE:-0}" || [[ "${REALITY_AUTO_RECOMMEND}" == "yes" ]]; then
    choice="${current_selected:-${recommended}}"
  else
    default_choice="${current_selected:-${recommended}}"
    choice="$(read_prompt "$(i18n_text prompt_selected_reality_domain "${recommended:-$(i18n_none)}")" "${default_choice}" yes)"
  fi
  [[ -n "${choice}" ]] || die "No REALITY domain was selected."

  jq -e --arg domain "${choice}" '.candidates[] | select(.domain == $domain and .compatible == true)' "${json_file}" >/dev/null \
    || die "$(i18n_text error_invalid_reality_selection "${choice}")"

  require_reality_selection_allowed "${json_file}" "${choice}"

  REALITY_SELECTED_DOMAIN="${choice}"
  REALITY_SERVER_NAME="${choice}"
  REALITY_DEST="${choice}:443"
  persist_selected_reality_state "${json_file}" "${choice}"
  save_installed_config
  success "Selected REALITY camouflage domain ${REALITY_SELECTED_DOMAIN}"
}

test_and_select_reality_candidate() {
  local probe_file
  probe_file="$(mktemp)"
  trap 'rm -f "${probe_file}"' RETURN
  local candidates=()
  while IFS= read -r candidate; do
    candidates+=("${candidate}")
  done < <(reality_candidate_list)
  [[ "${#candidates[@]}" -gt 0 ]] || die "No REALITY candidate domains available."

  run_reality_probe "${probe_file}" "${candidates[@]}"
  REALITY_PROBE_RESULT_FILE="${probe_file}"
  select_reality_candidate "${probe_file}"
}

reality_test_single_domain() {
  local domain="$1"
  python3 "${NEFLARE_RUNTIME_LIB_DIR}/reality_probe.py" --json --public-port "${XRAY_LISTEN_PORT}" "${domain}"
}

lint_current_reality_policy() {
  [[ -n "${REALITY_SELECTED_DOMAIN}" ]] || die "REALITY_SELECTED_DOMAIN is not configured."
  local probe_json
  probe_json="$(mktemp)"
  trap 'rm -f "${probe_json}"' RETURN
  reality_test_single_domain "${REALITY_SELECTED_DOMAIN}" > "${probe_json}"
  persist_selected_reality_state "${probe_json}" "${REALITY_SELECTED_DOMAIN}"
  local warning_level
  warning_level="$(jq -r '.candidates[0].policy.warning_level' "${probe_json}")"
  if [[ "${warning_level}" == "strong warning" || "${warning_level}" == "soft warning" ]]; then
    warn "REALITY policy checker reported ${warning_level} for ${REALITY_SELECTED_DOMAIN}"
    jq -r '.candidates[0].policy.unresolved_warnings[]?' "${probe_json}" >&2 || true
  fi
  if [[ "${warning_level}" == "hard failure" ]]; then
    jq -r '.candidates[0].policy.unresolved_warnings[]?' "${probe_json}" >&2 || true
    die "Current REALITY configuration failed policy linting."
  fi
}

reality_set_domain() {
  local domain="$1"
  local force="${2:-no}"
  local probe_json
  probe_json="$(mktemp)"
  local rendered
  rendered="$(mktemp)"
  trap 'rm -f "${probe_json}" "${rendered}"' RETURN
  reality_test_single_domain "${domain}" > "${probe_json}"

  jq -e '.candidates[0].compatible == true' "${probe_json}" >/dev/null \
    || { rm -f "${probe_json}"; die "Domain ${domain} is incompatible with the intended REALITY behavior."; }

  if [[ "${force}" != "yes" ]]; then
    require_reality_selection_allowed "${probe_json}" "${domain}"
  fi

  REALITY_SELECTED_DOMAIN="${domain}"
  REALITY_SERVER_NAME="${domain}"
  REALITY_DEST="${domain}:443"
  render_xray_config_file "${rendered}"
  apply_xray_config "${rendered}"
  persist_selected_reality_state "${probe_json}" "${domain}"
  save_installed_config
  success "REALITY destination switched to ${domain}"
}

policy_state_field() {
  local jq_filter="$1"
  if [[ -f "${REALITY_POLICY_STATE_FILE}" ]]; then
    jq -r "${jq_filter}" "${REALITY_POLICY_STATE_FILE}"
  else
    printf '\n'
  fi
}
