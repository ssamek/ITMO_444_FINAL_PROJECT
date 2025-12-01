#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f "./config.sh" ]; then
  echo "ERROR: infra/config.sh not found."
  exit 1
fi
source config.txt
source ./cloudwatch_utils.sh

log_to_cw "Destroying infrastructure..."

# Terminate instances from instance_id.txt (if exists)
if [ -f instance_id.txt ]; then
  while IFS= read -r INSTANCE_ID || [ -n "$INSTANCE_ID" ]; do
    if [ -z "$INSTANCE_ID" ]; then continue; fi
    log_to_cw "Terminating instance $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" || true
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION" || true
    log_to_cw "Terminated $INSTANCE_ID"
  done < instance_id.txt
else
  log_to_cw "No instance_id.txt file found"
fi

# Remove instance IPs file
if [ -f instance_ip.txt ]; then rm -f instance_ip.txt; fi

# Delete S3 bucket contents and bucket
if aws s3api head-bucket --bucket "$RESUME_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
  log_to_cw "Emptying and deleting S3 bucket: $RESUME_BUCKET_NAME"
  aws s3 rm "s3://$RESUME_BUCKET_NAME" --recursive --region "$REGION" || true
  aws s3api delete-bucket --bucket "$RESUME_BUCKET_NAME" --region "$REGION" || true
else
  log_to_cw "S3 bucket not found or already deleted"
fi

# Find VPC
if [ -f vpc_id.txt ]; then
  VPC_ID=$(cat vpc_id.txt)
else
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:${PROJECT_TAG_KEY},Values=${PROJECT_TAG_VALUE}" --region "$REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
fi

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  log_to_cw "Cleaning up VPC: $VPC_ID"

  # Detach & delete Internet Gateways
  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$REGION" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo ""); do
    if [ -n "$igw" ]; then
      log_to_cw "Detaching IGW $igw"
      aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" --region "$REGION" || true
      aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION" || true
      log_to_cw "Deleted IGW $igw"
    fi
  done

  # Delete route table associations and route tables (non-main)
  for rtb in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || echo ""); do
    # skip main route table deletion (main will be removed with VPC)
    aws ec2 describe-route-tables --route-table-ids "$rtb" --region "$REGION" >/dev/null 2>&1 || continue
    # delete associations
    for assoc in $(aws ec2 describe-route-tables --route-table-ids "$rtb" --region "$REGION" --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text 2>/dev/null || echo ""); do
      if [ -n "$assoc" ]; then
        # don't try to disassociate main route-table association where Main=true
        is_main=$(aws ec2 describe-route-tables --route-table-ids "$rtb" --region "$REGION" --query 'RouteTables[0].Associations[?Main==`true`].Main' --output text 2>/dev/null || echo "")
        if [ "$is_main" != "True" ] && [ -n "$is_main" ]; then
          aws ec2 disassociate-route-table --association-id "$assoc" --region "$REGION" || true
        fi
      fi
    done

    # attempt to delete route table (non-main)
    aws ec2 delete-route-table --route-table-id "$rtb" --region "$REGION" 2>/dev/null || true
  done

  # Delete subnets
  for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo ""); do
    if [ -n "$subnet" ]; then
      log_to_cw "Deleting subnet $subnet"
      aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION" || true
    fi
  done

  # Delete security groups created for this project (skip default SG)
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:${PROJECT_TAG_KEY},Values=${PROJECT_TAG_VALUE}" --region "$REGION" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo ""); do
    if [ -n "$sg" ]; then
      log_to_cw "Deleting security group $sg"
      aws ec2 delete-security-group --group-id "$sg" --region "$REGION" || true
    fi
  done

  # Finally delete VPC
  log_to_cw "Deleting VPC $VPC_ID"
  aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" || true
else
  log_to_cw "VPC not found; skipping VPC cleanup"
fi

# Delete CloudWatch log group if exists
if aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP" --region "$REGION" --query 'logGroups[?logGroupName==`'"$CW_LOG_GROUP"'`].logGroupName' --output text 2>/dev/null | grep -q "$CW_LOG_GROUP"; then
  aws logs delete-log-group --log-group-name "$CW_LOG_GROUP" --region "$REGION" || true
fi

# Remove local state files if present
rm -f instance_id.txt instance_ip.txt vpc_id.txt sg_id.txt

log_to_cw "Infrastructure destroyed successfully"
send_cw_metric 1

echo "=== destroy_infrastructure.sh completed ==="
