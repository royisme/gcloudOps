# AGENTS.md

Guidance for coding agents (Codex, Claude Code, etc.) working in this repository.

## Repository Goal

This repo provides idempotent host-level and service-level self-healing automation
for VM environments that can be reclaimed/restarted (for example spot/preemptible).

## Architecture

- Host-level self-heal entrypoint: `scripts/host-selfheal.sh`
- Service hook directory: `services-enabled/`
- Service hooks execution order: lexical by file name (`*.sh`)
- Feature flags source: `/etc/hostops/features.env`

## When Asked To Add A Service Self-Heal Script

1. Create hook script in `services-enabled/` using file name:
   - `<NN>-<service>.sh` (example: `20-myapp.sh`)
2. Ensure script is executable.
3. Ensure idempotency (safe to run repeatedly).
4. Avoid secrets in logs or files.
5. Return code contract:
   - `0`: success
   - non-zero: failure
6. Keep scope narrow:
   - health checks
   - minimal repair actions
   - no destructive operations unless explicitly requested

## Preferred Workflow

1. Use scaffold:
   - `bash scripts/new-service-hook.sh --name <service-name> --index <NN>`
2. Fill in service-specific logic in generated file.
3. Validate syntax:
   - `bash -n services-enabled/<NN>-<service>.sh`
   - `bash -n scripts/host-selfheal.sh`
4. Validate runtime on host:
   - `sudo bash /srv/ops/gcloudOps/scripts/host-selfheal.sh`
   - `sudo bash /srv/ops/gcloudOps/scripts/host-features-doctor.sh`

## Guardrails

- Do not remove unrelated files.
- Do not rewrite git history.
- Do not weaken existing checks without explicit instruction.
- Keep README updated when behavior/flags/contracts change.
