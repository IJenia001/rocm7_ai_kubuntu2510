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

# Ubuntu 26.04 still ships ROCm 7.1 under the old names (librocm-smi64-7,
# librocm-dbgapi0, rocminfo, rocm-device-libs-21, …). The 7.2.4 packages from
# repo.radeon.com (rocm-core, rocm-opencl) are the same generation. ROCm 10.1
# replaces them with amdrocm-* and does not upgrade those package names, so
# apt leaves the 7.x copies in /usr and /opt/rocm-7.2.4. Remove that stack
# after 10.1 is installed. The pin below stops Ubuntu from putting it back.
#
# 10.1 equivalents:
#   librocm-smi64-7, librocm-smi-dev, rocm-smi -> libamd_smi.so / amd-smi
#   librocm-dbgapi0, amd-dbgapi-dev            -> librocm-dbgapi.so.0.80
#   rocminfo, rocm-core, rocm, rocm-dev        -> /opt/rocm/core-10.1
#   rocm-device-libs-21                        -> core-10.1 device libraries
#   rocm-opencl                                -> amdrocm-opencl10.1

if [[ -d /opt/rocm/core-10.1 ]]; then
  ROCM_PHYS=$(readlink -f /opt/rocm/core-10.1)
  if [[ "$ROCM_PHYS" != "/opt/rocm/core-10.1" ]]; then
    echo "[MOVE] ROCm 10.1 lives inside the old tree ($ROCM_PHYS); moving it aside"
    mv "$ROCM_PHYS" /opt/rocm-core-10.1.reloc
  fi
fi

mapfile -t LEGACY < <(dpkg-query -W -f='${Package}\t${Version}\t${db:Status-Status}\n' \
  | awk -F'\t' '$3=="installed" && $2 ~ /(ubuntu|[.]70204-)/ && $1 ~ /^(rocm($|-)|librocm-|libhip|libhsa|libhsakmt|libmiopen|librocblas|librocfft|librocrand|librocsolver|librocsparse|librocalution|librocprim|librocthrust|libroctx|hipcc$|hip-utils$|hipify-perl$|hip-runtime-amd$|hsa-rocr$|comgr$|rocprofiler-register$|amd-dbgapi-dev$|libamd-comgr|libamdhip64|libhiprtc)/ {print $1}')

if ((${#LEGACY[@]})); then
  echo "[PURGE] Removing ROCm 7.x packages replaced by 10.1:"
  printf '  %s\n' "${LEGACY[@]}"
  apt-get purge -y "${LEGACY[@]}"
fi

if [[ -d /opt/rocm-core-10.1.reloc ]]; then
  if [[ -L /opt/rocm || ! -d /opt/rocm ]]; then
    rm -f /opt/rocm
    mkdir -p /opt/rocm
  fi
  if [[ ! -e /opt/rocm/core-10.1 ]]; then
    mv /opt/rocm-core-10.1.reloc /opt/rocm/core-10.1
  fi
fi

# Drop the old OpenCL ldconfig path left by rocm-opencl 7.2.4.
if [[ -f /etc/ld.so.conf.d/10-rocm-opencl.conf ]] && grep -q 'rocm-7' /etc/ld.so.conf.d/10-rocm-opencl.conf; then
  rm -f /etc/ld.so.conf.d/10-rocm-opencl.conf
fi

cat > /etc/apt/preferences.d/rocm-ubuntu-block <<'EOF'
# Keep Ubuntu's ROCm 7.1 packages from replacing the ROCm 10.1 stack.
Package: rocm rocm-* librocm-* libhip* libhsa-* libhsakmt* libmiopen* librocblas* librocfft* librocrand* librocsolver* librocsparse* librocalution* librocprim* librocthrust* libroctx* hipcc hip-utils hipify-perl hip-runtime-amd hsa-rocr comgr rocprofiler-register amd-dbgapi-dev libamd-comgr* libamdhip64* libhiprtc*
Pin: release o=Ubuntu
Pin-Priority: -1
EOF

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
