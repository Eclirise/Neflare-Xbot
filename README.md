# NeFlare Multi-Protocol Provisioning Repo

NeFlare provisions Debian 12 or Debian 13 VPS hosts into a hardened proxy host with:

- VLESS + REALITY on Xray
- optional Shadowsocks 2022 as an extra Xray inbound
- optional Hysteria 2 as a separate service
- hardened SSH on one persisted high port
- nftables default-drop inbound firewall
- mainland-China SSH geo-blocking via APNIC delegated data
- optional Telegram bot management
- optional disposable Docker-backed network tests
- systemd-timer-backed time synchronization watchdog
- vnStat-backed daily traffic and quota reporting
- validation before reload/restart
- snapshot-backed rollback for managed config changes

## Upgrade Safety

This repo now supports multiple server-side protocols, but the default upgrade path is conservative:

- existing VLESS + REALITY deployments stay enabled by default
- existing REALITY values are preserved on rerun unless you explicitly change them
- newly added protocols stay disabled by default on upgraded hosts
- rerunning `install.sh` does not force Hysteria 2 or Shadowsocks 2022 onto an existing VLESS-only host
- Telegram bot secrets are preserved and do not need to be re-entered during upgrade

The installer preserves the current values for these VLESS + REALITY fields unless you explicitly enter the advanced edit path or provide replacement values in config:

- `XRAY_UUID`
- `XRAY_PRIVATE_KEY`
- `XRAY_PUBLIC_KEY`
- `XRAY_SHORT_IDS`
- `REALITY_SELECTED_DOMAIN`
- `REALITY_SERVER_NAME`
- `REALITY_DEST`
- `XRAY_LISTEN_PORT`

## Supported Layout

- Xray service:
  - VLESS + REALITY
  - Shadowsocks 2022
- Hysteria 2 service:
  - separate binary
  - separate config
  - separate systemd unit

No panel, no database, and no change to the existing Xray service model.

## Scope

Supported:

- Debian 12 `bookworm`
- Debian 13 `trixie`
- systemd-based VPS hosts

Not supported:

- Ubuntu or non-Debian distributions
- provider control-plane firewall automation
- full APNIC signature trust-chain verification
- automatic Hysteria 2 ACME modes other than HTTP-01 in this repo

## Design Notes

- Xray still runs as `root` so REALITY material remains root-readable without a second secret handoff path.
- The Telegram bot still runs as `root` so confirmed maintenance commands can stay simple and explicit.
- REALITY camouflage targets are still operator-supplied only. The repo does not ship baked-in defaults.
- REALITY policy warnings for non-443 ports and discouraged targets are preserved.
- Hysteria 2 is strict opt-in.
- Shadowsocks 2022 is managed as an extra Xray inbound instead of a separate core.
- Hysteria 2 ACME in this repo is implemented with HTTP-01, so enabling ACME also requires opening `TCP/80`.
- Debian 12/13 already ships `systemd-timesyncd`, whose default poll window can grow to `34min 8s`; the NeFlare timer is only a watchdog to re-enable/check sync state instead of replacing the OS sync cadence.

## Repository Layout

- `install.sh`: main installer and verifier entrypoint
- `uninstall.sh`: conservative cleanup and optional network restore
- `lib/`: shared shell libraries and Python helpers
- `templates/`: rendered config templates and example env
- `systemd/`: service and timer units
- `bot/`: Telegram bot implementation
- `verify/`: post-install checks and helper commands
- `old-bot.py`: legacy reference only, not used at runtime

## Runtime Layout

The installer copies runtime assets into:

- `/usr/local/lib/neflare`
- `/usr/local/lib/neflare-bot`
- `/usr/local/bin/neflarectl`

Managed state lives under:

- `/etc/neflare`
- `/var/lib/neflare`
- `/var/lib/neflare-bot`
- `/var/backups/neflare`

Primary managed configs:

- `/etc/neflare/neflare.env`
- `/usr/local/etc/xray/config.json`
- `/etc/neflare/hysteria2.yaml`
- `/etc/neflare/bot.env`

## Installation

Interactive:

```bash
sudo ./install.sh
```

Non-interactive:

```bash
sudo ./install.sh --config /root/neflare.env --non-interactive
```

Fresh install directly from GitHub:

```bash
sudo apt-get update
sudo apt-get install -y git ca-certificates
sudo rm -rf /opt/Neflare-Xbot
sudo git clone --depth=1 -b main https://github.com/Eclirise/Neflare-Xbot.git /opt/Neflare-Xbot
cd /opt/Neflare-Xbot
sudo ./install.sh
```

## Interactive Menu Flow

The interactive installer now uses grouped sections:

1. System / host settings
2. Protocol selection
3. Per-protocol settings
4. Telegram bot settings
5. Final summary / confirmation

Prompt behavior on rerun is existing-value-aware:

- non-secret values show the current value as the default
- sensitive values show markers such as `[configured]` or `[preserve existing]`
- pressing Enter preserves existing secrets
- bot secrets are not printed in plaintext
- REALITY materials are preserved unless you open the advanced VLESS + REALITY edit path

