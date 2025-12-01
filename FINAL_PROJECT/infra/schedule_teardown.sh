#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/config.txt"

HOURS=${AUTO_TEARDOWN_HOURS:-24}
echo "Scheduling teardown in $HOURS hours."
( sleep $((HOURS * 3600)) && bash "$DIR/destroy_infrastructure.sh" ) & disown
echo "Teardown scheduled (background)."
