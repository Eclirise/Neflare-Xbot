# NeFlare Xray REALITY Provisioning Repo

NeFlare provisions a fresh Debian 12 or Debian 13 VPS into a production-minded Xray VLESS + REALITY server with a default public listener on TCP/RAW 443 and:

- hardened SSH on one persisted high port
- nftables default-drop inbound firewall
- mainland-China SSH geo-blocking via APNIC delegated data
- optional Telegram bot management, enabled by default on fresh installs
- periodic REALITY lint watch with Telegram change notifications
- optional disposable Docker-backed network tests, enabled by default on fresh installs
- vnStat-backed daily traffic and quota reporting
- explicit validation before reload/restart
- snapshot-backed rollback for managed config changes
- final Mihomo / Clash.Meta-compatible client snippet output

## Scope

Supported:

- Debian 12 `bookworm`
- Debian 13 `trixie`
- fresh-host style provisioning with systemd

Not supported:

- Ubuntu or other distributions
- provider control-plane firewall automation
- full APNIC signature trust-chain verification

## Design Notes

- Xray runs as `root` in this project. This is intentional so REALITY key material and config can remain root-readable without adding a second secret-distribution path. The service is still hardened with a restrictive systemd drop-in.
- The Telegram bot service also runs as `root`. This is intentional so confirmed maintenance commands such as repo sync, service control, and verification can be executed without a separate privilege handoff path.
- The CN SSH geo-block updater uses HTTPS transport, strict APNIC parsing, nftables validation, atomic replacement, and last-known-good rollback. It does not claim cryptographic source attestation beyond that.
- IPv6 is an explicit installer choice. If enabled, nftables applies explicit IPv6 policy and SSH CN geo-blocking when IPv6 CN ranges are available. If disabled, the installer applies sysctl-based IPv6 disablement and reports that state clearly.
- The installer does not ship a baked-in REALITY camouflage target list. You must provide candidate domains. Auto-recommendation means selecting the least risky acceptable candidate from your supplied set after transparent scoring and policy linting.
- The first interactive installer prompt is the UI language selector (`English` or `中文`). The chosen language is persisted as `UI_LANG` and reused by installer summaries and bot status/report output.
- REALITY candidate input is mandatory and must contain at least 2 distinct domains. The installer tests the supplied set and picks the best acceptable option unless you override it.
- Apple/iCloud-related or tutorial-like camouflage patterns are discouraged operationally and are flagged explicitly rather than treated as good defaults.
- Disposable Docker-backed tests are optional but enabled by default on fresh installs. When enabled, the installer preserves an existing Docker installation when present, otherwise installs Docker and configures it for host-network test runs with Docker firewall management disabled, so it should not be mixed with an existing custom Docker network setup.

## Repository Layout

- `install.sh`: main installer and verifier entrypoint
- `uninstall.sh`: conservative cleanup and optional network restore
- `lib/`: shared shell libraries and Python helpers
- `templates/`: rendered config templates
- `systemd/`: service and timer units
- `bot/`: modular Telegram bot implementation
- `verify/`: post-install checks and helper commands
- `old-bot.py`: legacy reference only, not used at runtime

## Installation

Interactive:

```bash
sudo ./install.sh
```

Fresh install directly from GitHub:

```bash
sudo apt-get update && sudo apt-get install -y git ca-certificates && sudo rm -rf /opt/Neflare-Xbot && sudo git clone --depth=1 -b main https://github.com/Eclirise/Neflare-Xbot.git /opt/Neflare-Xbot && cd /opt/Neflare-Xbot && sudo ./install.sh
```

Fresh Debian 12/13 VPS from zero after first login or reboot:

These command sets assume you are already in a `root` shell on the VPS.
If you are not `root`, prefix the commands with `sudo`.

Fresh interactive deployment:

```bash
apt-get update
apt-get install -y git ca-certificates
rm -rf /opt/Neflare-Xbot
git clone --depth=1 -b main https://github.com/Eclirise/Neflare-Xbot.git /opt/Neflare-Xbot
cd /opt/Neflare-Xbot
chmod +x install.sh
bash install.sh
```

Fresh non-interactive deployment with a local config file:

```bash
apt-get update
apt-get install -y git ca-certificates
rm -rf /opt/Neflare-Xbot
git clone --depth=1 -b main https://github.com/Eclirise/Neflare-Xbot.git /opt/Neflare-Xbot
cp /opt/Neflare-Xbot/templates/neflare.env.example /root/neflare.env
cd /opt/Neflare-Xbot
chmod +x install.sh
# edit /root/neflare.env before running the next line
bash install.sh --config /root/neflare.env --non-interactive
```

Non-interactive:

```bash
sudo ./install.sh --config /root/neflare.env --non-interactive
```

The installer will:

