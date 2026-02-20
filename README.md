# gcloudOps

`gcloudOps` is a practical, idempotent host-ops toolkit for GPU VMs on GCP (or similar environments), built for preemptible/spot-style lifecycle events.

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
- Installs GPU/Docker runtime dependencies (only when missing).
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
│   ├── host-bootstrap.sh
│   ├── host-selfheal.sh
│   └── systemd/host-selfheal.service
└── README.md
```

## Execution Flow

1. `install.sh`
- Syncs this repository to `/srv/ops/gcloudOps`.
- Initializes host layout/groups.
- Installs and enables `host-selfheal.service`.

2. `scripts/host-bootstrap.sh`
- Installs GPU driver (if needed).
- Installs Docker + Compose (if needed).
- Installs NVIDIA container toolkit (if needed).
- Performs runtime verification.

3. `scripts/host-selfheal.sh`
- Runs on every boot via systemd.
- Verifies GPU driver, Docker availability, and container GPU probe.

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

# Optional heavy bootstrap (driver/docker/toolkit)
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
- self-heal check passes at boot.

## Validation Commands

```bash
bash -n install.sh
bash -n scripts/host-layout-init.sh
bash -n scripts/host-bootstrap.sh
bash -n scripts/host-selfheal.sh
```

## Operational Highlights (Portfolio-Friendly)

- Production-minded shell automation for host lifecycle management.
- Idempotent provisioning logic for unreliable spot capacity.
- systemd-based self-healing checks for runtime readiness.
- Clear separation of ops/config/data/log responsibilities.

## Notes

- Target platform: Debian/Ubuntu-style Linux hosts.
- Run scripts as root (`sudo`) on VM hosts.
- This repo focuses on host/runtime readiness, not app deployment logic.
