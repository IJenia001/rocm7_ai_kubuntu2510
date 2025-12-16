#!/usr/bin/env bash
# ROCm 7+ installer for Kubuntu 25.10
# Target: AMD GPU (RDNA2/RDNA3/RDNA4), kernel amdgpu
# Run as root: sudo bash rocm7_kubuntu_25.10.sh

set -e

ROCM_VERSION="7.0"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"; exit 1
fi

echo "[1/7] Base system update"
apt update && apt -y full-upgrade

echo "[2/7] Base dependencies"
apt install -y wget curl gnupg2 software-properties-common dkms pciutils lsb-release

echo "[3/7] AMD ROCm repository"
mkdir -p /etc/apt/keyrings
wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor > /etc/apt/keyrings/rocm.gpg

# ROCm officially supports Ubuntu 22.04 (jammy) and 24.04 (noble)
# For Kubuntu 25.10 (questing) we must pin to noble to avoid dependency breakage
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION}/ noble main" > /etc/apt/sources.list.d/rocm.list

cat <<EOF >/etc/apt/preferences.d/rocm-pin
Package: *
Pin: release n=noble
Pin-Priority: 1001
EOF

apt update

echo "[4/7] Kernel & firmware checks"
apt install -y linux-firmware

modprobe amdgpu || true

if ! lsmod | grep -q amdgpu; then
  echo "amdgpu not loaded – check kernel compatibility"; exit 1
fi

echo "[5/7] ROCm core installation"
# Install minimal working ROCm stack first, then expand
# Handle packages held on the system: record, temporarily unhold, install, then reapply holds
HELD_PKGS=$(apt-mark showhold)
REAPPLY_HOLDS=0
if [ -n "$HELD_PKGS" ]; then
  echo "Detected held packages: $HELD_PKGS"
  echo "Temporarily unholding them to allow ROCm packages to install..."
  apt-mark unhold $HELD_PKGS || true
  REAPPLY_HOLDS=1
fi

# Install core ROCm components
apt install -y rocm-core rocminfo rocm-smi || {
  echo "apt failed; trying with --allow-change-held-packages"
  apt install -y --allow-change-held-packages rocm-core rocminfo rocm-smi || exit 1
}

# Reapply original holds if any
if [ "$REAPPLY_HOLDS" -eq 1 ] && [ -n "$HELD_PKGS" ]; then
  echo "Reapplying holds on: $HELD_PKGS"
  apt-mark hold $HELD_PKGS || true
fi

# Optional full stack (may be heavy)
apt install -y rocm-dev rocm-libs rocm-llvm rocm-utils || echo "Full ROCm stack not fully available on questing; core installed"

echo "[6/7] User permissions"
USER_NAME=${SUDO_USER:-$USER}
usermod -aG video,render $USER_NAME

cat <<EOF >/etc/profile.d/rocm.sh
export ROCM_PATH=/opt/rocm
export PATH=\$PATH:/opt/rocm/bin
export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64
EOF

echo "[7/7] Validation"
/opt/rocm/bin/rocminfo || true
/opt/rocm/opencl/bin/clinfo || true

echo "ROCm ${ROCM_VERSION}+ installation finished"
echo "Reboot required"