## Configuration

Use `templates/neflare.env.example` as a starting point.

Core flags:

- `ENABLE_VLESS_REALITY=yes`
- `ENABLE_HYSTERIA2=no`
- `ENABLE_SS2022=no`
- `ENABLE_BOT=yes`
- `ENABLE_DOCKER_TESTS=yes`
- `ENABLE_TIME_SYNC=yes`

System / host:

- `ADMIN_USER`
- `ADMIN_PUBLIC_KEY`
- `SSH_PORT`
- `ENABLE_IPV6`
- `ENABLE_TIME_SYNC`
- `REPO_SYNC_URL`
- `REPO_SYNC_BRANCH`
- `REPO_SYNC_DIR`
- `SERVER_PUBLIC_ENDPOINT`

Xray / REALITY:

- `XRAY_LISTEN_PORT`
- `REALITY_CANDIDATES`
- `REALITY_AUTO_RECOMMEND`
- `REALITY_SELECTED_DOMAIN`
- `REALITY_SERVER_NAME`
- `REALITY_DEST`
- `XRAY_UUID`
- `XRAY_PRIVATE_KEY`
- `XRAY_PUBLIC_KEY`
- `XRAY_SHORT_IDS`
- `ALLOW_NONSTANDARD_REALITY_PORT`
- `ALLOW_DISCOURAGED_REALITY_TARGET`

Hysteria 2:

- `HYSTERIA2_VERSION`
- `HYSTERIA2_DOMAIN`
- `HYSTERIA2_LISTEN_PORT`
- `HYSTERIA2_TLS_MODE=acme|file`
- `HYSTERIA2_ACME_EMAIL`
- `HYSTERIA2_ACME_DIR`
- `HYSTERIA2_ACME_CHALLENGE_TYPE=http`
- `HYSTERIA2_ACME_HTTP_PORT=80`
- `HYSTERIA2_TLS_CERT_FILE`
- `HYSTERIA2_TLS_KEY_FILE`
- `HYSTERIA2_AUTH_PASSWORD`
- `HYSTERIA2_MASQUERADE_TYPE=proxy|none`
- `HYSTERIA2_MASQUERADE_URL`
- `HYSTERIA2_MASQUERADE_REWRITE_HOST`
- `HYSTERIA2_MASQUERADE_INSECURE`

Shadowsocks 2022:

- `SS2022_LISTEN_PORT`
- `SS2022_METHOD`
- `SS2022_PASSWORD`

Telegram bot:

- `BOT_TOKEN`
- `CHAT_ID`
- `BOT_BIND_TOKEN`
- `REPORT_TIME`
- `REPORT_TZ`
- `QUOTA_MONTHLY_CAP_GB`
- `QUOTA_RESET_DAY_UTC`
- `BOT_LOG_RETENTION_DAYS`
- `BOT_LOG_MAX_BYTES`

## Protocol Notes

### VLESS + REALITY

- still managed by Xray
- still uses operator-supplied REALITY candidate domains
- still warns on non-443 public listener ports
- still preserves conservative REALITY lint behavior
- existing upgraded hosts keep current REALITY settings by default

### Hysteria 2

- separate service: `neflare-hysteria2`
- separate config: `/etc/neflare/hysteria2.yaml`
- default disabled
- requires only its own variables when `ENABLE_HYSTERIA2=yes`
- can coexist with VLESS + REALITY as:
  - VLESS + REALITY on `TCP/443`
  - Hysteria 2 on `UDP/443`
- repo-supported TLS modes:
  - `acme`
  - `file`
- repo-supported masquerade modes:
  - `proxy`
  - `none`

If you use `HYSTERIA2_TLS_MODE=acme`, this repo configures HTTP-01 and expects `TCP/80` to be reachable.

### Shadowsocks 2022

- extra Xray inbound
- default disabled
- configured directly from installer or env
- managed on a single listener for `TCP/UDP`
- does not modify existing VLESS + REALITY values when enabled later
- should be used with synchronized system time because SS2022 replay protection depends on clock sanity

## Verification

Full verification:

```bash
sudo ./install.sh --verify-only
```

Targeted checks:

```bash
sudo verify/check-ssh.sh
sudo verify/check-firewall.sh
sudo verify/check-xray.sh
sudo verify/check-hysteria2.sh
sudo verify/check-time-sync.sh
sudo verify/check-bbr.sh
sudo verify/check-bot.sh
```

REALITY test and Clash Meta client snippet:

```bash
verify/reality-test.sh example.com
verify/reality-lint.sh
verify/print-client-snippet.sh
```

## Telegram Bot

The bot is optional and still uses long polling.

Installer behavior:

- existing `BOT_TOKEN` and `CHAT_ID` are preserved by default
- bot secrets are shown as configured/not-configured markers instead of plaintext
- if `BOT_TOKEN` is set and `CHAT_ID` is blank, the installer preserves or generates `BOT_BIND_TOKEN`
- reruns do not force bot secrets to be re-entered

