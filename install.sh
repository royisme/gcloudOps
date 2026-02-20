#!/usr/bin/env bash
#
# install.sh – copy the gcloudOps repository into the host layout and set up
# basic services.  This script assumes it is run as root (via sudo) on a
# Debian/Ubuntu based system.  It is idempotent: you can run it multiple
# times on the same host without harmful side effects.

set -euo pipefail

REPO_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="${GCLOUDOPS_REPO_NAME:-gcloudOps}"
DEST_ROOT="/srv/ops/${REPO_NAME}"
INSTALL_MODE="${GCLOUDOPS_INSTALL_MODE:-auto}"   # auto|local|git
GCLOUDOPS_REF="${GCLOUDOPS_REF:-main}"           # branch/tag/commit
GCLOUDOPS_REPO_URL="${GCLOUDOPS_REPO_URL:-}"
GCLOUDOPS_OWNER="${GCLOUDOPS_OWNER:-${SUDO_USER:-}}"
GCLOUDOPS_GROUP="${GCLOUDOPS_GROUP:-}"

log() { echo "[install] $*"; }

resolve_owner_group() {
  local fallback_owner
  local fallback_group

  fallback_owner="$(stat -c '%U' /srv/ops 2>/dev/null || true)"
  fallback_group="$(stat -c '%G' /srv/ops 2>/dev/null || true)"

  if [ -z "$GCLOUDOPS_OWNER" ] || ! id -u "$GCLOUDOPS_OWNER" >/dev/null 2>&1; then
    if [ -n "$fallback_owner" ] && [ "$fallback_owner" != "root" ] && id -u "$fallback_owner" >/dev/null 2>&1; then
      GCLOUDOPS_OWNER="$fallback_owner"
    else
      GCLOUDOPS_OWNER="root"
    fi
  fi

  if [ -z "$GCLOUDOPS_GROUP" ] || ! getent group "$GCLOUDOPS_GROUP" >/dev/null 2>&1; then
    if [ -n "$fallback_group" ] && [ "$fallback_group" != "root" ] && getent group "$fallback_group" >/dev/null 2>&1; then
      GCLOUDOPS_GROUP="$fallback_group"
    else
      GCLOUDOPS_GROUP="$GCLOUDOPS_OWNER"
    fi
  fi
}

run_as_owner() {
  if [ "$GCLOUDOPS_OWNER" = "root" ]; then
    "$@"
    return 0
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$GCLOUDOPS_OWNER" -- "$@"
  else
    sudo -u "$GCLOUDOPS_OWNER" "$@"
  fi
}

