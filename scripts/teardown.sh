#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
source "$script_dir/aws-common.sh"

instance_id=$(stack_output InstanceId)
if [ -z "$instance_id" ] || [ "$instance_id" = None ]; then
  instance_id='not yet available'
fi
echo "Stack: $STACK_NAME; GPU instance: $instance_id"
echo 'Destroying this stack deletes the EC2 instance, its EBS root volume, models, and generated outputs.'
echo 'The pre-existing default VPC and the potentially shared CDKToolkit bootstrap stack remain.'
printf 'Type "destroy %s" to continue: ' "$STACK_NAME"
IFS= read -r answer
if [ "$answer" != "destroy $STACK_NAME" ]; then
  echo 'Cancelled. No changes made.'
  exit 1
fi

if ! command -v node >/dev/null 2>&1 || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  echo 'Node.js 22+ is required to run CDK.' >&2
  exit 1
fi
if [ ! -x "$project_dir/node_modules/.bin/cdk" ]; then
  echo 'Local CDK CLI is missing. Run npm install before teardown.' >&2
  exit 1
fi

aws cloudformation update-termination-protection --region "$REGION" \
  --stack-name "$STACK_NAME" --no-enable-termination-protection
(cd "$project_dir" && ./node_modules/.bin/cdk destroy "$STACK_NAME" --force)
echo "Stack $STACK_NAME has been destroyed in account $account_id, region $REGION."
