#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f "./config.sh" ]; then echo "Missing config.sh"; exit 1; fi
source ./config.sh
source ./cloudwatch_utils.sh

log_to_cw "Setting up CloudWatch monitoring..."

# Create log group & stream
aws logs create-log-group --log-group-name "$CW_LOG_GROUP" --region "$REGION" 2>/dev/null || true
aws logs create-log-stream --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" --region "$REGION" 2>/dev/null || true

# Create a basic alarm template (you can attach SNS topic ARN if you want notifications)
INSTANCE_ID=$(cat instance_id.txt 2>/dev/null | head -n1 || echo "")
if [ -n "$INSTANCE_ID" ]; then
  aws cloudwatch put-metric-alarm \
    --alarm-name "ResumeApp_HighCPU" \
    --metric-name CPUUtilization \
    --namespace "AWS/EC2" \
    --statistic Average \
    --period 300 \
    --threshold 70 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --evaluation-periods 1 \
    --region "$REGION" || true

  log_to_cw "Created CPU alarm for instance $INSTANCE_ID"
else
  log_to_cw "No instance_id.txt found; skipping CPU alarm creation (create alarm manually or run this after instance is launched)."
fi

send_cw_metric 1
