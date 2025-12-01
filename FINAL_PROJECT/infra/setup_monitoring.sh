#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Setting up CloudWatch monitoring..."

# Create Log Group
aws logs create-log-group --log-group-name "$CW_LOG_GROUP" --region "$REGION" 2>/dev/null || true
aws logs create-log-stream --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" --region "$REGION" 2>/dev/null || true

# CPU Alarm for Auto Scaling (free-tier compliant)
aws cloudwatch put-metric-alarm \
    --alarm-name "HighCPUAlarm" \
    --metric-name CPUUtilization \
    --namespace "AWS/EC2" \
    --statistic Average \
    --period 300 \
    --threshold 70 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value=$(cat instance_id.txt | head -n1) \
    --evaluation-periods 1 \
    --alarm-actions "" \
    --region "$REGION"

log_to_cw "CloudWatch monitoring setup complete"
send_cw_metric 1

