#!/usr/bin/env bash

lang_normalize() {
  case "${1:-}" in
    zh|ZH|zh_CN|zh-cn|zh-Hans|cn|CN|chinese|中文|简体中文) printf 'zh\n' ;;
    en|EN|en_US|en-us|english|英文) printf 'en\n' ;;
    "") printf '\n' ;;
    *) printf 'en\n' ;;
  esac
}

current_ui_lang() {
  local normalized
  normalized="$(lang_normalize "${UI_LANG:-}")"
  printf '%s\n' "${normalized:-en}"
}

choose_ui_language() {
  local current_default=""
  if [[ -n "${UI_LANG:-}" ]]; then
    UI_LANG="$(lang_normalize "${UI_LANG}")"
  fi
  current_default="${UI_LANG:-en}"

  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    UI_LANG="${current_default}"
    export UI_LANG
    return 0
  fi

  local answer=""
  printf 'Select installer language / 选择安装语言 [en/zh] [%s]: ' "${current_default}" >&2
  read -r answer || true
  UI_LANG="$(lang_normalize "${answer:-${current_default}}")"
  UI_LANG="${UI_LANG:-${current_default}}"
  export UI_LANG
}

i18n_bool() {
  local value
  value="$(normalize_yes_no "${1:-}")"
  case "$(current_ui_lang):${value}" in
    zh:yes) printf '是' ;;
    zh:no) printf '否' ;;
    en:yes) printf 'yes' ;;
    en:no) printf 'no' ;;
    *) printf '%s' "${1:-}" ;;
  esac
}

i18n_none() {
  if [[ "$(current_ui_lang)" == "zh" ]]; then
    printf '无'
  else
    printf 'none'
  fi
}

