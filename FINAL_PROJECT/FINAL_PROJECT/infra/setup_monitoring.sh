#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/config.txt"

# create SNS topic and subscription
TOPIC_ARN=$(aws sns create-topic --name "${EC2_INSTANCE_NAME}-alerts" --region "$AWS_REGION" --query "TopicArn" --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$ALARM_EMAIL" --region "$AWS_REGION"

# create CloudWatch log group (assuming the app logs to /var/log/resume_parser.log or to stdout via systemd journald)
aws logs create-log-group --log-group-name "/resume-parser/$EC2_INSTANCE_NAME" --region "$AWS_REGION" || true

# create alarm example: CPU > 70% for 5 minutes
aws cloudwatch put-metric-alarm --alarm-name "${EC2_INSTANCE_NAME}-HighCPU" \
  --alarm-description "High CPU alarm" \
  --namespace "AWS/EC2" --metric-name CPUUtilization --statistic Average \
  --period 300 --evaluation-periods 2 --threshold 70 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$EC2_INSTANCE_NAME" --query "Reservations[0].Instances[0].InstanceId" --output text --region "$AWS_REGION") \
  --alarm-actions "$TOPIC_ARN" --region "$AWS_REGION"

echo "Monitoring configured. Check your email to confirm SNS subscription ($ALARM_EMAIL)."
