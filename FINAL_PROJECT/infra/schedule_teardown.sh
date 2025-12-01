#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f "./config.sh" ]; then echo "Missing config.sh"; exit 1; fi
source ./config.sh
source ./cloudwatch_utils.sh

log_to_cw "Scheduling automatic teardown in $AUTO_TEARDOWN_HOURS hours..."

# compute absolute time
TARGET_TIME=$(date -d "+${AUTO_TEARDOWN_HOURS} hours" +"%M %H %d %m %u")
# But simpler: schedule at hour/min
CRON_MIN=$(date -d "+${AUTO_TEARDOWN_HOURS} hours" +"%M")
CRON_HOUR=$(date -d "+${AUTO_TEARDOWN_HOURS} hours" +"%H")
CRON_JOB="$CRON_MIN $CRON_HOUR * * * /bin/bash $(pwd)/destroy_infrastructure.sh >> $(pwd)/teardown.log 2>&1"

# install crontab entry idempotently (comment with marker)
(crontab -l 2>/dev/null | grep -v '# RESUME_TEARDOWN' || true; echo "# RESUME_TEARDOWN - scheduled teardown"; echo "$CRON_JOB # RESUME_TEARDOWN") | crontab -

log_to_cw "Automatic teardown scheduled at ${CRON_HOUR}:${CRON_MIN} (local time)"
send_cw_metric 1
