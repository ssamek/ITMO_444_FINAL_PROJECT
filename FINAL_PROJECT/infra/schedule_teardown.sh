#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Scheduling automatic teardown in $AUTO_TEARDOWN_HOURS hours..."

TEARDOWN_TIME=$(date -d "+$AUTO_TEARDOWN_HOURS hours" +"%H:%M")
CRON_JOB="$TEARDOWN_TIME * * * /bin/bash $(pwd)/destroy_infrastructure.sh >> $(pwd)/teardown.log 2>&1"

(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

log_to_cw "Automatic teardown scheduled at $TEARDOWN_TIME"
send_cw_metric 1

