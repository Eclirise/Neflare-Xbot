#!/usr/bin/env bash

readonly BOT_ENV_FILE="${NEFLARE_CONFIG_DIR}/bot.env"
readonly BOT_SYSTEMD_UNIT="/etc/systemd/system/neflare-bot.service"
readonly BOT_REALITY_LINT_SERVICE_UNIT="/etc/systemd/system/neflare-reality-lint-watch.service"
readonly BOT_REALITY_LINT_TIMER_UNIT="/etc/systemd/system/neflare-reality-lint-watch.timer"

ensure_vnstat_interface_initialized() {
  if ! vnstat --iflist 2>/dev/null | tr ' ' '\n' | grep -Fxq "${NETWORK_INTERFACE}"; then
    vnstat --add -i "${NETWORK_INTERFACE}" >/dev/null 2>&1 || true
  fi
  systemctl enable vnstat >/dev/null 2>&1 || true
  systemctl restart vnstat >/dev/null 2>&1 || true
}

write_bot_env_file() {
  snapshot_file_once "${BOT_ENV_FILE}"
  write_env_file "${BOT_ENV_FILE}" \
    "UI_LANG=${UI_LANG}" \
    "NEFLARE_CONFIG_FILE=${NEFLARE_CONFIG_FILE}" \
    "NEFLARE_STATE_DIR=${NEFLARE_STATE_DIR}" \
    "NEFLARE_BOT_STATE_DIR=${NEFLARE_BOT_STATE_DIR}" \
    "ENABLE_DOCKER_TESTS=${ENABLE_DOCKER_TESTS}" \
    "BOT_LOG_RETENTION_DAYS=${BOT_LOG_RETENTION_DAYS}" \
    "BOT_LOG_MAX_BYTES=${BOT_LOG_MAX_BYTES}" \
    "REPO_SYNC_URL=${REPO_SYNC_URL}" \
    "REPO_SYNC_BRANCH=${REPO_SYNC_BRANCH}" \
    "REPO_SYNC_DIR=${REPO_SYNC_DIR}" \
    "BOT_TOKEN=${BOT_TOKEN}" \
    "CHAT_ID=${CHAT_ID}" \
    "BOT_BIND_TOKEN=${BOT_BIND_TOKEN}" \
    "REPORT_TIME=${REPORT_TIME}" \
    "REPORT_TZ=${REPORT_TZ}" \
    "NETWORK_INTERFACE=${NETWORK_INTERFACE}" \
    "QUOTA_MONTHLY_CAP_GB=${QUOTA_MONTHLY_CAP_GB}" \
    "QUOTA_RESET_DAY_UTC=${QUOTA_RESET_DAY_UTC}"
}

install_bot_units() {
  snapshot_file_once "${BOT_SYSTEMD_UNIT}"
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-bot.service" "${BOT_SYSTEMD_UNIT}" 0644 root root
  if [[ -f "${BOT_REALITY_LINT_SERVICE_UNIT}" ]]; then
    snapshot_file_once "${BOT_REALITY_LINT_SERVICE_UNIT}"
    rm -f "${BOT_REALITY_LINT_SERVICE_UNIT}"
  fi
  if [[ -f "${BOT_REALITY_LINT_TIMER_UNIT}" ]]; then
    snapshot_file_once "${BOT_REALITY_LINT_TIMER_UNIT}"
    rm -f "${BOT_REALITY_LINT_TIMER_UNIT}"
  fi
  systemctl daemon-reload
}

configure_optional_bot() {
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    snapshot_file_once "${BOT_ENV_FILE}"
    systemctl disable --now neflare-reality-lint-watch.timer >/dev/null 2>&1 || true
    systemctl disable --now neflare-bot >/dev/null 2>&1 || true
    rm -f "${BOT_ENV_FILE}"
    info "Telegram bot not enabled; disabled the bot and reality-lint timer units and removed the bot environment file."
    return 0
  fi

  mkdir_root_only "${NEFLARE_BOT_STATE_DIR}"
  ensure_vnstat_interface_initialized
  write_bot_env_file
  install_bot_units

  if [[ -n "${BOT_TOKEN}" ]]; then
    if systemctl is-active --quiet neflare-bot; then
      systemctl enable neflare-bot >/dev/null 2>&1 || true
      systemctl restart neflare-bot
    else
      systemctl enable --now neflare-bot
    fi
    systemctl disable --now neflare-reality-lint-watch.timer >/dev/null 2>&1 || true
    success "Telegram bot deployed and started"
  else
    systemctl disable --now neflare-reality-lint-watch.timer >/dev/null 2>&1 || true
    systemctl disable --now neflare-bot >/dev/null 2>&1 || true
    warn "Telegram bot files deployed, but BOT_TOKEN is empty so the bot service was not started."
  fi
}