i18n_text() {
  local key="$1"
  shift || true
  local format=""

  case "$(current_ui_lang):${key}" in
    zh:prompt_admin_user) format='管理员用户名' ;;
    zh:prompt_admin_key) format='管理员 SSH 公钥' ;;
    zh:prompt_ssh_port) format='持久化 SSH 端口' ;;
    zh:prompt_enable_ipv6) format='启用 IPv6（yes/no）' ;;
    zh:prompt_xray_port) format='公网 REALITY 监听端口' ;;
    zh:warn_non443) format='使用非 443 的公网 REALITY 端口是本项目中的非默认、高风险运维选择。' ;;
    zh:confirm_non443) format='确认继续使用非 443 的公网 REALITY 端口 %s' ;;
    zh:prompt_reality_candidates) format='请输入至少 2 个 REALITY 伪装候选域名，使用逗号分隔（必填，不提供内置默认目标）' ;;
    zh:prompt_auto_select) format='自动选择测试后最优且可接受的候选目标（yes/no）' ;;
    zh:prompt_selected_reality_domain) format='选择 REALITY 域名（留空使用推荐值 %s）' ;;
    zh:prompt_enable_bot) format='启用 Telegram Bot 支持（yes/no）' ;;
    zh:prompt_bot_token) format='Telegram BOT_TOKEN（留空表示稍后再启用 Bot）' ;;
    zh:prompt_chat_id) format='Telegram CHAT_ID（留空表示稍后绑定）' ;;
    zh:prompt_report_time) format='日报发送时间 HH:MM' ;;
    zh:prompt_report_tz) format='日报时区' ;;
    zh:prompt_quota_cap) format='月流量配额（GB，0 表示不限制）' ;;
    zh:prompt_quota_reset) format='每月配额重置日（UTC，建议 1-28）' ;;
    zh:prompt_server_endpoint) format='客户端连接地址覆盖（IP/域名，留空自动检测）' ;;
    zh:confirm_continue) format="输入 'yes'、'确认' 或 '是' 继续: " ;;
    zh:summary_done) format='已完成：' ;;
    zh:summary_not_done) format='未完成：' ;;
    zh:summary_limitations) format='限制：' ;;
    zh:summary_manual) format='手动后续步骤：' ;;
    zh:policy_header) format='策略摘要：' ;;
    zh:cloud_firewall_header) format='云厂商防火墙手动规则：' ;;
    zh:provider_inbound_drop) format='- 入站默认：DROP' ;;
    zh:provider_outbound_accept) format='- 出站默认：ACCEPT' ;;
    zh:provider_allow_xray) format='- 放行任意来源 TCP/%s' ;;
    zh:provider_allow_ssh) format='- 放行你的管理来源到 TCP/%s' ;;
    zh:policy_port443) format='- 公网 REALITY 端口是否为 443：%s' ;;
    zh:policy_ipv6) format='- IPv6 模式：%s' ;;
    zh:policy_triggered) format='- 所选伪装目标是否触发运维风险告警：%s' ;;
    zh:policy_level) format='- 所选伪装目标风险级别：%s' ;;
    zh:policy_apple) format='- 所选目标是否为 Apple/iCloud 相关：%s' ;;
    zh:policy_unresolved) format='- 未解决的保守性告警：%s' ;;
    zh:verify_ok) format='校验完成且通过。' ;;
    zh:install_done_notice) format='安装器语言已切换为中文。' ;;
    zh:runtime_language_notice) format='当前输出语言：中文。' ;;
    zh:error_reality_candidates_required) format='REALITY_CANDIDATES 为必填项。本安装器不会内置默认伪装目标。' ;;
    zh:error_reality_candidates_count) format='请至少提供 2 个不同的 REALITY 候选域名。' ;;
    zh:error_invalid_reality_selection) format='所选 REALITY 域名 %s 与预期行为不兼容。' ;;
    en:prompt_admin_user) format='Admin user' ;;
    en:prompt_admin_key) format='Admin SSH public key' ;;
    en:prompt_ssh_port) format='Persisted SSH port' ;;
    en:prompt_enable_ipv6) format='Enable IPv6 (yes/no)' ;;
    en:prompt_xray_port) format='Public REALITY listener port' ;;
    en:warn_non443) format='Using a public REALITY listener port other than 443 is a non-default, higher-risk operational choice for this project.' ;;
    en:confirm_non443) format='Proceed with non-443 public REALITY listener port %s' ;;
    en:prompt_reality_candidates) format='Enter at least 2 REALITY camouflage candidate domains, comma-separated (required; no built-in default target list)' ;;
    en:prompt_auto_select) format='Auto-select the best tested acceptable candidate (yes/no)' ;;
    en:prompt_selected_reality_domain) format='Selected REALITY domain (blank for recommended %s)' ;;
    en:prompt_enable_bot) format='Enable Telegram bot support (yes/no)' ;;
    en:prompt_bot_token) format='Telegram BOT_TOKEN (blank to defer bot start)' ;;
    en:prompt_chat_id) format='Telegram CHAT_ID (blank to bind later)' ;;
    en:prompt_report_time) format='Daily report time HH:MM' ;;
    en:prompt_report_tz) format='Daily report timezone' ;;
    en:prompt_quota_cap) format='Monthly quota cap in GB (0 disables cap)' ;;
    en:prompt_quota_reset) format='Monthly quota reset day in UTC (1-28 recommended)' ;;
    en:prompt_server_endpoint) format='Client-facing server IP/domain override (blank to auto-detect)' ;;
    en:confirm_continue) format="Type 'yes' to continue: " ;;
    en:summary_done) format='Done:' ;;
    en:summary_not_done) format='Not done:' ;;
    en:summary_limitations) format='Limitations:' ;;
    en:summary_manual) format='Manual follow-up steps:' ;;
    en:policy_header) format='Policy summary:' ;;
    en:cloud_firewall_header) format='Provider firewall manual rules:' ;;
    en:provider_inbound_drop) format='- Inbound default: DROP' ;;
    en:provider_outbound_accept) format='- Outbound default: ACCEPT' ;;
    en:provider_allow_xray) format='- Allow TCP/%s from anywhere' ;;
    en:provider_allow_ssh) format='- Allow TCP/%s from your admin source(s)' ;;
    en:policy_port443) format='- Public REALITY port is 443: %s' ;;
    en:policy_ipv6) format='- IPv6 mode: %s' ;;
    en:policy_triggered) format='- Selected camouflage target triggered operational-risk warnings: %s' ;;
    en:policy_level) format='- Selected camouflage target warning level: %s' ;;
    en:policy_apple) format='- Selected target is Apple/iCloud-related: %s' ;;
    en:policy_unresolved) format='- Unresolved conservative warnings: %s' ;;
    en:verify_ok) format='Verification suite completed successfully.' ;;
    en:install_done_notice) format='Installer language set to English.' ;;
    en:runtime_language_notice) format='Current output language: English.' ;;
    en:error_reality_candidates_required) format='REALITY_CANDIDATES is required. This installer does not bake in a default camouflage target.' ;;
    en:error_reality_candidates_count) format='Provide at least 2 distinct REALITY candidate domains.' ;;
    en:error_invalid_reality_selection) format='Selected REALITY domain %s is incompatible with the intended behavior.' ;;
    *) format='%s' ; set -- "${key}" "$@" ;;
  esac

  printf -- "${format}" "$@"
}
