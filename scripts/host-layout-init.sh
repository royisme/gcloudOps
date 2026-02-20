#!/usr/bin/env bash
#
# host-layout-init.sh – create the standard directory layout and groups
# used by gcloudOps.  This script can be run multiple times without
# adverse effects.  It should be run as root.

set -euo pipefail

# Groups for operational files and service data
OPS_GRP="ops"
SVC_GRP="svcdata"

# Current user (for group membership)
CURRENT_USER="${SUDO_USER:-${USER}}"

echo "[layout-init] Creating groups if missing"
if ! getent group "$OPS_GRP" >/dev/null 2>&1; then
  groupadd "$OPS_GRP"
fi
if ! getent group "$SVC_GRP" >/dev/null 2>&1; then
  groupadd "$SVC_GRP"
fi

# Add the current user to the groups
usermod -aG "$OPS_GRP" "$CURRENT_USER" || true
usermod -aG "$SVC_GRP" "$CURRENT_USER" || true

echo "[layout-init] Creating directory structure"
install -d -m 2775 -o root -g "$OPS_GRP" /srv/ops
install -d -m 2775 -o root -g "$OPS_GRP" /srv/work
install -d -m 2775 -o root -g "$OPS_GRP" /srv/config
install -d -m 2775 -o root -g "$SVC_GRP" /var/lib/svcs
install -d -m 2775 -o root -g "$SVC_GRP" /var/log/svcs

echo "[layout-init] Marking layout initialisation"
mkdir -p /etc/hostops
if [ ! -f /etc/hostops/layout.conf ]; then
  echo "initialized=$(date -Is)" > /etc/hostops/layout.conf
fi

echo "[layout-init] Layout initialisation complete.  You may need to log out and log back in for group changes to take effect."