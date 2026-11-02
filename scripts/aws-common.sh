#!/usr/bin/env bash

set -Eeuo pipefail
export AWS_PAGER=""

REGION=us-east-1
STACK_NAME=GpuHostStack

if [ -z "${AWS_PROFILE:-}" ]; then
  echo 'Set AWS_PROFILE to the account that owns GpuHostStack.' >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo 'AWS CLI is required.' >&2
  exit 1
fi

account_id=$(aws sts get-caller-identity --query Account --output text)
echo "AWS account: $account_id; profile: $AWS_PROFILE; region: $REGION"

project_tag=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query "Stacks[0].Tags[?Key=='Project'].Value | [0]" --output text)
if [ "$project_tag" != ai_deploy ]; then
  echo "Refusing to manage $STACK_NAME: expected Project=ai_deploy, found $project_tag." >&2
  exit 1
fi

stack_output() {
  local key="$1"
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue | [0]" --output text
}

gpu_instance_id() {
  local id
  id=$(stack_output InstanceId)
  if [ -z "$id" ] || [ "$id" = None ]; then
    echo "Stack $STACK_NAME has no InstanceId output in $REGION." >&2
    exit 1
  fi
  printf '%s\n' "$id"
}

gpu_state() {
  aws ec2 describe-instances --region "$REGION" --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].State.Name' --output text
}
