#!/usr/bin/env bash
#
# host-bootstrap.sh – perform heavy initialisation of a fresh VM: install GPU
# drivers, Docker, and the NVIDIA container toolkit.  This script should
# only be run as root when those components are absent.  It may cause the
# machine to reboot.

set -euo pipefail

log() { echo "[host-bootstrap] $*"; }

ensure_dearmored_keyring() {
  local key_url="$1"
  local keyring_path="$2"
  local tmp_keyring

  tmp_keyring="$(mktemp)"
  curl -fsSL "$key_url" | gpg --dearmor > "$tmp_keyring"
  install -m 0644 "$tmp_keyring" "$keyring_path"
  rm -f "$tmp_keyring"
}

write_if_changed() {
  local target="$1"
  local content="$2"
  local tmp

  tmp="$(mktemp)"
  printf '%s\n' "$content" > "$tmp"
  if [ ! -f "$target" ] || ! cmp -s "$tmp" "$target"; then
    install -m 0644 "$tmp" "$target"
  fi
  rm -f "$tmp"
}

log "Updating package index and installing base tools"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https python3 git

# Detect OS codename
. /etc/os-release
CODENAME="${VERSION_CODENAME:-$(lsb_release -cs || true)}"

## 1. GPU driver installation (only if missing)
if ! command -v nvidia-smi >/dev/null 2>&1; then
  log "nvidia-smi not found; installing NVIDIA driver (binary/prod)"
  mkdir -p /opt/google/cuda-installer
  cd /opt/google/cuda-installer
  if [ ! -f cuda_installer.pyz ]; then
    curl -fsSL "https://storage.googleapis.com/compute-gpu-installation-us/installer/latest/cuda_installer.pyz" -o cuda_installer.pyz
  fi
  # Running the installer may trigger a reboot.  If a reboot happens, re-run this script afterwards.
  python3 cuda_installer.pyz install_driver --installation-mode=binary --installation-branch=prod || true
  log "If the installer requested a reboot, please reboot now and re-run this script."
else
  log "NVIDIA driver already installed.  Skipping driver installation."
fi

## 2. Docker and compose installation (only if missing)
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found; installing Docker Engine and Compose"
  install -m 0755 -d /etc/apt/keyrings
  ensure_dearmored_keyring "https://download.docker.com/linux/debian/gpg" "/etc/apt/keyrings/docker.gpg"
  write_if_changed "/etc/apt/sources.list.d/docker.list" \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable"
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
else
  log "Docker already installed; ensuring service is enabled"
  systemctl enable --now docker
fi

## 3. NVIDIA container toolkit (only if missing)
if ! dpkg -l 2>/dev/null | grep -qE '^ii\s+nvidia-container-toolkit\s'; then
  log "Installing NVIDIA container toolkit"
  install -m 0755 -d /etc/apt/keyrings
  ensure_dearmored_keyring "https://nvidia.github.io/libnvidia-container/gpgkey" "/etc/apt/keyrings/nvidia-container-toolkit.gpg"
  NVIDIA_REPO_LINE="$(
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g'
  )"
  write_if_changed "/etc/apt/sources.list.d/nvidia-container-toolkit.list" "$NVIDIA_REPO_LINE"
  apt-get update -y
  apt-get install -y nvidia-container-toolkit
  if command -v nvidia-ctk >/dev/null 2>&1; then
    nvidia-ctk runtime configure --runtime=docker || true
    systemctl restart docker
  fi
else
  log "NVIDIA container toolkit already installed."
fi

## 4. Verification steps
if command -v nvidia-smi >/dev/null 2>&1; then
  log "Verifying host GPU driver"
  nvidia-smi || true
fi

log "Verifying Docker access to GPU"
if command -v docker >/dev/null 2>&1; then
  set +e
  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1
  RC=$?
  set -e
  if [ $RC -eq 0 ]; then
    log "Docker GPU probe successful."
  else
    log "Docker GPU probe failed.  Please ensure the driver and container toolkit are correctly installed."
  fi
fi

log "Bootstrap completed.  If you installed the driver, a reboot may be required."