1. validate Debian version
2. collect or load configuration
3. create a snapshot under `/var/backups/neflare`
4. install required packages
5. deploy runtime assets to `/usr/local/lib/neflare`, `/usr/local/lib/neflare-bot`, and `/usr/local/bin/neflarectl`
6. create or reuse the admin user and install the provided public key
7. perform a two-phase SSH cutover before disabling root/password login
8. install or explicitly upgrade Xray through the official install flow
9. generate REALITY UUID, X25519 keys, and short IDs
10. test and score REALITY camouflage candidates
11. lint REALITY policy choices and warn or fail conservatively
12. render and validate Xray config before restart
13. apply explicit IPv4/IPv6 nftables rules
14. install and run the CN SSH geo-block updater
15. schedule weekly CN SSH geo-block refreshes
16. enable BBR only if supported
17. optionally install and configure Docker for disposable network tests
18. optionally deploy the Telegram bot
19. run verification and print summary plus client YAML

## Configuration

Use `templates/neflare.env.example` as a starting point.

Important keys:

- `ADMIN_USER`
- `ADMIN_PUBLIC_KEY`
- `UI_LANG`
- `SSH_PORT`
- `ENABLE_IPV6`
- `ENABLE_BOT`
- `ENABLE_DOCKER_TESTS`
- `BOT_LOG_RETENTION_DAYS`
- `BOT_LOG_MAX_BYTES`
- `REPO_SYNC_URL`
- `REPO_SYNC_BRANCH`
- `REPO_SYNC_DIR`
- `XRAY_INSTALL_SCRIPT_URL`
- `XRAY_INSTALL_SCRIPT_SHA256`
- `XRAY_INSTALL_VERIFY_SHA256`
- `BOT_TOKEN`
- `CHAT_ID`
- `BOT_BIND_TOKEN`
- `REPORT_TIME`
- `REPORT_TZ`
- `QUOTA_MONTHLY_CAP_GB`
- `QUOTA_RESET_DAY_UTC`
- `REALITY_CANDIDATES`
- `REALITY_AUTO_RECOMMEND`
- `XRAY_LISTEN_PORT`
- `ALLOW_NONSTANDARD_REALITY_PORT`
- `ALLOW_DISCOURAGED_REALITY_TARGET`
- `SERVER_PUBLIC_ENDPOINT`

Installed runtime config is stored in:

- `/etc/neflare/neflare.env`
- `/etc/neflare/bot.env`

Both are root-readable only.

REALITY policy notes:

