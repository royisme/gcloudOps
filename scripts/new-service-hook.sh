#!/usr/bin/env bash
#
# new-service-hook.sh – scaffold a service self-heal hook script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOOKS_DIR="${REPO_ROOT}/services-enabled"
INDEX="50"
NAME=""
FORCE="false"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/new-service-hook.sh --name <service-name> [--index <NN>] [--hooks-dir <path>] [--force]

Options:
  --name       Required. Hook/service name (example: myapp, redis-cache).
  --index      Optional. Lexical order prefix, default: 50.
  --hooks-dir  Optional. Target directory, default: ./services-enabled.
  --force      Optional. Overwrite existing file.

Examples:
  bash scripts/new-service-hook.sh --name myapp
  bash scripts/new-service-hook.sh --name redis-cache --index 20
  bash scripts/new-service-hook.sh --name api --hooks-dir /srv/ops/gcloudOps/services-enabled
EOF
}

sanitize_name() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --index)
      INDEX="${2:-}"
      shift 2
      ;;
    --hooks-dir)
      HOOKS_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "--name is required." >&2
  usage
  exit 1
fi

if ! echo "$INDEX" | grep -Eq '^[0-9]{2,3}$'; then
  echo "--index must be a 2-3 digit number (for example: 10, 50, 120)." >&2
  exit 1
fi

SAFE_NAME="$(sanitize_name "$NAME")"
if [ -z "$SAFE_NAME" ]; then
  echo "Invalid --name after sanitization." >&2
  exit 1
fi

mkdir -p "$HOOKS_DIR"
HOOK_PATH="${HOOKS_DIR}/${INDEX}-${SAFE_NAME}.sh"

if [ -f "$HOOK_PATH" ] && [ "$FORCE" != "true" ]; then
  echo "Hook already exists: ${HOOK_PATH}" >&2
  echo "Use --force to overwrite." >&2
  exit 1
fi

cat > "$HOOK_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

log() { echo "[service-hook:${SAFE_NAME}] \$*"; }

# This hook is executed by scripts/host-selfheal.sh.
# Requirements:
# 1) Keep this script idempotent.
# 2) Do not print or store secrets.
# 3) Return 0 on success; non-zero on failure.

log "Starting self-heal checks"

# TODO: Replace with real checks/repair steps for your service.
# Example:
# systemctl enable --now ${SAFE_NAME}.service
# systemctl is-active --quiet ${SAFE_NAME}.service

log "Self-heal checks completed"
exit 0
EOF

chmod +x "$HOOK_PATH"

echo "Created hook: ${HOOK_PATH}"
echo "Next steps:"
echo "1) Implement your service-specific checks/repairs."
echo "2) Test: sudo bash /srv/ops/gcloudOps/scripts/host-selfheal.sh"
echo "3) Diagnose: sudo bash /srv/ops/gcloudOps/scripts/host-features-doctor.sh"