resolve_repo_url_from_source() {
  if [ -n "$GCLOUDOPS_REPO_URL" ]; then
    echo "$GCLOUDOPS_REPO_URL"
    return 0
  fi
  if [ -d "${REPO_SRC_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$REPO_SRC_DIR" remote get-url origin 2>/dev/null || true
  fi
}

sync_repo_local() {
  log "Using local sync mode."
  if [ ! -d "$DEST_ROOT" ]; then
    cp -a "$REPO_SRC_DIR" "$DEST_ROOT"
    return 0
  fi

  if [ "$REPO_SRC_DIR" = "$DEST_ROOT" ]; then
    log "Source and destination are the same path; skipping file sync."
    return 0
  fi

  log "Destination ${DEST_ROOT} already exists; syncing repository contents."
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git/' "$REPO_SRC_DIR"/ "$DEST_ROOT"/
  else
    (
      cd "$REPO_SRC_DIR"
      tar --exclude='.git' -cf - .
    ) | (
      cd "$DEST_ROOT"
      tar -xf -
    )
  fi
}

sync_repo_git() {
  local repo_url="$1"
  log "Using git converge mode (ref=${GCLOUDOPS_REF})."

  if ! command -v git >/dev/null 2>&1; then
    log "git is required for GCLOUDOPS_INSTALL_MODE=git."
    exit 1
  fi
  if [ -z "$repo_url" ]; then
    log "Cannot determine repository URL. Set GCLOUDOPS_REPO_URL or run from a git clone with origin."
    exit 1
  fi

  if [ ! -d "$DEST_ROOT" ]; then
    mkdir -p "$(dirname "$DEST_ROOT")"
    if [ "$GCLOUDOPS_OWNER" != "root" ]; then
      install -d -m 2775 -o "$GCLOUDOPS_OWNER" -g "$GCLOUDOPS_GROUP" "$DEST_ROOT"
      run_as_owner git clone "$repo_url" "$DEST_ROOT"
    else
      git clone "$repo_url" "$DEST_ROOT"
    fi
  elif [ ! -d "$DEST_ROOT/.git" ]; then
    log "Destination exists but is not a git repo: ${DEST_ROOT}"
    log "Refusing to overwrite. Move it away or use GCLOUDOPS_INSTALL_MODE=local."
    exit 1
  fi

  run_as_owner git -C "$DEST_ROOT" remote set-url origin "$repo_url"

  if [ -n "$(run_as_owner git -C "$DEST_ROOT" status --porcelain)" ]; then
    log "Destination repo has uncommitted changes: ${DEST_ROOT}"
    log "Refusing auto-update to avoid losing local edits."
    exit 1
  fi

  run_as_owner git -C "$DEST_ROOT" fetch --tags origin
  if run_as_owner git -C "$DEST_ROOT" show-ref --verify --quiet "refs/heads/${GCLOUDOPS_REF}"; then
    run_as_owner git -C "$DEST_ROOT" checkout "${GCLOUDOPS_REF}"
    run_as_owner git -C "$DEST_ROOT" pull --ff-only origin "${GCLOUDOPS_REF}"
  elif run_as_owner git -C "$DEST_ROOT" show-ref --verify --quiet "refs/remotes/origin/${GCLOUDOPS_REF}"; then
    run_as_owner git -C "$DEST_ROOT" checkout -B "${GCLOUDOPS_REF}" "origin/${GCLOUDOPS_REF}"
  elif run_as_owner git -C "$DEST_ROOT" rev-parse --verify --quiet "${GCLOUDOPS_REF}^{commit}" >/dev/null; then
    run_as_owner git -C "$DEST_ROOT" checkout --detach "${GCLOUDOPS_REF}"
  else
    log "Requested ref not found: ${GCLOUDOPS_REF}"
    exit 1
  fi
}

log "Installing ${REPO_NAME} into ${DEST_ROOT}"

# Ensure the parent directory exists
mkdir -p /srv/ops
resolve_owner_group
log "Repository owner/group target: ${GCLOUDOPS_OWNER}:${GCLOUDOPS_GROUP}"

REPO_URL="$(resolve_repo_url_from_source)"
case "$INSTALL_MODE" in
  local)
    sync_repo_local
    ;;
  git)
    sync_repo_git "$REPO_URL"
    ;;
  auto)
    if [ -n "$REPO_URL" ]; then
      sync_repo_git "$REPO_URL"
    else
      sync_repo_local
    fi
    ;;
  *)
    log "Unsupported GCLOUDOPS_INSTALL_MODE=${INSTALL_MODE}. Use auto|local|git."
    exit 1
    ;;
esac

chown -R "${GCLOUDOPS_OWNER}:${GCLOUDOPS_GROUP}" "$DEST_ROOT"

if [ ! -f "$DEST_ROOT/scripts/host-layout-init.sh" ]; then
  log "Missing expected script in destination: $DEST_ROOT/scripts/host-layout-init.sh"
  exit 1
fi

# Run layout initialisation (creates groups and directories)
log "Initialising host directory layout and groups"
bash "$DEST_ROOT/scripts/host-layout-init.sh"

# Install default feature flags if missing
mkdir -p /etc/hostops
if [ ! -f /etc/hostops/features.env ]; then
  install -m 0644 "$DEST_ROOT/scripts/host-features.env.example" /etc/hostops/features.env
  log "Created /etc/hostops/features.env (default: Docker enabled, GPU disabled)"
fi

# Install the systemd unit for the host self‑heal service
log "Installing host self-heal service"
install -m 0644 "$DEST_ROOT/scripts/systemd/host-selfheal.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable host-selfheal.service

log "Installation complete. You can run the bootstrap script to install heavy dependencies:"
echo "    sudo bash ${DEST_ROOT}/scripts/host-bootstrap.sh"
echo "It may reboot the machine, so run it when convenient."
