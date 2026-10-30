#!/usr/bin/env bash
set -euo pipefail

# ROCm installer for Kubuntu 26.04
# Installs the current stable ROCm (10.1) full SDK: runtimes, compilers,
# math/ML libraries (BLAS, FFT, RAND, solver, sparse, MIOpen, RCCL, …),
# OpenCL, developer tools, and the HPC libraries (rocALUTION, hipTensor)
# for every supported GPU architecture.

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[FIX] Removing old ROCm / amdgpu apt entries"
rm -f /etc/apt/sources.list.d/rocm*.list \
      /etc/apt/sources.list.d/amdgpu*.list \
      /etc/apt/sources.list.d/rocm*.sources \
      /etc/apt/sources.list.d/amdgpu*.sources || true

KEYRING_DIR="/etc/apt/keyrings"
KEYRING="${KEYRING_DIR}/amdrocm.gpg"
LIST="/etc/apt/sources.list.d/amdrocm-stable.sources"
REPO="https://stable.repo.amd.com/rocm/core/packages/ubuntu2604/"
ROCM_ROOT="/opt/rocm/core-10.1"

. /etc/os-release
case "${VERSION_ID:-}" in
  26.04*) ;;
  *)
    echo "This script targets Kubuntu/Ubuntu 26.04 (found: ${PRETTY_NAME:-unknown})"
    exit 1
    ;;
esac

apt update
apt install -y curl wget gnupg ca-certificates

install -d -m 0755 "$KEYRING_DIR"
echo "[KEY] Installing ROCm GPG key"
curl -fsSL https://stable.repo.amd.com/rocm/gpg/packages.gpg \
  | gpg --dearmor --yes -o "$KEYRING"
chmod 0644 "$KEYRING"

cat > "$LIST" <<EOF
X-Repo-Id: amdrocm-stable
Types: deb
URIs: ${REPO}
Suites: stable
Components: main
Architectures: amd64
Signed-By: ${KEYRING}
Enabled: yes
EOF

apt update

HELD=$(apt-mark showhold || true)
if [[ -n "$HELD" ]]; then
  echo "[HOLD] Temporarily unholding: $HELD"
  apt-mark unhold $HELD || true
fi

# Full suite for all GPU architectures, plus HPC libraries not in the core SDK.
apt install -y \
  amdrocm-core-sdk10.1 \
  amdrocm-hpc-sdk10.1 \
  amdrocm-hipify10.1

if [[ -n "$HELD" ]]; then
  echo "[HOLD] Restoring holds"
  apt-mark hold $HELD || true
fi

if [[ ! -x "${ROCM_ROOT}/bin/rocminfo" ]]; then
  echo "ROCm was installed, but ${ROCM_ROOT}/bin/rocminfo is missing"
  exit 1
fi

echo "${ROCM_ROOT}/lib" > /etc/ld.so.conf.d/rocm.conf
ldconfig

for g in video render; do
  getent group "$g" >/dev/null || groupadd "$g"
  usermod -aG "$g" "${SUDO_USER:-root}"
done

cat >/etc/profile.d/rocm.sh <<EOF
export ROCM_PATH=${ROCM_ROOT}
export HIP_PATH=${ROCM_ROOT}
export PATH=\${ROCM_PATH}/bin:\${PATH}
export LD_LIBRARY_PATH=\${ROCM_PATH}/lib:\${LD_LIBRARY_PATH:-}
export HSA_OVERRIDE_GFX_VERSION=12.0.0
EOF
chmod 0644 /etc/profile.d/rocm.sh

echo "[OK] ROCm 10.1 full SDK installed from ${REPO}"
echo "Prefix: ${ROCM_ROOT}"
echo "Open a new shell (or reboot) so PATH and the video/render groups apply."
