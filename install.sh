#!/usr/bin/env bash
#
# install.sh – copy the gcloudOps repository into the host layout and set up
# basic services.  This script assumes it is run as root (via sudo) on a
# Debian/Ubuntu based system.  It is idempotent: you can run it multiple
# times on the same host without harmful side effects.

set -euo pipefail

REPO_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$REPO_SRC_DIR")"
DEST_ROOT="/srv/ops/${REPO_NAME}"

echo "[install] Installing ${REPO_NAME} into ${DEST_ROOT}"

# Ensure the parent directory exists
mkdir -p /srv/ops

# Copy or sync repository contents
if [ ! -d "$DEST_ROOT" ]; then
  cp -a "$REPO_SRC_DIR" "$DEST_ROOT"
else
  echo "[install] Destination ${DEST_ROOT} already exists; syncing repository contents."
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git/' "$REPO_SRC_DIR"/ "$DEST_ROOT"/
  else
    # Fallback for minimal environments without rsync.
    (
      cd "$REPO_SRC_DIR"
      tar --exclude='.git' -cf - .
    ) | (
      cd "$DEST_ROOT"
      tar -xf -
    )
  fi
fi

# Run layout initialisation (creates groups and directories)
echo "[install] Initialising host directory layout and groups"
bash "$DEST_ROOT/scripts/host-layout-init.sh"

# Install default feature flags if missing
mkdir -p /etc/hostops
if [ ! -f /etc/hostops/features.env ]; then
  install -m 0644 "$DEST_ROOT/scripts/host-features.env.example" /etc/hostops/features.env
  echo "[install] Created /etc/hostops/features.env (default: Docker enabled, GPU disabled)"
fi

# Install the systemd unit for the host self‑heal service
echo "[install] Installing host self‑heal service"
install -m 0644 "$DEST_ROOT/scripts/systemd/host-selfheal.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable host-selfheal.service

echo "[install] Installation complete.  You can run the bootstrap script to install heavy dependencies:"
echo "    sudo bash ${DEST_ROOT}/scripts/host-bootstrap.sh"
echo "It may reboot the machine, so run it when convenient."
