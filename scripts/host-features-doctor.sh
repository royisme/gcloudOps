#!/usr/bin/env bash
#
# host-features-doctor.sh – print effective feature flags and runtime readiness
# hints for quick operational diagnostics.

set -euo pipefail

FEATURE_FILE="/etc/hostops/features.env"
DEFAULT_ENABLE_DOCKER="true"
DEFAULT_ENABLE_GPU="false"
DEFAULT_ENABLE_SERVICE_HOOKS="true"
DEFAULT_SERVICE_HOOKS_DIR="/srv/ops/gcloudOps/services-enabled"
DEFAULT_SERVICE_HOOK_TIMEOUT_SEC="300"
DEFAULT_SERVICE_HOOK_FAIL_MODE="continue"

normalize_bool() {
  local raw="${1:-}"
  local fallback="$2"
  case "${raw,,}" in
    1|true|yes|on) echo "true" ;;
    0|false|no|off|"") echo "false" ;;
    *) echo "$fallback" ;;
  esac
}

print_kv() {
  local key="$1"
  local value="$2"
  printf '%-28s %s\n' "${key}:" "${value}"
}

ENABLE_DOCKER_RAW="$DEFAULT_ENABLE_DOCKER"
ENABLE_GPU_RAW="$DEFAULT_ENABLE_GPU"
ENABLE_SERVICE_HOOKS_RAW="$DEFAULT_ENABLE_SERVICE_HOOKS"
SERVICE_HOOKS_DIR_RAW="$DEFAULT_SERVICE_HOOKS_DIR"
SERVICE_HOOK_TIMEOUT_SEC_RAW="$DEFAULT_SERVICE_HOOK_TIMEOUT_SEC"
SERVICE_HOOK_FAIL_MODE_RAW="$DEFAULT_SERVICE_HOOK_FAIL_MODE"

if [ -f "$FEATURE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$FEATURE_FILE"
fi

ENABLE_DOCKER_EFFECTIVE="$(normalize_bool "${ENABLE_DOCKER:-$ENABLE_DOCKER_RAW}" "$DEFAULT_ENABLE_DOCKER")"
ENABLE_GPU_EFFECTIVE="$(normalize_bool "${ENABLE_GPU:-$ENABLE_GPU_RAW}" "$DEFAULT_ENABLE_GPU")"
ENABLE_SERVICE_HOOKS_EFFECTIVE="$(normalize_bool "${ENABLE_SERVICE_HOOKS:-$ENABLE_SERVICE_HOOKS_RAW}" "$DEFAULT_ENABLE_SERVICE_HOOKS")"
SERVICE_HOOKS_DIR_EFFECTIVE="${SERVICE_HOOKS_DIR:-$SERVICE_HOOKS_DIR_RAW}"
SERVICE_HOOK_TIMEOUT_SEC_EFFECTIVE="${SERVICE_HOOK_TIMEOUT_SEC:-$SERVICE_HOOK_TIMEOUT_SEC_RAW}"
SERVICE_HOOK_FAIL_MODE_EFFECTIVE="${SERVICE_HOOK_FAIL_MODE:-$SERVICE_HOOK_FAIL_MODE_RAW}"

echo "== gcloudOps Feature Doctor =="
print_kv "Feature file" "$FEATURE_FILE"
print_kv "Feature file exists" "$([ -f "$FEATURE_FILE" ] && echo yes || echo no)"
print_kv "ENABLE_DOCKER (effective)" "$ENABLE_DOCKER_EFFECTIVE"
print_kv "ENABLE_GPU (effective)" "$ENABLE_GPU_EFFECTIVE"
print_kv "ENABLE_SERVICE_HOOKS (effective)" "$ENABLE_SERVICE_HOOKS_EFFECTIVE"
print_kv "SERVICE_HOOKS_DIR" "$SERVICE_HOOKS_DIR_EFFECTIVE"
print_kv "SERVICE_HOOK_TIMEOUT_SEC" "$SERVICE_HOOK_TIMEOUT_SEC_EFFECTIVE"
print_kv "SERVICE_HOOK_FAIL_MODE" "$SERVICE_HOOK_FAIL_MODE_EFFECTIVE"
echo

echo "== Runtime Checks =="
if command -v docker >/dev/null 2>&1; then
  print_kv "docker command" "present"
  if docker info >/dev/null 2>&1; then
    print_kv "docker daemon" "reachable"
  else
    print_kv "docker daemon" "not reachable"
  fi
else
  print_kv "docker command" "missing"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi -L >/dev/null 2>&1; then
    print_kv "nvidia driver" "ready"
  else
    print_kv "nvidia driver" "installed but not ready"
  fi
else
  print_kv "nvidia driver" "missing"
fi

if dpkg-query -W -f='${Status}\n' nvidia-container-toolkit 2>/dev/null | grep -q '^install ok installed$'; then
  print_kv "nvidia-container-toolkit" "installed"
else
  print_kv "nvidia-container-toolkit" "not installed"
fi

if [ "$ENABLE_SERVICE_HOOKS_EFFECTIVE" = "true" ]; then
  if [ -d "$SERVICE_HOOKS_DIR_EFFECTIVE" ]; then
    HOOK_COUNT="$(find "$SERVICE_HOOKS_DIR_EFFECTIVE" -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')"
    print_kv "service hooks directory" "present"
    print_kv "service hooks (*.sh)" "$HOOK_COUNT"
  else
    print_kv "service hooks directory" "missing"
  fi
else
  print_kv "service hooks" "disabled"
fi
echo

echo "== Suggested Next Step =="
if [ "$ENABLE_DOCKER_EFFECTIVE" = "false" ] && [ "$ENABLE_GPU_EFFECTIVE" = "false" ]; then
  echo "- Minimal mode enabled. Run only layout/service checks as needed."
elif [ "$ENABLE_DOCKER_EFFECTIVE" = "true" ] && [ "$ENABLE_GPU_EFFECTIVE" = "false" ]; then
  echo "- Generic Docker mode. Ensure Docker daemon is reachable."
  echo "  Command: sudo bash /srv/ops/gcloudOps/scripts/host-selfheal.sh"
elif [ "$ENABLE_DOCKER_EFFECTIVE" = "true" ] && [ "$ENABLE_GPU_EFFECTIVE" = "true" ]; then
  echo "- GPU mode. Validate driver/toolkit and Docker GPU probe."
  echo "  Command: sudo bash /srv/ops/gcloudOps/scripts/host-bootstrap.sh"
  echo "  Command: sudo bash /srv/ops/gcloudOps/scripts/host-selfheal.sh"
else
  echo "- ENABLE_GPU=true with ENABLE_DOCKER=false is unusual."
  echo "  Consider setting ENABLE_DOCKER=true unless you use host-only GPU workloads."
fi
