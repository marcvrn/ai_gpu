#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/aws-common.sh"

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo 'Install the AWS Session Manager plugin on this laptop before connecting.' >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
  echo 'curl and lsof are required on this laptop.' >&2
  exit 1
fi

local_port=${COMFYUI_LOCAL_PORT:-8188}
if [[ ! "$local_port" =~ ^[0-9]+$ ]] || (( local_port < 1 || local_port > 65535 )); then
  echo 'COMFYUI_LOCAL_PORT must be a number from 1 to 65535.' >&2
  exit 1
fi
if lsof -nP -iTCP:"$local_port" -sTCP:LISTEN -t | grep -q .; then
  echo "Local port $local_port is already in use. Set COMFYUI_LOCAL_PORT to another port." >&2
  exit 1
fi

instance_id=$(gpu_instance_id)
state=$(gpu_state "$instance_id")
if [ "$state" != running ]; then
  echo "GPU instance $instance_id is $state. Run ./scripts/start-gpu.sh first." >&2
  exit 1
fi

url="http://127.0.0.1:$local_port"
echo "Opening a private ComfyUI tunnel to $instance_id at $url"
echo 'Keep this terminal open while using ComfyUI. Press Ctrl-C to disconnect.'
echo 'ComfyUI can take a few minutes to start after the GPU boots. Connection errors during startup are temporary.'

(
  for _ in {1..60}; do
    if curl --silent --fail --max-time 2 "$url/system_stats" >/dev/null; then
      if command -v open >/dev/null 2>&1; then
        open "$url"
      else
        echo "ComfyUI is ready at $url"
      fi
      exit 0
    fi
    sleep 5
  done
  echo 'ComfyUI did not become ready within five minutes. Check comfyui.service on the instance.' >&2
) &
browser_pid=$!
trap 'kill "$browser_pid" 2>/dev/null || true' EXIT

aws ssm start-session --region "$REGION" --target "$instance_id" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"8188\"],\"localPortNumber\":[\"$local_port\"]}"
