#!/bin/bash
# Quick status check
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

detect_base_dir() { BASE_DIR="$(pwd)"; [ -d "$BASE_DIR/fe" ] && BASE_DIR="$BASE_DIR/fe"; }
detect_base_dir 2>/dev/null || BASE_DIR="$(pwd)"

TD="${BASE_DIR}/${TRACKING_DIR}"
[ ! -d "$TD" ] && echo "No automation session found" && exit 1

Q=$(wc -l < "$TD/$JOB_QUEUE_FILE" 2>/dev/null || echo 0)
A=$(wc -l < "$TD/$ACTIVE_JOBS_FILE" 2>/dev/null || echo 0)
C=$(wc -l < "$TD/$COMPLETED_JOBS_FILE" 2>/dev/null || echo 0)
F=$(wc -l < "$TD/$FAILED_JOBS_FILE" 2>/dev/null || echo 0)
T=$((Q+A+C+F))
P=$(( T>0 ? ((C+F)*100)/T : 0 ))

echo "Status: Completed: $C | Failed: $F | Running: $A | Queued: $Q | Progress: ${P}%"
