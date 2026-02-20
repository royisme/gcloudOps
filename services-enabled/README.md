# Service Hooks

Place service-specific self-heal scripts in this directory to make them part of
the host self-heal flow.

## Contract

- File name: `*.sh`
- Must be executable: `chmod +x your-hook.sh`
- Must be idempotent (safe to run multiple times)
- Exit code:
  - `0`: success
  - non-zero: failure

## Execution

`scripts/host-selfheal.sh` runs hooks in lexical file name order.

Defaults:
- `ENABLE_SERVICE_HOOKS=true`
- `SERVICE_HOOKS_DIR=/srv/ops/gcloudOps/services-enabled`
- `SERVICE_HOOK_TIMEOUT_SEC=300`
- `SERVICE_HOOK_FAIL_MODE=continue` (`strict` to fail whole self-heal)

## Example

```bash
#!/usr/bin/env bash
set -euo pipefail

# Ensure app service is enabled and running.
systemctl enable --now myapp.service
```
