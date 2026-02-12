#!/usr/bin/env bash
set -euo pipefail

# ROCm 7.x installer for Kubuntu 25.10 (FIXED noble-only)
# v4.1 hotfix: remove invalid codenames, force noble, auto-clean old repos

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"; exit 1
fi

echo "[FIX] Removing invalid ROCm repo entries (oracular/questing)"
rm -f /etc/apt/sources.list.d/rocm*.list || true
rm -f /etc/apt/sources.list.d/amdgpu*.list || true

CODENAME="noble"
ROCM_VER="7.2"
KEYRING="/usr/share/keyrings/rocm.gpg"
LIST="/etc/apt/sources.list.d/rocm.list"

apt update
apt install -y curl wget gnupg ca-certificates software-properties-common

if [[ ! -f "$KEYRING" ]]; then
  echo "[KEY] Installing ROCm GPG key"
  curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o "$KEYRING"
fi

cat > "$LIST" <<EOF
deb [arch=amd64 signed-by=$KEYRING] https://repo.radeon.com/rocm/apt/$ROCM_VER $CODENAME main
EOF

apt update

# Handle held packages safely
HELD=$(apt-mark showhold || true)
if [[ -n "$HELD" ]]; then
  echo "[HOLD] Temporarily unholding: $HELD"
  apt-mark unhold $HELD || true
fi

apt install -y rocm-core rocminfo rocm-smi rocm-opencl hip-runtime-amd

if [[ -n "$HELD" ]]; then
  echo "[HOLD] Restoring holds"
  apt-mark hold $HELD || true
fi

# Groups
for g in video render; do
  getent group $g >/dev/null || groupadd $g
  usermod -aG $g ${SUDO_USER:-root}
done

# Environment
cat >/etc/profile.d/rocm.sh <<'EOF'
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:$LD_LIBRARY_PATH
export HSA_OVERRIDE_GFX_VERSION=12.0.0
EOF

chmod +x /etc/profile.d/rocm.sh

echo "[OK] ROCm base installed (noble repo)"
echo "Reboot recommended"
