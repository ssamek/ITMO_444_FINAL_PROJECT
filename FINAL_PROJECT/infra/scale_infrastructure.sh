#!/usr/bin/env bash
# quick script to launch an additional EC2 instance with same userdata
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/config.txt"

# reuse SG, Key and Instance Profile created earlier
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${EC2_INSTANCE_NAME}-sg" --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION")
INSTANCE_PROFILE_NAME="${EC2_INSTANCE_NAME}-S3AccessRole"

# you may reuse the same USERDATA from create_infrastructure.sh or point to a bootstrap script in S3
USERDATA_FILE="$DIR/userdata.sh"
if [ -f "$USERDATA_FILE" ]; then
  USERDATA="$(cat "$USERDATA_FILE")"
else
  USERDATA="#!/bin/bash
echo 'no userdata file'"
fi

aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
  --user-data "$USERDATA" \
  --region "$AWS_REGION"
echo "Launched one additional instance."
