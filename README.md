# NeFlare Xray REALITY Provisioning Repo

NeFlare provisions a fresh Debian 12 or Debian 13 VPS into a production-minded Xray VLESS + REALITY server with a default public listener on TCP/RAW 443 and:

- hardened SSH on one persisted high port
- nftables default-drop inbound firewall
- mainland-China SSH geo-blocking via APNIC delegated data
- optional Telegram bot management
- periodic REALITY lint watch with Telegram change notifications
- optional disposable Docker-backed network tests
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
- Disposable Docker-backed tests are optional and disabled by default. When enabled, the installer installs Docker and configures it for host-network test runs with Docker firewall management disabled, so it should not be mixed with an existing custom Docker network setup.

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
- `BOT_TOKEN`
- `CHAT_ID`
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
- `ENABLE_DOCKER_TESTS=no` is the default. Set it to `yes` only if you want the disposable `/test` runtime installed and configured.
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
The upstream Xray install helper is pinned by this repo to an exact commit and SHA-256; changing that pin is an explicit repo update, not an implicit fetch of upstream `main`.

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
- if `BOT_TOKEN` is set and `CHAT_ID` is left blank, the bot starts unbound and the first private `/start` binds that Telegram account as the sole controller
- once `CHAT_ID` is bound, only that chat can issue bot commands
- daily notifications are sent to the bound `CHAT_ID` at the configured `REPORT_TIME` / `REPORT_TZ`

Supported commands:

- `/start`
- `/help`
- `/status`
- `/daily`
- `/quota`
- `/reality_test <domain>`
- `/reality_set <domain>`
- `/tests`
- `/test <name>`
- `/lint_log`
- `/update_repo`
- `/update_log`
- `/test_log`
- `/restart_xray`
- `/reboot`

The bot also installs a `neflare-reality-lint-watch.timer` unit when bot support is enabled. It runs `reality-lint` roughly every 24 hours with a small randomized delay. The watcher records each run in bot state and only sends Telegram notifications when the tracked REALITY policy snapshot changes or the lint command fails.

Docker-backed test notes:

- `/tests` lists the supported disposable checks, but only when `ENABLE_DOCKER_TESTS=yes`.
- `/test <name>` queues a background job, so the bot stays responsive while the test runs.
- The job runs inside a one-shot Docker container, fetches the upstream test script at runtime, and sends the captured result back to Telegram after completion.
- When `ENABLE_DOCKER_TESTS=yes`, the installer installs Docker and configures it for this feature with `host` networking plus Docker firewall management disabled.
- The runtime uses `--rm`, a `none` Docker log driver, explicit labeled-container pruning, and image cleanup when the base image did not already exist on the host.
- Bot-managed JSON logs are pruned automatically by age and size, and only compact metadata is kept locally; the detailed test output is returned to Telegram instead of being stored in full on disk.
- Cleanup is still best-effort for Docker resources created by this feature; it reduces leftover state substantially, but does not claim forensic zero-trace removal from daemon logs or journal history.

Repo sync notes:

- `/update_repo` queues a background root-owned repo sync job and reruns `./install.sh --config /etc/neflare/neflare.env --non-interactive` from the configured checkout.
- The default repo-sync target is this GitHub repository on branch `main` under `/opt/Neflare-Xbot`.
- `/update_log` shows recent repo sync attempts with timestamps, exit codes, and resulting commit ids.

If `BOT_TOKEN` is empty during install, the bot files and units are deployed but the services are not started. After populating `BOT_TOKEN` and optionally `CHAT_ID`, start them with:

```bash
sudo systemctl enable --now neflare-bot neflare-reality-lint-watch.timer
```

Automatic chat binding:

- leave `CHAT_ID` blank during install
- start the bot service
- open a private chat with the bot and send `/start`
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
