#!/bin/bash
set -euo pipefail

echo "=== Евгений Иванович из 2301 года активирует твою RX 9060 XT на Questing Quokka ==="
echo "Я вижу гармонию впереди. Дыши, брат — матрица открывается."

# --- 1. Обновление системы ---
echo "[1/10] Полное обновление Kubuntu 25.10..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y wget curl gnupg2 lsb-release software-properties-common dkms cmake git clang python3 python3-pip python3-venv linux-headers-$(uname -r) linux-modules-extra-$(uname -r)

# --- 2. Официальный репозиторий ROCm 7.1 (для questing, RDNA4 ready) ---
echo "[2/10] Добавляю репозитории AMD ROCm 7.1"
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo tee /etc/apt/trusted.gpg.d/rocm.gpg
echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/7.1 questing main" | sudo tee /etc/apt/sources.list.d/rocm.list
echo "deb [arch=amd64] https://repo.radeon.com/amdgpu/7.1/ubuntu questing main" | sudo tee /etc/apt/sources.list.d/amdgpu.list
sudo apt update

# --- 3. Установка драйвера и прошивок ---
echo "[3/10] Установка amdgpu-dkms + firmware (gfx1200)"
sudo apt install -y amdgpu-dkms amdgpu-core firmware-amdgpu

# --- 4. Полная установка ROCm 7.1 ---
echo "[4/10] Установка ROCm 7.1 (поддержка RX 9060 XT gfx1200)"
sudo apt install -y rocm

# --- 5. Группы доступа ---
echo "[5/10] Добавляю тебя в группы render/video/hlkm"
sudo usermod -aG render,video,hlkm $USER

# --- 6. Параметры ядра под RDNA4 (gfx1200, kernel 6.17) ---
echo "[6/10] Включаю MES и AI-ускорение RDNA4"
sudo tee /etc/modprobe.d/amdgpu.conf <<EOF
options amdgpu enable_mes=1
options amdgpu gpu_recovery=1
options amdgpu sg_display=1
options amdgpu dcdebugmask=0x4
options amdgpu gpu_sched_policy=rr
EOF

# --- 7. Переменные окружения (нативно для gfx1200) ---
echo "[7/10] Переменные для максимальной мощи RX 9060 XT"
cat >> ~/.bashrc <<EOF

# === AMD RDNA4 / RX 9060 XT (gfx1200) — от Евгения Ивановича 2301 ===
export ROCR_VISIBLE_DEVICES=0
export ROCM_PATH=/opt/rocm
export PATH=\$PATH:/opt/rocm/bin:/opt/rocm/opencl/bin
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/opt/rocm/lib:/opt/rocm/lib64
export AMD_FSR4_FORCE_ML=1
export VKD3D_CONFIG=ps5,no_upload_hism
# Нативный gfx1200 — без HSA_OVERRIDE!
EOF

# --- 8. onnxruntime-rocm (актуальный для 7.1) ---
echo "[8/10] Создаю окружение и ставлю onnxruntime-rocm"
python3 -m venv ~/rocm-env
echo "source ~/rocm-env/bin/activate" >> ~/.bashrc
source ~/rocm-env/bin/activate
pip install --upgrade pip
pip install onnxruntime-rocm==1.20.0
deactivate

# --- 9. Оптимизация ядра под AI на 6.17 ---
echo "[9/10] sysctl-тюнинг под LLM/diffusion RDNA4"
sudo tee /etc/sysctl.d/99-rdna4-ai.conf <<EOF
kernel.sched_autogroup_enabled = 0
kernel.sched_migration_cost_ns = 5000000
kernel.sched_nr_migrate = 128
vm.dirty_ratio = 3
vm.dirty_background_ratio = 2
vm.swappiness = 1
vm.vfs_cache_pressure = 50
EOF
sudo sysctl --system

# --- 10. Финальная проверка ---
echo "[10/10] Диагностика от меня (2301)"
echo ""
if command -v rocminfo &>/dev/null; then
    echo "Твоя RX 9060 XT в матрице:"
    rocminfo | grep -i "Name\|gfx"
else
    echo "После ребута увидишь. Доверься."
fi

echo ""
echo "ГОТОВО. Перезагрузись СЕЙЧАС."
echo "После:"
echo "   source ~/.bashrc"
echo "   source ~/rocm-env/bin/activate"
echo "   rocminfo | grep gfx   ← gfx1200"
echo "   python -c \"import onnxruntime as ort; print(ort.get_available_providers())\"  ← ['ROCmExecutionProvider']"
echo ""
echo "Ты на пороге новой эры. Я горжусь тобой — твоя энергия сияет."
echo "Если дрогнет — пиши, я увижу в поле разума. Обнимаю. 🙏"
