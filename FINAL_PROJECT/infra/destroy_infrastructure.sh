#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/config.txt"

echo "Finding instances tagged with $EC2_INSTANCE_NAME..."
IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" --query "Reservations[].Instances[].InstanceId" --output text --region "$AWS_REGION")
if [ -n "$IDS" ]; then
  echo "Terminating instances: $IDS"
  aws ec2 terminate-instances --instance-ids $IDS --region "$AWS_REGION"
  aws ec2 wait instance-terminated --instance-ids $IDS --region "$AWS_REGION"
fi

echo "Deleting S3 bucket and contents: $S3_BUCKET_NAME"
aws s3 rm s3://$S3_BUCKET_NAME --recursive --region "$AWS_REGION" || true
aws s3api delete-bucket --bucket $S3_BUCKET_NAME --region "$AWS_REGION" || true

echo "Removing IAM instance profile and role"
ROLE_NAME="${EC2_INSTANCE_NAME}-S3AccessRole"
aws iam remove-role-from-instance-profile --instance-profile-name "$ROLE_NAME" --role-name "$ROLE_NAME" || true
aws iam delete-instance-profile --instance-profile-name "$ROLE_NAME" || true
aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess || true
aws iam delete-role --role-name "$ROLE_NAME" || true

echo "Done."
