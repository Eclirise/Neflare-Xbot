# Agent Notes

## Purpose

This repo provisions Debian 12/13 VPS hosts into Xray VLESS + REALITY servers with hardening, verification, and rollback safety. Treat it as infrastructure code, not a quick installer.

## High-Risk Areas

Changes to the following require strict review and explicit validation:

- `lib/ssh.sh`
- `lib/nftables.sh`
- `lib/ipv6.sh`
- `lib/xray.sh`
- `lib/reality.sh`
- `lib/verify.sh`

Never change those paths casually. Preserve:

- validation before reload/restart
- rollback on failure
- idempotent reruns
- root-only secret permissions
- explicit IPv6 behavior
- separation between repo update and explicit Xray-core upgrade
- no baked-in REALITY camouflage defaults
- policy-aware REALITY warnings for non-443 ports and discouraged targets

## Runtime Layout

The installer copies runtime assets into:

- `/usr/local/lib/neflare`
- `/usr/local/lib/neflare-bot`
- `/usr/local/bin/neflarectl`

System state lives under:

- `/etc/neflare`
- `/var/lib/neflare`
- `/var/lib/neflare-bot`
- `/var/backups/neflare`

Do not assume services run directly from the repo checkout.

## Bot Design

`old-bot.py` is a legacy feature reference only. Do not cargo-cult its architecture.

The current bot design intentionally keeps:

- limited commands
- long polling
- explicit confirmation for dangerous actions
- env-based config
- lightweight JSON state only where needed

Do not reintroduce:

- broad security dashboards
- probe analytics
- whitelist management
- noisy background alerting
- menu sprawl

## Validation Expectations

Before finalizing changes, run at least:

- `bash -n` on shell scripts
- `python -m py_compile` on Python files
- `./install.sh --verify-only` when runtime state exists

If you touch REALITY logic, also run:

- `verify/reality-test.sh <domain>`

If you touch docs, keep README aligned to the actual implemented behavior rather than the original prompt.
