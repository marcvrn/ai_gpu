#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/aws-common.sh"

instance_id=$(gpu_instance_id)
state=$(gpu_state "$instance_id")
echo "GPU instance: $instance_id; state: $state"

case "$state" in
  running)
    echo 'GPU is already running.'
    ;;
  stopped)
    aws ec2 start-instances --region "$REGION" --instance-ids "$instance_id" >/dev/null
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$instance_id"
    echo 'GPU is running. ComfyUI may need a little longer to become ready.'
    ;;
  *)
    echo "Cannot start a GPU instance in state $state. Try again after its current transition finishes." >&2
    exit 1
    ;;
esac
