#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TAG_NAME="${TAG_NAME:-resume-parser-demo}"
KEY_NAME="${KEY_NAME:-resume-demo-key}"
BUCKET_NAME="${BUCKET_NAME:-}" # if you used create script, replace with same value or read from a file

# 1. Terminate instances with tag
INSTANCE_IDS=$(aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Name,Values=$TAG_NAME" "Name=instance-state-name,Values=running,stopping,stopped,pending" --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCE_IDS" ]; then
  echo "Terminating instances: $INSTANCE_IDS"
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $INSTANCE_IDS
else
  echo "No instances found with tag $TAG_NAME"
fi

# 2. Remove S3 bucket (if provided). BE CAREFUL: deletes all objects.
if [ -n "$BUCKET_NAME" ]; then
  echo "Removing objects and deleting S3 bucket $BUCKET_NAME"
  aws s3 rm "s3://$BUCKET_NAME" --recursive || true
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" || true
fi

# 3. Remove security group (best-effort)
SG_NAME="${SEC_GROUP_NAME:-resume-parser-sg}"
SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Deleting security group $SG_ID"
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$SG_ID" || true
fi

# 4. Remove key pair locally and in AWS
aws ec2 delete-key-pair --region "$AWS_REGION" --key-name "$KEY_NAME" || true
if [ -f "./${KEY_NAME}.pem" ]; then
  rm -f "./${KEY_NAME}.pem"
fi

# 5. Remove IAM role and instance profile (best-effort)
IAM_ROLE_NAME="${IAM_ROLE_NAME:-ResumeParserEC2Role}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-ResumeParserProfile}"
if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$IAM_ROLE_NAME" || true
  aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" || true
fi
if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
  # remove inline policies
  POLICIES=$(aws iam list-role-policies --role-name "$IAM_ROLE_NAME" --query 'PolicyNames' --output text || true)
  for p in $POLICIES; do
    aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$p" || true
  done
  aws iam delete-role --role-name "$IAM_ROLE_NAME" || true
fi

echo "Destroy complete (best-effort). Check your AWS console for any remaining resources."
