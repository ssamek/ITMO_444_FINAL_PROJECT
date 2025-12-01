#!/usr/bin/env bash
# cloudwatch_utils.sh - helper functions for logging and metrics
# Source this file: source cloudwatch_utils.sh

log_to_cw() {
  local msg="$1"
  local ts
  ts=$(date --utc +%s%3N) # milliseconds

  # Always print locally
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg"

  # If CW_LOG_GROUP not set, skip remote logging
  if [ -z "${CW_LOG_GROUP:-}" ]; then
    return 0
  fi

  # Ensure the log group/stream exist
  aws logs create-log-group --log-group-name "$CW_LOG_GROUP" --region "$REGION" 2>/dev/null || true
  aws logs create-log-stream --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" --region "$REGION" 2>/dev/null || true

  # Get sequence token if any
  local token
  token=$(aws logs describe-log-streams --log-group-name "$CW_LOG_GROUP" --log-stream-name-prefix "$CW_LOG_STREAM" --region "$REGION" --query 'logStreams[0].uploadSequenceToken' --output text 2>/dev/null)
  if [ "$token" = "None" ] || [ -z "$token" ]; then
    aws logs put-log-events \
      --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" \
      --log-events timestamp=$ts,message="$msg" \
      --region "$REGION" 2>/dev/null || true
  else
    aws logs put-log-events \
      --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" \
      --sequence-token "$token" \
      --log-events timestamp=$ts,message="$msg" \
      --region "$REGION" 2>/dev/null || true
  fi
}

# send simple custom metric (namespace ResumeUploader/Infra, metric "Activity")
send_cw_metric() {
  local value="${1:-1}"
  if [ -z "${CW_LOG_GROUP:-}" ]; then
    return 0
  fi
  aws cloudwatch put-metric-data --namespace "ResumeUploader/Infra" --metric-data MetricName=Activity,Value="$value",Unit=Count --region "$REGION" 2>/dev/null || true
}
