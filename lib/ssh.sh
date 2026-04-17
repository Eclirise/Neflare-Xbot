#!/usr/bin/env bash

readonly SSHD_DROPIN_PATH="/etc/ssh/sshd_config.d/50-neflare.conf"
readonly SUDOERS_DROPIN_PATH="/etc/sudoers.d/90-neflare-admin"

CURRENT_ADMIN_SOURCE_IP="${CURRENT_ADMIN_SOURCE_IP:-}"
CURRENT_ADMIN_SOURCE_FAMILY="${CURRENT_ADMIN_SOURCE_FAMILY:-}"

detect_current_admin_source() {
  CURRENT_ADMIN_SOURCE_IP=""
  CURRENT_ADMIN_SOURCE_FAMILY=""
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    CURRENT_ADMIN_SOURCE_IP="$(awk '{print $1}' <<<"${SSH_CONNECTION}")"
  fi
  if [[ -z "${CURRENT_ADMIN_SOURCE_IP}" ]]; then
    CURRENT_ADMIN_SOURCE_IP="$(who -m 2>/dev/null | sed -n 's/.*(\(.*\)).*/\1/p' | head -n1 || true)"
  fi
  if [[ -z "${CURRENT_ADMIN_SOURCE_IP}" ]]; then
    CURRENT_ADMIN_SOURCE_IP="$(who am i 2>/dev/null | sed -n 's/.*(\(.*\)).*/\1/p' | head -n1 || true)"
  fi
  if [[ -n "${CURRENT_ADMIN_SOURCE_IP}" ]]; then
    if [[ "${CURRENT_ADMIN_SOURCE_IP}" == *:* ]]; then
      CURRENT_ADMIN_SOURCE_FAMILY="6"
    else
      CURRENT_ADMIN_SOURCE_FAMILY="4"
    fi
    info "Detected current admin source ${CURRENT_ADMIN_SOURCE_IP} (IPv${CURRENT_ADMIN_SOURCE_FAMILY})"
  else
    warn "Unable to detect current admin source IP from the current session."
  fi
}

detect_current_sshd_primary_port() {
  local port
  port="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}')"
  printf '%s\n' "${port:-22}"
}

user_home_dir() {
  getent passwd "$1" | awk -F: '{print $6}'
}

