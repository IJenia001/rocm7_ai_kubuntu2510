#!/bin/bash
set -euo pipefail

echo "=== START: ROCm 7.0 + AI setup ==="

# --- 1. Обновление системы ---
echo "[INFO] Updating system..."
sudo apt update && sudo apt dist-upgrade -y
sudo apt install -y wget curl python3 python3-pip python3-venv python3-setuptools python3-wheel dkms cmake git clang

# --- 2. Скачиваем актуальный amdgpu-install 7.0.70000 ---
echo "[INFO] Downloading amdgpu-install 7.0.70000..."
cd /tmp
wget https://repo.radeon.com/amdgpu-install/7.1/ubuntu/noble/amdgpu-install_7.1.70100-1_all.deb
sudo apt install -y ./amdgpu-install_7.1.70100-1_all.deb

# --- 3. Обновляем apt и устанавливаем ROCm ---
echo "[INFO] Updating apt and installing ROCm..."
sudo apt update
sudo apt install -y rocm

# --- 4. Добавляем текущего пользователя в группы render, video ---
echo "[INFO] Adding user to render and video groups..."
sudo usermod -aG render,video $LOGNAME

# --- 5. Настройка драйвера amdgpu для AI/ACCEL ---
echo "[INFO] Configuring amdgpu driver..."
sudo bash -c 'cat >/etc/modprobe.d/amdgpu-ai.conf <<EOF
options amdgpu enable_mes=1
options amdgpu gpu_recovery=1
options amdgpu navi21_enable_pcie_gen=0xff
options amdgpu enable_ai=1
options amdgpu enable_accel=1
options amdgpu sg_display=1
EOF'

# --- 6. Переменные окружения FSR4 ML ---
echo "[INFO] Adding FSR4 ML environment variables..."
cat >> ~/.bashrc <<EOF
# AMD FSR4 ML settings
export AMD_FSR4_FORCE_ML=1
export VKD3D_CONFIG=ps5
export HSA_OVERRIDE_GFX_VERSION=12.0.1
EOF

# --- 7. Установка ONNX Runtime ROCm ---
echo "[INFO] Installing onnxruntime-rocm..."
python3 -m venv ~/.venv
. ~/.venv/bin/activate # Активация виртуального окружения
pip install --upgrade onnxruntime-rocm  # Удален флаг --user
deactivate # Деактивация окружения после установки (необязательно, но рекомендуется)

# --- 8. Оптимизация ядра для AI/ML ---
echo "[INFO] Setting sysctl parameters..."
sudo bash -c 'cat >/etc/sysctl.d/90-amd-ai.conf <<EOF
kernel.sched_autogroup_enabled=0
kernel.sched_migration_cost_ns=5000000
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF'
sudo sysctl --system

# --- 9. Установка ROCm ML и HIP библиотек ---
echo "[INFO] Installing ROCm ML and HIP libraries..."
sudo apt install -y rocm-ml-libraries rocm-device-libs rocm-core hip-dev hipblas hipify-clang miopen-hip

# --- 10. Проверка GPU и ROCm ---
echo "[INFO] Checking ROCm GPU..."
if command -v rocminfo >/dev/null 2>&1; then
    rocminfo | grep gfx | head -n 20
else
    echo "[WARN] rocminfo not found. Check /opt/rocm/bin in PATH."
fi

echo "[INFO] Checking HIP compiler..."
if command -v hipcc >/dev/null 2>&1; then
    hipcc --version
else
    echo "[WARN] hipcc not found. Reload environment or add /opt/rocm/bin to PATH."
fi

echo "=== FINISHED ==="
echo ">>> REBOOT REQUIRED to apply changes!"
echo "After reboot, check:"
echo "  rocminfo | grep gfx"
echo "  hipcc --version"
echo "  python3 -m pip list | grep onnxruntime"
echo "  python3 - <<EOF
import onnxruntime as ort
print(ort.get_device())
EOF"

echo ">>> **IMPORTANT REMINDERS:** <<<"
echo "- Run this script with sudo privileges."
echo "- Reboot your system after running the script."
echo "- Ensure /opt/rocm/bin is in your PATH environment variable."
echo "- Refer to the official ROCm documentation for advanced configuration and troubleshooting: https://rocm.docs.amd.com/"
