#!/usr/bin/env bash
set -Eeuo pipefail

exec > >(tee -a /var/log/ai-deploy-setup.log) 2>&1
trap 'echo "Setup failed at line $LINENO. Check /var/log/ai-deploy-setup.log." >&2' ERR

export DEBIAN_FRONTEND=noninteractive
export PIP_NO_CACHE_DIR=1

COMFY_DIR=/opt/ComfyUI
COMFY_VERSION=v0.43.0
MODEL_BASE=https://huggingface.co/Comfy-Org/Wan-2.2/resolve/main/split_files

apt-get update
apt-get install -y --no-install-recommends git curl ca-certificates python3 python3-venv python3-pip ffmpeg

if ! id comfyui >/dev/null 2>&1; then
  useradd --system --home-dir "$COMFY_DIR" --shell /usr/sbin/nologin comfyui
fi

if [ ! -d "$COMFY_DIR/.git" ]; then
  if [ -e "$COMFY_DIR" ]; then
    echo "Cannot replace existing non-Git directory at $COMFY_DIR" >&2
    exit 1
  fi
  rm -rf "${COMFY_DIR}.partial"
  git clone --branch "$COMFY_VERSION" --depth 1 https://github.com/Comfy-Org/ComfyUI.git "${COMFY_DIR}.partial"
  mv "${COMFY_DIR}.partial" "$COMFY_DIR"
fi

if [ "$(git -C "$COMFY_DIR" describe --tags --exact-match)" != "$COMFY_VERSION" ]; then
  echo "Existing ComfyUI checkout at $COMFY_DIR is not $COMFY_VERSION" >&2
  exit 1
fi

if [ ! -x "$COMFY_DIR/.venv/bin/python" ]; then
  python3 -m venv "$COMFY_DIR/.venv"
fi

"$COMFY_DIR/.venv/bin/python" -m pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu130 torch torchvision torchaudio
"$COMFY_DIR/.venv/bin/python" -m pip install --no-cache-dir -r "$COMFY_DIR/requirements.txt"
nvidia-smi >/dev/null
"$COMFY_DIR/.venv/bin/python" -c 'import torch; assert torch.cuda.is_available(), "PyTorch cannot access the GPU"'

download_model() {
  local relative_path="$1"
  local expected_sha256="$2"
  local destination="$COMFY_DIR/models/${relative_path#split_files/}"
  local partial="${destination}.part"

  mkdir -p "$(dirname "$destination")"
  if [ -f "$destination" ] && printf '%s  %s\n' "$expected_sha256" "$destination" | sha256sum --check --status; then
    return
  fi
  rm -f "$destination"
  curl --fail --location --retry 5 --retry-delay 5 --retry-all-errors --continue-at - \
    --output "$partial" "$MODEL_BASE/${relative_path#split_files/}"
  if ! printf '%s  %s\n' "$expected_sha256" "$partial" | sha256sum --check --status; then
    echo "Checksum failed for $relative_path" >&2
    rm -f "$partial"
    return 1
  fi
  mv "$partial" "$destination"
}

download_model split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors \
  456f901338bd9eadbded3828b819109a9b68e8a525ca5cf8d0049a69fcfeca1e
download_model split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
  c3355d30191f1f066b26d93fba017ae9809dce6c627dda5f6a66eaa651204f68
download_model split_files/vae/wan2.2_vae.safetensors \
  e40321bd36b9709991dae2530eb4ac303dd168276980d3e9bc4b6e2b75fed156

chown -R comfyui:comfyui "$COMFY_DIR"

cat >/etc/systemd/system/comfyui.service <<'UNIT'
[Unit]
Description=Private ComfyUI for Wan 2.2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=comfyui
Group=comfyui
WorkingDirectory=/opt/ComfyUI
ExecStart=/opt/ComfyUI/.venv/bin/python main.py --listen 127.0.0.1 --port 8188
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now comfyui.service
for attempt in {1..60}; do
  if curl --fail --silent http://127.0.0.1:8188/system_stats >/dev/null; then
    echo 'ComfyUI setup completed.'
    exit 0
  fi
  sleep 5
done
systemctl status comfyui.service --no-pager || true
echo 'ComfyUI did not become ready within five minutes.' >&2
exit 1
