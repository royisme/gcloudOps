# gcloudOps

`gcloudOps` is a practical, idempotent host-ops toolkit for VM workloads on GCP (or similar environments), built for preemptible/spot-style lifecycle events.

When a VM is reclaimed but the boot disk persists, these scripts help the next VM instance recover quickly and consistently without manual repair.

## Why This Project Exists

In spot/preemptible setups, host state can drift after repeated stop/recreate cycles:
- runtime packages may be partially configured,
- services may not be enabled,
- host layout may be inconsistent,
- old ops scripts may remain on disk.

This repository focuses on reliable host recovery with repeatable scripts and simple operational controls.

## What It Does

- Initializes a stable host directory and permission layout.
- Installs runtime dependencies (only when missing), with optional GPU support.
- Runs a boot-time self-heal check through systemd.
- Supports safe re-runs after VM reclaim/restart events.

## Core Design Principles

- Idempotent by default: scripts are safe to run multiple times.
- Small blast radius: minimal assumptions and scoped host changes.
- Observable behavior: clear log output and explicit checks.
- Recovery-first: optimized for "disk kept, VM replaced" scenarios.

## Repository Structure

```text
.
├── install.sh
├── scripts
│   ├── host-layout-init.sh
│   ├── host-features.env.example
│   ├── host-bootstrap.sh
│   ├── host-selfheal.sh
│   └── systemd/host-selfheal.service
└── README.md
```

## Feature Flags (Core vs GPU)

`install.sh` creates `/etc/hostops/features.env` on first run (if missing).

Default:
```bash
ENABLE_DOCKER=true
ENABLE_GPU=false
```

Meaning:
- `ENABLE_DOCKER=true`: manage and verify Docker runtime.
- `ENABLE_GPU=true`: install/check NVIDIA stack and run GPU probe.

You can switch modes by editing `/etc/hostops/features.env`.

- Generic Docker app (non-AI): keep `ENABLE_GPU=false`.
- AI/GPU workload: set `ENABLE_GPU=true`, then rerun bootstrap.

Quick diagnostics:
```bash
sudo bash /srv/ops/gcloudOps/scripts/host-features-doctor.sh
```
This prints effective feature flags, key runtime status, and suggested next steps.

## Execution Flow

1. `install.sh`
- Syncs this repository to `/srv/ops/gcloudOps`.
- Initializes host layout/groups.
- Initializes feature flags file (if missing).
- Installs and enables `host-selfheal.service`.

2. `scripts/host-bootstrap.sh`
- Installs Docker + Compose (if `ENABLE_DOCKER=true`).
- Installs GPU driver + NVIDIA toolkit (if `ENABLE_GPU=true`).
- Performs runtime verification.

3. `scripts/host-selfheal.sh`
- Runs on every boot via systemd.
- Verifies only enabled features (Docker/GPU) based on flags.

## Host Layout

| Purpose | Path |
|---|---|
| Ops scripts | `/srv/ops` |
| Work tree | `/srv/work` |
| Config | `/srv/config` |
| Service data | `/var/lib/svcs` |
| Service logs | `/var/log/svcs` |

Unix groups:
- `ops` for operational/config paths
- `svcdata` for runtime data and logs

## Quick Start

```bash
sudo apt-get update -y
sudo apt-get install -y git ca-certificates

tmpdir="$(mktemp -d)"
sudo git clone <REPO_URL> "$tmpdir/gcloudOps"
sudo bash "$tmpdir/gcloudOps/install.sh"

# Optional bootstrap (depends on feature flags)
sudo bash /srv/ops/gcloudOps/scripts/host-bootstrap.sh
```

## Spot/Preemptible Recovery Playbook

After a VM is reclaimed and a new instance boots with the same disk:

```bash
sudo bash /srv/ops/gcloudOps/install.sh
sudo bash /srv/ops/gcloudOps/scripts/host-bootstrap.sh
sudo systemctl status host-selfheal.service
```

Expected outcome:
- layout/groups remain valid,
- missing dependencies are repaired,
- already-correct state is kept unchanged,
- self-heal checks pass according to enabled feature flags.

## Validation Commands

```bash
bash -n install.sh
bash -n scripts/host-layout-init.sh
bash -n scripts/host-bootstrap.sh
bash -n scripts/host-selfheal.sh
```

## Changelog

### 2026-02-20

- Added idempotent repo sync behavior in `install.sh` when `/srv/ops/gcloudOps` already exists.
- Hardened bootstrap repository/keyring writes to be safe on repeated runs.
- Fixed NVIDIA toolkit detection using `dpkg-query` (removed false negatives from regex mismatch).
- Introduced feature flags for generic vs GPU hosts:
  - `ENABLE_DOCKER=true`
  - `ENABLE_GPU=false` (default)
- Added `scripts/host-features.env.example` and auto-initialize `/etc/hostops/features.env` on install.
- Updated `host-bootstrap.sh` and `host-selfheal.sh` to execute checks by enabled features only.
- Added `scripts/host-features-doctor.sh` for quick on-host diagnostics and next-step hints.
- Completed live validation on VM `instance-20260220-062618`:
  - Generic mode (`ENABLE_GPU=false`) self-heal passes.
  - GPU mode (`ENABLE_GPU=true`) bootstrap + self-heal pass.

## Operational Highlights (Portfolio-Friendly)

- Production-minded shell automation for host lifecycle management.
- Idempotent provisioning logic for unreliable spot capacity.
- systemd-based self-healing checks for runtime readiness.
- Clear separation of ops/config/data/log responsibilities.

## Notes

- Target platform: Debian/Ubuntu-style Linux hosts.
- Run scripts as root (`sudo`) on VM hosts.
- This repo focuses on host/runtime readiness, not app deployment logic.