- `REALITY_CANDIDATES` is required. The repo does not provide baked-in camouflage defaults.
- `REALITY_CANDIDATES` must contain at least 2 distinct domains supplied by the operator.
- `XRAY_LISTEN_PORT=443` is the default and recommended public listener.
- If you set a non-443 public listener, also set `ALLOW_NONSTANDARD_REALITY_PORT=yes` and expect a strong warning.
- If you intentionally want a discouraged but still technically compatible target, set `ALLOW_DISCOURAGED_REALITY_TARGET=yes` and review the policy warnings carefully.
- `ENABLE_BOT=yes` is the default for fresh installs. Set it to `no` if you do not want Telegram bot management deployed.
- `ENABLE_DOCKER_TESTS=yes` is the default for fresh installs. Set it to `no` if you do not want the disposable `/test` runtime installed and configured.
- `REPORT_TZ=Asia/Shanghai` is the default for fresh installs.
- `BOT_LOG_RETENTION_DAYS=14` is the default. Set it to `0` to disable age-based pruning of bot-managed JSON logs.
- `BOT_LOG_MAX_BYTES=65536` is the default. Set it to `0` to disable size-based pruning of bot-managed JSON logs.
- `REPO_SYNC_URL=https://github.com/Eclirise/Neflare-Xbot.git`, `REPO_SYNC_BRANCH=main`, and `REPO_SYNC_DIR=/opt/Neflare-Xbot` are the default repo-sync settings used by `neflarectl repo-sync` and Telegram `/update_repo`.

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
sudo verify/check-bbr.sh
sudo verify/check-bot.sh
```

Reality test and client snippet:

```bash
verify/reality-test.sh example.com
verify/reality-lint.sh
verify/print-client-snippet.sh
```

## Routine Maintenance

Repository code update:

1. pull or sync the repo normally
2. rerun `sudo ./install.sh` or `sudo ./install.sh --config ... --non-interactive`
3. review verification output

One-command repo sync from the configured GitHub checkout:

```bash
sudo neflarectl repo-sync --yes
```

Explicit Xray-core upgrade:

```bash
sudo ./install.sh --upgrade-xray
```

This is intentionally separate from routine repo updates.
The upstream Xray install helper URL is still pinned by this repo to a specific `Xray-install` commit by default, so repo-controlled installer behavior remains explicit.
SHA-256 enforcement for that helper is now disabled by default (`XRAY_INSTALL_VERIFY_SHA256=no`), and existing installs using the old pinned default policy are migrated to `no` on the next installer run.
If you want to re-enable checksum enforcement, set `XRAY_INSTALL_VERIFY_SHA256=yes` in your config and keep `XRAY_INSTALL_SCRIPT_SHA256` aligned with the exact helper script URL.

The CN SSH geo-block updater runs weekly by systemd timer. You can force an immediate refresh with:

```bash
sudo neflarectl update-cn-ssh-geo
```

Useful runtime commands:

```bash
sudo neflarectl verify
sudo neflarectl reality-test example.com
sudo neflarectl reality-set example.com
sudo neflarectl reality-lint
sudo neflarectl reality-lint-watch
sudo neflarectl lint-log
sudo neflarectl tests
sudo neflarectl test-run unlock_media
sudo neflarectl test-log
sudo neflarectl repo-log
sudo neflarectl repo-sync --yes
sudo neflarectl print-policy
sudo neflarectl print-client
sudo neflarectl quota
sudo neflarectl quota-set 120 380 2026-05-01T00:00:00Z
sudo neflarectl quota-clear
```

## Telegram Bot

The bot is optional and uses long polling for simplicity and reliability on small VPS deployments.

Installer behavior:

- if you enable bot support, the installer prompts for `BOT_TOKEN`
- `CHAT_ID` is optional during install
- if `BOT_TOKEN` is set and `CHAT_ID` is left blank, the bot starts unbound, records candidate chats, and the installer generates a one-time `BOT_BIND_TOKEN`
- send `/start` to the bot to see the currently known chat ids, then send `/claim <BOT_BIND_TOKEN>` from your chosen private chat to bind that Telegram account as the sole controller
- once `CHAT_ID` is bound, only that chat can issue bot commands
- once bound, every bot restart/startup sends a concise online notice to the authorized chat and continues daily notifications at the configured `REPORT_TIME` / `REPORT_TZ`

Supported commands:

- `/start`
- `/help`
- `/chat_ids`
- `/settings`
- `/notify`
- `/countdown`
- `/countdown_set <YYYY-MM-DD> <HH:MM> <message>`
- `/countdown_clear`
- `/status`
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

The bot no longer installs the old timer-driven `reality-lint` watcher by default. REALITY checks remain available on demand through `neflarectl reality-lint` and the Telegram REALITY commands, but the bot avoids background alerting/noisy periodic scans.

Docker-backed test notes:

- `/tests` lists the supported disposable checks, but only when `ENABLE_DOCKER_TESTS=yes`.
- `/test <name>` queues a background job, so the bot stays responsive while the test runs.
- The job runs inside a one-shot Docker container, fetches the upstream test script at runtime, uses a common non-interactive shell environment plus official script arguments where available, and sends the cleaned result back to Telegram after completion.
- When `ENABLE_DOCKER_TESTS=yes`, the installer preserves an existing Docker installation when present, otherwise installs Docker and configures it for this feature with `host` networking plus Docker firewall management disabled.
- On Debian 13 `trixie`, the installer also installs `docker-cli` when needed because `docker.io` may provide `dockerd` without the `docker` client binary.
- The runtime uses `--rm`, a `none` Docker log driver, explicit labeled-container pruning, and image cleanup when the base image did not already exist on the host.
- Bot-side formatting strips common Docker pull noise, ANSI color escapes, and generic menu/prompt noise before returning long test output to Telegram.
- Bot-managed JSON logs are pruned automatically by age and size, and only compact metadata is kept locally; the detailed test output is returned to Telegram instead of being stored in full on disk.
- Cleanup is still best-effort for Docker resources created by this feature; it reduces leftover state substantially, but does not claim forensic zero-trace removal from daemon logs or journal history.

Repo sync notes:

- `/update_repo` queues a background root-owned repo sync job and reruns `./install.sh --config /etc/neflare/neflare.env --non-interactive` from the configured checkout.
- the sync now force-aligns the checkout to `origin/<REPO_SYNC_BRANCH>` and overwrites local checkout changes in the configured repo-sync directory before rerunning `install.sh`
- The default repo-sync target is this GitHub repository on branch `main` under `/opt/Neflare-Xbot`.
- `/update_log` shows recent repo sync attempts with timestamps, exit codes, and resulting commit ids.

If `BOT_TOKEN` is empty during install, the bot files and units are deployed but the services are not started. After populating `BOT_TOKEN` and optionally `CHAT_ID`, start them with:

```bash
sudo systemctl enable --now neflare-bot
```

Automatic chat binding:

- leave `CHAT_ID` blank during install
- start the bot service
- open chats with the bot as needed so it can record candidate chat ids
- send `/start` to inspect the currently seen chat ids
- send `/claim <BOT_BIND_TOKEN>` from your chosen private chat
- that private chat becomes the sole authorized controller

Manual override binding:

```bash
sudo neflarectl list-chat-candidates
sudo neflarectl bind-chat <chat_id>
sudo systemctl restart neflare-bot
```

`/reality_test` and `/reality_set` return:

- compatibility result
- latency/stability result
- policy warning level
- discouraged pattern matches
- whether the target is Apple/iCloud-related

## Rollback

Managed config changes are snapshot-backed and validated before reload/restart. The installer stores the latest snapshot id in:

- `/etc/neflare/last-snapshot-id`

Network restore from the latest snapshot:

```bash
sudo ./uninstall.sh --restore-network
```

Network restore from a specific snapshot:

```bash
sudo ./uninstall.sh --restore-network --snapshot 20260326T120000Z
```