visudo_binary_path() {
  local candidate=""
  candidate="$(command -v visudo 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  for candidate in /usr/sbin/visudo /sbin/visudo /usr/bin/visudo; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

ensure_admin_user() {
  snapshot_file_once "${SUDOERS_DROPIN_PATH}"
  if id "${ADMIN_USER}" >/dev/null 2>&1; then
    info "Admin user ${ADMIN_USER} already exists"
  else
    info "Creating admin user ${ADMIN_USER}"
    useradd --create-home --shell /bin/bash --groups sudo "${ADMIN_USER}"
    CREATED_ADMIN_USER="yes"
  fi

  local home_dir
  home_dir="$(user_home_dir "${ADMIN_USER}")"
  [[ -n "${home_dir}" ]] || die "Unable to determine home directory for ${ADMIN_USER}"

  install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${home_dir}/.ssh"
  local auth_keys="${home_dir}/.ssh/authorized_keys"
  touch "${auth_keys}"
  chmod 0600 "${auth_keys}"
  chown "${ADMIN_USER}:${ADMIN_USER}" "${auth_keys}"
  if ! grep -Fqx "${ADMIN_PUBLIC_KEY}" "${auth_keys}"; then
    printf '%s\n' "${ADMIN_PUBLIC_KEY}" >> "${auth_keys}"
  fi
  chown "${ADMIN_USER}:${ADMIN_USER}" "${auth_keys}"
  chmod 0600 "${auth_keys}"

  if [[ "${ADMIN_NOPASSWD_SUDO}" == "yes" ]]; then
    local visudo_bin=""
    visudo_bin="$(visudo_binary_path)" || die "visudo was not found. Install the sudo package correctly before continuing."
    install_text "${SUDOERS_DROPIN_PATH}" "${ADMIN_USER} ALL=(ALL:ALL) NOPASSWD:ALL
" 0440 root root
    "${visudo_bin}" -cf "${SUDOERS_DROPIN_PATH}" >/dev/null
  else
    rm -f "${SUDOERS_DROPIN_PATH}"
  fi
}

render_sshd_dropin() {
  local destination="$1"
  local port_lines="$2"
  local hardening_lines="$3"
  render_template_to "${NEFLARE_SOURCE_ROOT}/templates/sshd_config.neflare.conf.tpl" "${destination}" \
    "PORT_LINES=${port_lines}" \
    "HARDENING_LINES=${hardening_lines}" \
    "ADMIN_USER=${ADMIN_USER}"
}

validate_sshd_config() {
  sshd -t
}

reload_sshd_or_rollback() {
  local previous_path="$1"
  if systemctl reload ssh; then
    return 0
  fi
  warn "sshd reload failed; restoring ${SSHD_DROPIN_PATH}"
  if [[ -s "${previous_path}" ]]; then
    cp -a "${previous_path}" "${SSHD_DROPIN_PATH}"
  else
    rm -f "${SSHD_DROPIN_PATH}"
  fi
  systemctl reload ssh || true
  die "sshd reload failed and original configuration was restored."
}

apply_sshd_dropin_with_rollback() {
  local rendered_file="$1"
  snapshot_file_once "${SSHD_DROPIN_PATH}"
  local previous
  previous="$(mktemp)"
  if [[ -f "${SSHD_DROPIN_PATH}" ]]; then
    cp -a "${SSHD_DROPIN_PATH}" "${previous}"
  else
    : > "${previous}"
  fi

  install_file_atomic "${rendered_file}" "${SSHD_DROPIN_PATH}" 0600 root root
  if ! validate_sshd_config; then
    warn "sshd validation failed; restoring previous drop-in"
    if [[ -s "${previous}" ]]; then
      cp -a "${previous}" "${SSHD_DROPIN_PATH}"
    else
      rm -f "${SSHD_DROPIN_PATH}"
    fi
    validate_sshd_config || true
    rm -f "${previous}"
    die "sshd validation failed."
  fi
  reload_sshd_or_rollback "${previous}"
  rm -f "${previous}"
}

confirm_ssh_cutover() {
  if bool_is_true "${NON_INTERACTIVE:-0}"; then
    [[ "${SSH_CUTOVER_CONFIRMED}" == "yes" ]] || die "Non-interactive mode requires SSH_CUTOVER_CONFIRMED=yes before final SSH hardening."
    return 0
  fi

  if [[ "$(current_ui_lang)" == "zh" ]]; then
    cat >&2 <<EOF
请先新开一个 SSH 会话，并确认下面这条命令可以成功登录，然后再继续最终加固：
  ssh -p ${SSH_PORT} ${ADMIN_USER}@${SERVER_PUBLIC_ENDPOINT}

确认新的密钥登录链路可用后，回到这里输入 verified。
EOF
  else
    cat >&2 <<EOF
Open a second SSH session now and verify that the following login works before final hardening:
  ssh -p ${SSH_PORT} ${ADMIN_USER}@${SERVER_PUBLIC_ENDPOINT}

Once the new key-based path is confirmed, return here and type 'verified'.
EOF
  fi
  local answer=""
  while [[ "${answer}" != "verified" ]]; do
    if [[ "$(current_ui_lang)" == "zh" ]]; then
      read -r -p "输入 verified 继续最终 SSH 加固： " answer
    else
      read -r -p "Type 'verified' to continue with final SSH hardening: " answer
    fi
  done
  SSH_CUTOVER_CONFIRMED="yes"
}

configure_ssh_hardening() {
  detect_current_admin_source
  local current_port stage1_file stage2_file port_lines_stage1 hardening_stage1 hardening_stage2
  current_port="$(detect_current_sshd_primary_port)"
  info "Current sshd primary port is ${current_port}"

  port_lines_stage1="Port ${current_port}"
  if [[ "${current_port}" != "${SSH_PORT}" ]]; then
    port_lines_stage1="${port_lines_stage1}
Port ${SSH_PORT}"
  fi
  hardening_stage1="PubkeyAuthentication yes
PermitEmptyPasswords no
UsePAM yes"
  stage1_file="$(mktemp)"
  render_sshd_dropin "${stage1_file}" "${port_lines_stage1}" "${hardening_stage1}"
  apply_sshd_dropin_with_rollback "${stage1_file}"
  rm -f "${stage1_file}"

  confirm_ssh_cutover

  hardening_stage2="PubkeyAuthentication yes
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
UsePAM yes
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2"
  stage2_file="$(mktemp)"
  render_sshd_dropin "${stage2_file}" "Port ${SSH_PORT}" "${hardening_stage2}"
  apply_sshd_dropin_with_rollback "${stage2_file}"
  rm -f "${stage2_file}"
  success "SSH hardening applied on port ${SSH_PORT}"
}