`/status` now includes:

- enabled protocols
- listener summary including SSH
- xray service status
- hysteria2 service status when enabled
- time sync status

Example listener summary:

```text
Enabled protocols: VLESS+REALITY, Hysteria 2
Listener summary:
- SSH: TCP 45222
- VLESS+REALITY: TCP 443
- Hysteria 2: UDP 443
- SS2022: disabled
Service status:
- xray: active
- hysteria2: active
- time sync: enabled=yes, synchronized=yes
```

Supported commands remain intentionally limited:

- `/start`
- `/help`
- `/chat_ids`
- `/settings`
- `/notify`
- `/countdown`
- `/countdown_set <YYYY-MM-DD> <HH:MM> <message>`
- `/countdown_clear`
- `/status`
- `/client`
- `/daily`
- `/quota`
- `/health`
- `/calibrate`
- `/quota_set <used_gb> <remain_gb> [next_reset_utc]`
- `/quota_clear`
- `/reality_test <domain>`
- `/reality_set <domain>`
- `/tests`
- `/test <name>`
- `/update_repo`
- `/update_log`
- `/test_log`
- `/restart_xray`
- `/reboot`

## Routine Maintenance

Repository code update:

```bash
cd /opt/Neflare-Xbot
sudo git pull --ff-only
sudo ./install.sh
```

Routine non-interactive rerun from saved config:

```bash
cd /opt/Neflare-Xbot
sudo ./install.sh --config /etc/neflare/neflare.env --non-interactive
```

Explicit Xray core upgrade:

```bash
sudo ./install.sh --upgrade-xray
```

This is intentionally separate from routine repo updates.

Useful runtime commands:

```bash
sudo neflarectl verify
sudo neflarectl status
sudo neflarectl daily
sudo neflarectl quota
sudo neflarectl print-policy
sudo neflarectl print-client
sudo neflarectl time-sync
sudo neflarectl reality-test example.com
sudo neflarectl reality-set example.com
sudo neflarectl repo-sync --yes
```

## Safe Upgrade for Existing VLESS + REALITY Hosts

Existing VLESS + REALITY-only hosts can safely update with:

```bash
cd /opt/Neflare-Xbot
sudo git pull --ff-only
sudo ./install.sh
```

Expected default behavior:

- `ENABLE_VLESS_REALITY` stays `yes`
- `ENABLE_HYSTERIA2` stays `no` unless you enable it
- `ENABLE_SS2022` stays `no` unless you enable it
- `ENABLE_TIME_SYNC` defaults to `yes` so SS2022 and other replay-sensitive protocols can rely on a synchronized clock
- current REALITY UUID, keys, short IDs, domain, destination, and listener port stay unchanged
- existing bot secrets stay unchanged

## Enable Hysteria 2 Later

Edit `/etc/neflare/neflare.env` and set at least:

```bash
ENABLE_HYSTERIA2=yes
HYSTERIA2_DOMAIN=hy2.example.com
HYSTERIA2_LISTEN_PORT=443
HYSTERIA2_TLS_MODE=acme
HYSTERIA2_ACME_EMAIL=admin@example.com
HYSTERIA2_AUTH_PASSWORD='replace-with-your-secret'
HYSTERIA2_MASQUERADE_TYPE=proxy
HYSTERIA2_MASQUERADE_URL=https://news.ycombinator.com/
```

Then rerun:

```bash
sudo ./install.sh --config /etc/neflare/neflare.env --non-interactive
```

If you use ACME mode, open `TCP/80` and make sure the domain resolves to the server first.

## Enable Shadowsocks 2022 Later

Edit `/etc/neflare/neflare.env` and set at least:

```bash
ENABLE_SS2022=yes
SS2022_LISTEN_PORT=40010
SS2022_METHOD=2022-blake3-aes-256-gcm
SS2022_PASSWORD='replace-with-your-secret'
ENABLE_TIME_SYNC=yes
```

Then rerun:

```bash
sudo ./install.sh --config /etc/neflare/neflare.env --non-interactive
```

For best interoperability, use a proper SS2022 key such as `openssl rand -base64 32` and keep the host clock synchronized.

## Rollback

Managed config changes are snapshot-backed. The latest snapshot id is stored in:

- `/etc/neflare/last-snapshot-id`

Network restore from the latest snapshot:

```bash
sudo ./uninstall.sh --restore-network
```

Network restore from a specific snapshot:

```bash
sudo ./uninstall.sh --restore-network --snapshot 20260326T120000Z
```

For service-level rollback after a bad rerun:

1. inspect the current `/etc/neflare/neflare.env`
2. revert the changed protocol flags or settings
3. rerun `sudo ./install.sh --config /etc/neflare/neflare.env --non-interactive`

The installer validates managed configs before restart where the underlying service supports it, and restores the previous managed state if Xray or Hysteria 2 restart fails.
