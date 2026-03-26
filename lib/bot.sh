#!/usr/bin/env bash

readonly BOT_ENV_FILE="${NEFLARE_CONFIG_DIR}/bot.env"
readonly BOT_SYSTEMD_UNIT="/etc/systemd/system/neflare-bot.service"

ensure_vnstat_interface_initialized() {
  if ! vnstat --iflist 2>/dev/null | tr ' ' '\n' | grep -Fxq "${NETWORK_INTERFACE}"; then
    vnstat --add -i "${NETWORK_INTERFACE}" >/dev/null 2>&1 || true
  fi
  systemctl enable vnstat >/dev/null 2>&1 || true
  systemctl restart vnstat >/dev/null 2>&1 || true
}

write_bot_env_file() {
  snapshot_file_once "${BOT_ENV_FILE}"
  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/bot.env.tpl" "${BOT_ENV_FILE}" \
    "UI_LANG=${UI_LANG}" \
    "NEFLARE_CONFIG_FILE=${NEFLARE_CONFIG_FILE}" \
    "NEFLARE_STATE_DIR=${NEFLARE_STATE_DIR}" \
    "NEFLARE_BOT_STATE_DIR=${NEFLARE_BOT_STATE_DIR}" \
    "BOT_TOKEN=${BOT_TOKEN}" \
    "CHAT_ID=${CHAT_ID}" \
    "REPORT_TIME=${REPORT_TIME}" \
    "REPORT_TZ=${REPORT_TZ}" \
    "NETWORK_INTERFACE=${NETWORK_INTERFACE}" \
    "QUOTA_MONTHLY_CAP_GB=${QUOTA_MONTHLY_CAP_GB}" \
    "QUOTA_RESET_DAY_UTC=${QUOTA_RESET_DAY_UTC}"
  chmod 0600 "${BOT_ENV_FILE}"
}

install_bot_unit() {
  snapshot_file_once "${BOT_SYSTEMD_UNIT}"
  install_file_atomic "${NEFLARE_SOURCE_ROOT}/systemd/neflare-bot.service" "${BOT_SYSTEMD_UNIT}" 0644 root root
  systemctl daemon-reload
}

configure_optional_bot() {
  if [[ "${ENABLE_BOT}" != "yes" ]]; then
    info "Telegram bot not enabled; skipping bot deployment."
    return 0
  fi

  mkdir_root_only "${NEFLARE_BOT_STATE_DIR}"
  ensure_vnstat_interface_initialized
  write_bot_env_file
  install_bot_unit

  if [[ -n "${BOT_TOKEN}" ]]; then
    systemctl enable --now neflare-bot
    success "Telegram bot deployed and started"
  else
    systemctl disable --now neflare-bot >/dev/null 2>&1 || true
    warn "Telegram bot files deployed, but BOT_TOKEN is empty so the service was not started."
  fi
}
