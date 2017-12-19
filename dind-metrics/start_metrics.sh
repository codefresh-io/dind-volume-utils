#!/bin/bash

echo "Starting dind metric collector in background:
"

sigterm_trap(){
   echo "SIGTERM received at $(date) - killing METRICS_PID ${METRICS_PID}"
   kill $METRICS_PID
}
trap sigterm_trap SIGTERM

DIR=$(dirname $0)

LOG_DIR=${DIR}/log
mkdir -p ${LOG_DIR}

METRICS_LOG_FILE=${LOG_DIR}/metrics.log
echo "Starting metrics.sh in background, log file in $METRICS_LOG_FILE "
${DIR}/metrics.sh &>"${METRICS_LOG_FILE}" <&- &
METRICS_PID=$!
