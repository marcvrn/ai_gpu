#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/aws-common.sh"

instance_id=$(gpu_instance_id)
state=$(gpu_state "$instance_id")
echo "GPU instance: $instance_id; state: $state"

case "$state" in
  stopped)
    echo 'GPU is already stopped.'
    ;;
  running)
    echo 'Stopping now. Any active ComfyUI job will be interrupted.'
    aws ec2 stop-instances --region "$REGION" --instance-ids "$instance_id" >/dev/null
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$instance_id"
    echo 'GPU is stopped. EBS storage still incurs charges.'
    ;;
  *)
    echo "Cannot stop a GPU instance in state $state. Try again after its current transition finishes." >&2
    exit 1
    ;;
esac
