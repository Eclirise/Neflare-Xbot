# NeFlare Xray REALITY Provisioning Repo

NeFlare provisions a fresh Debian 12 or Debian 13 VPS into a production-minded Xray VLESS + REALITY server with a default public listener on TCP/RAW 443 and:

- hardened SSH on one persisted high port
- nftables default-drop inbound firewall
- mainland-China SSH geo-blocking via APNIC delegated data
- optional Telegram bot management
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
- The CN SSH geo-block updater uses HTTPS transport, strict APNIC parsing, nftables validation, atomic replacement, and last-known-good rollback. It does not claim cryptographic source attestation beyond that.
- IPv6 is an explicit installer choice. If enabled, nftables applies explicit IPv6 policy and SSH CN geo-blocking when IPv6 CN ranges are available. If disabled, the installer applies sysctl-based IPv6 disablement and reports that state clearly.
- The installer does not ship a baked-in REALITY camouflage target list. You must provide candidate domains. Auto-recommendation means selecting the least risky acceptable candidate from your supplied set after transparent scoring and policy linting.
- The first interactive installer prompt is the UI language selector (`English` or `中文`). The chosen language is persisted as `UI_LANG` and reused by installer summaries and bot status/report output.
- REALITY candidate input is mandatory and must contain at least 2 distinct domains. The installer tests the supplied set and picks the best acceptable option unless you override it.
- Apple/iCloud-related or tutorial-like camouflage patterns are discouraged operationally and are flagged explicitly rather than treated as good defaults.

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
17. optionally deploy the Telegram bot
18. run verification and print summary plus client YAML

## Configuration

Use `templates/neflare.env.example` as a starting point.

Important keys:

- `ADMIN_USER`
- `ADMIN_PUBLIC_KEY`
- `UI_LANG`
- `SSH_PORT`
- `ENABLE_IPV6`
- `ENABLE_BOT`
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

Explicit Xray-core upgrade:

```bash
sudo ./install.sh --upgrade-xray
```

This is intentionally separate from routine repo updates.

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
sudo neflarectl print-policy
sudo neflarectl print-client
sudo neflarectl quota
sudo neflarectl quota-set 120 380 2026-05-01T00:00:00Z
sudo neflarectl quota-clear
```

## Telegram Bot

The bot is optional and uses long polling for simplicity and reliability on small VPS deployments.

Supported commands:

- `/start`
- `/help`
- `/status`
- `/daily`
- `/quota`
- `/reality_test <domain>`
- `/reality_set <domain>`
- `/restart_xray`
- `/reboot`

If `BOT_TOKEN` is empty during install, the bot files and unit are deployed but the service is not started. After populating `BOT_TOKEN` and optionally `CHAT_ID`, start it with:

```bash
sudo systemctl enable --now neflare-bot
```

Deferred chat binding:

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

Rollback coverage includes:

- SSH drop-in changes
- sudoers drop-in for the admin user
- nftables main config and CN set file
- IPv6 and BBR sysctl files
- Xray config and service override
- bot env and unit files

## Uninstall

Conservative cleanup without touching live network state:

```bash
sudo ./uninstall.sh
```

Cleanup plus network restore:

```bash
sudo ./uninstall.sh --restore-network
```

Cleanup plus local Xray purge:

```bash
sudo ./uninstall.sh --purge-xray
```

## Cloud Firewall Guidance

The installer prints this again at the end, but the required provider-panel rules are:

- inbound default drop
- outbound default accept
- allow TCP/`XRAY_LISTEN_PORT` from anywhere
- allow TCP/`SSH_PORT` from your admin source(s)

## Limitations

- CN SSH geo-blocking is allocation-based from APNIC delegated data, not commercial geolocation intelligence.
- REALITY candidate scoring and policy linting are heuristic. Re-test candidates before and after major routing, provider, or target-site changes.
- The repo intentionally prefers conservative defaults over popular copy-paste community patterns.
- If the installer keeps a temporary admin allow entry for migration safety, that host is not yet in the strict final SSH geo-block posture until you remove it.


## Fresh VPS Commands

HTTPS clone example:
```bash
sudo apt-get update && sudo apt-get install -y git ca-certificates
git clone --branch <YOUR_BRANCH> <YOUR_REPO_URL> neflare-xbot
cd neflare-xbot
chmod +x install.sh
sudo ./install.sh
```
SSH clone example:

```bash
sudo apt-get update && sudo apt-get install -y git ca-certificates
git clone --branch <YOUR_BRANCH> <YOUR_REPO_URL> neflare-xbot
cd neflare-xbot
chmod +x install.sh
sudo ./install.sh
```
