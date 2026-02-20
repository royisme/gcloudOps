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
  if [ -f "$FEATURE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$FEATURE_FILE"
  fi
  ENABLE_DOCKER="$(normalize_bool "${ENABLE_DOCKER:-true}" "true")"
  ENABLE_GPU="$(normalize_bool "${ENABLE_GPU:-false}" "false")"
}

load_feature_flags
log "Starting host self-heal check (ENABLE_DOCKER=${ENABLE_DOCKER}, ENABLE_GPU=${ENABLE_GPU})"

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

log "Host self-heal check passed."
exit 0
