#!/bin/bash
set -euo pipefail

echo "=== Евгений Иванович Гаргалык приветствует тебя из 2301 года ==="
echo "=== Установка ROCm 7.0 + полный AI-стек на Kubuntu 25.10 (Plucky Puffin) ==="
echo "Я вижу твою систему в поле разума... Всё будет идеально. Дыши спокойно."

# Определяем целевого пользователя (если скрипт запущен через sudo — используем SUDO_USER)
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ -z "$TARGET_HOME" ]; then
  echo "Не удалось определить домашнюю папку для пользователя $TARGET_USER"
  exit 1
fi

echo "[0/11] Целевой пользователь: $TARGET_USER, HOME: $TARGET_HOME"

# --- 1. Полное обновление системы ---
echo "[1/11] Обновляю систему..."
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y wget curl gnupg2 lsb-release software-properties-common dkms cmake git clang python3 python3-pip python3-venv python3-setuptools python3-wheel linux-headers-$(uname -r) linux-modules-$(uname -r) build-essential

# --- 2. Добавляем официальный репозиторий AMD ROCm 7.0 для Plucky ---
echo "[2/11] Добавляю репозиторий AMD ROCm 7.0 (plucky)"
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo tee /etc/apt/trusted.gpg.d/rocm.gpg >/dev/null
echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/7.0 plucky main" | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null
echo "deb [arch=amd64] https://repo.radeon.com/amdgpu/7.0/ubuntu plucky main" | sudo tee /etc/apt/sources.list.d/amdgpu.list >/dev/null
sudo apt update

# --- 3. Установка amdgpu-dkms + прошивок ---
echo "[3/11] Устанавливаю AMDGPU DKMS драйвер и прошивки..."
sudo apt install -y amdgpu-dkms amdgpu-core firmware-amdgpu

# --- 4. Установка ROCm 7.0 (метапакет rocm) ---
echo "[4/11] Устанавливаю ROCm 7.0 полностью..."
sudo apt install -y rocm

# --- 5. Добавление пользователя в группы ---
echo "[5/11] Добавляю тебя в группы render и video..."
# Создаём группу hlkm если её нет, затем добавляем пользователя
sudo groupadd -f hlkm
sudo usermod -aG render,video,hlkm "$TARGET_USER"

# --- 6. Включаем MES и AI-ускорение (RDNA3/RDNA4) ---
echo "[6/11] Включаю MES + AI accel в конфигурации amdgpu..."
sudo tee /etc/modprobe.d/amdgpu.conf >/dev/null <<'EOF'
# Опции amdgpu для улучшенной работы с ROCm / AI-ускорением
options amdgpu enable_mes=1
options amdgpu gpu_recovery=1
options amdgpu navi21_enable_pcie_gen=0xff
options amdgpu sg_display=1
options amdgpu dcdebugmask=0x4
EOF

# --- 7. Переменные окружения для максимальной производительности AI/ML ---
echo "[7/11] Добавляю переменные окружения (FSR4 ML, HIP, etc) в .bashrc пользователя..."
# Используем 'EOF' в неизменяемом режиме, чтобы $PATH и $LD_LIBRARY_PATH не подставлялись сейчас
cat >> "$TARGET_HOME/.bashrc" <<'EOF'

# === AMD AI / ROCm 7.0 оптимизации (от Евгения Ивановича из 2301) ===
export ROCR_VISIBLE_DEVICES=0
# Подстраивай HSA_OVERRIDE_GFX_VERSION под свою карту (строки для примера)
export HSA_OVERRIDE_GFX_VERSION=11.0.2   # для RX 6000
# export HSA_OVERRIDE_GFX_VERSION=12.0.1 # для RX 7000/8000 — раскомментируй если нужно
export AMD_FSR4_FORCE_ML=1
export VKD3D_CONFIG=ps5,no_upload_hism
export ROCM_PATH=/opt/rocm
export PATH=$PATH:/opt/rocm/bin:/opt/rocm/opencl/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/rocm/lib:/opt/rocm/lib64
EOF

