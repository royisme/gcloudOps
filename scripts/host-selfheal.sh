#!/usr/bin/env bash
#
# host-selfheal.sh – perform lightweight checks on every boot to ensure
# that the host environment is ready for containerised workloads.  It
# verifies the presence of GPU drivers, Docker and the NVIDIA container
# toolkit, and performs a test run of `nvidia-smi` inside a container.

set -euo pipefail

LOG_FILE="/var/log/svcs/host-selfheal.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"; }
FEATURE_FILE="/etc/hostops/features.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

is_package_installed() {
  local pkg="$1"
  dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -q '^install ok installed$'
}

normalize_bool() {
  local raw="${1:-}"
  local fallback="$2"
  case "${raw,,}" in
    1|true|yes|on) echo "true" ;;
    0|false|no|off|"") echo "false" ;;
    *) echo "$fallback" ;;
  esac
}

load_feature_flags() {
  ENABLE_DOCKER="true"
  ENABLE_GPU="false"
  ENABLE_SERVICE_HOOKS="true"
  SERVICE_HOOKS_DIR="${REPO_ROOT}/services-enabled"
  SERVICE_HOOK_TIMEOUT_SEC="300"
  SERVICE_HOOK_FAIL_MODE="continue"
  if [ -f "$FEATURE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$FEATURE_FILE"
  fi
  ENABLE_DOCKER="$(normalize_bool "${ENABLE_DOCKER:-true}" "true")"
  ENABLE_GPU="$(normalize_bool "${ENABLE_GPU:-false}" "false")"
  ENABLE_SERVICE_HOOKS="$(normalize_bool "${ENABLE_SERVICE_HOOKS:-true}" "true")"
  SERVICE_HOOK_TIMEOUT_SEC="${SERVICE_HOOK_TIMEOUT_SEC:-300}"
  SERVICE_HOOK_FAIL_MODE="${SERVICE_HOOK_FAIL_MODE:-continue}"
}

run_service_hooks() {
  local hooks_dir="$1"
  local timeout_sec="$2"
  local fail_mode="$3"
  local hook
  local rc
  local found=0

  if [ ! -d "$hooks_dir" ]; then
    log "Service hooks directory not found: ${hooks_dir}. Skipping."
    return 0
  fi

  for hook in "$hooks_dir"/*.sh; do
    if [ ! -e "$hook" ]; then
      continue
    fi
    found=1

    if [ ! -x "$hook" ]; then
      log "Service hook is not executable: ${hook}. Skipping."
      continue
    fi

    log "Running service hook: ${hook}"
    if command -v timeout >/dev/null 2>&1; then
      set +e
      timeout "${timeout_sec}" bash "$hook"
      rc=$?
      set -e
    else
      set +e
      bash "$hook"
      rc=$?
      set -e
    fi

    if [ "$rc" -ne 0 ]; then
      log "Service hook failed (rc=${rc}): ${hook}"
      if [ "$fail_mode" = "strict" ]; then
        return 20
      fi
    else
      log "Service hook passed: ${hook}"
    fi
  done

  if [ "$found" -eq 0 ]; then
    log "No service hooks found in ${hooks_dir}."
  fi

  return 0
}

load_feature_flags
log "Starting host self-heal check (ENABLE_DOCKER=${ENABLE_DOCKER}, ENABLE_GPU=${ENABLE_GPU}, ENABLE_SERVICE_HOOKS=${ENABLE_SERVICE_HOOKS})"

# Ensure the host layout has been initialised
if [ ! -f /etc/hostops/layout.conf ]; then
  log "Host layout not initialised.  Run host-layout-init.sh as root."
  exit 1
fi

# Check Docker only when enabled
if [ "$ENABLE_DOCKER" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    log "docker command missing.  Run host-bootstrap.sh to install Docker."
    exit 4
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
  log "Docker service is present"
else
  log "ENABLE_DOCKER=false; skipping Docker checks."
fi

# Check GPU only when enabled
if [ "$ENABLE_GPU" = "true" ]; then
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi missing.  Run host-bootstrap.sh to install the driver."
    exit 2
  fi
  if ! nvidia-smi -L >/dev/null 2>&1; then
    log "nvidia-smi failed; the driver may not be properly loaded."
    exit 3
  fi
  log "Host GPU driver OK"

  if [ "$ENABLE_DOCKER" = "true" ]; then
    if ! is_package_installed "nvidia-container-toolkit"; then
      log "nvidia-container-toolkit not installed.  Run host-bootstrap.sh to install it."
      exit 5
    fi

    set +e
    docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1
    PROBE_RC=$?
    set -e

    if [ $PROBE_RC -ne 0 ]; then
      log "GPU probe inside Docker failed.  Check that the driver and container toolkit are correctly configured."
      exit 6
    fi
  else
    log "ENABLE_GPU=true and ENABLE_DOCKER=false; skipping Docker GPU probe."
  fi
else
  log "ENABLE_GPU=false; skipping GPU checks."
fi

if [ "$ENABLE_SERVICE_HOOKS" = "true" ]; then
  run_service_hooks "${SERVICE_HOOKS_DIR}" "${SERVICE_HOOK_TIMEOUT_SEC}" "${SERVICE_HOOK_FAIL_MODE}"
else
  log "ENABLE_SERVICE_HOOKS=false; skipping service hooks."
fi

log "Host self-heal check passed."
exit 0