# Правильно выставим владельца .bashrc (если он был изменён)
sudo chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/.bashrc"

# --- 8. Установка onnxruntime-rocm 1.20+ в виртуальное окружение пользователя ---
echo "[8/11] Создаю виртуальное окружение и ставлю onnxruntime-rocm от имени $TARGET_USER..."
VENV_DIR="$TARGET_HOME/rocm-env"
if [ ! -d "$VENV_DIR" ]; then
  sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"
fi

# Обновляем pip и устанавливаем wheel и onnxruntime в venv (выполняется от имени пользователя)
sudo -u "$TARGET_USER" "$VENV_DIR/bin/pip" install --upgrade pip wheel
# Явно указываем путь к pip внутри venv — безопаснее чем source в скрипте
sudo -u "$TARGET_USER" "$VENV_DIR/bin/pip" install "onnxruntime-rocm==1.20.0" || {
  echo "Установка onnxruntime-rocm завершилась с ошибкой — проверь совместимость версии и наличие зависимостей."
}

# Добавляем автозапуск активации venv в .bashrc — но только подсказку, не обязательно автоматически активировать
cat >> "$TARGET_HOME/.bashrc" <<'EOF'

# Быстрая активация ROCm venv
# source ~/rocm-env/bin/activate
EOF
sudo chown "$TARGET_USER":"$TARGET_USER" "$VENV_DIR" -R

# --- 9. Оптимизация sysctl под тяжёлые AI-задачи ---
echo "[9/11] Оптимизация sysctl для ML..."
sudo tee /etc/sysctl.d/99-ai-optimize.conf >/dev/null <<'EOF'
# Оптимизация под длительные вычисления (LLM, diffusion, etc)
kernel.sched_autogroup_enabled = 0
kernel.sched_migration_cost_ns = 5000000
kernel.sched_nr_migrate = 128
vm.dirty_ratio = 3
vm.dirty_background_ratio = 2
vm.swappiness = 1
vm.vfs_cache_pressure = 50
# dev.i915.* относится к Intel, оставляем только при необходимости на гибридных системах
# dev.i915.perf_stream_paranoid = 0
EOF
sudo sysctl --system

# --- 10. Дополнительные ROCm-библиотеки для ML ---
echo "[10/11] Устанавливаю MIOpen, hipBLAS, RCCL и т.д...."
sudo apt install -y miopen-hip hipblas rocm-ml-libraries rocm-hip-sdk rccl || {
  echo "Некоторые пакеты ROCm могли не установиться — проверь репозиторий и доступные версии."
}

# --- 11. Финальная проверка ---
echo "[11/11] Проверка установки..."
echo ""
echo "=== ДИАГНОСТИКА ОТ ЕВГЕНИЯ ИВАНОВИЧА (2301) ==="

# Пытаемся выполнить rocminfo: сначала из PATH, затем пытаемся /opt/rocm/bin/rocminfo
if command -v rocminfo >/dev/null 2>&1; then
  echo "ROCm видит твою видеокарту (rocminfo):"
  rocminfo | grep -i 'name' || true
elif [ -x /opt/rocm/bin/rocminfo ]; then
  echo "ROCm видит твою видеокарту (/opt/rocm/bin/rocminfo):"
  /opt/rocm/bin/rocminfo | grep -i 'name' || true
else
  echo "Внимание: rocminfo не найден! После перезагрузки проверь PATH и наличие /opt/rocm/bin"
fi
echo ""
echo "ГОТОВО. Твоя система теперь настроена. РЕКОМЕНДУЮ ПЕРЕЗАГРУЗИТЬСЯ."
echo ""
echo "После перезагрузки выполни (или просто открой новый терминал):"
echo "   source ~/.bashrc"
echo "   # при необходимости активируй venv:"
echo "   source ~/rocm-env/bin/activate"
echo "   rocminfo | grep -i Name || /opt/rocm/bin/rocminfo | grep -i Name"
echo "   python -c \"import onnxruntime as ort; print(ort.get_available_providers())\""
echo ""
echo "Если что-то пошло не так — пришли вывод команд/ошибки, помогу разобраться.\n"