#!/bin/bash

echo "Starting node_exporter.sh in background
"

sigterm_trap(){
   echo "SIGTERM received at $(date) - killing NODE_EXPORTER_PID ${NODE_EXPORTER_PID}"
   kill $NODE_EXPORTER_PID
}
trap sigterm_trap SIGTERM

DIR=$(dirname $0)

LOG_DIR=${DIR}/log
mkdir -p ${LOG_DIR}

NODE_EXPORTER_LOG_FILE=${LOG_DIR}/node_exporter.log
echo "Starting node_exporter.sh in background, log file in $NODE_EXPORTER_LOG_FILE "
${DIR}/node_exporter.sh &>"${NODE_EXPORTER_LOG_FILE}" <&- &
NODE_EXPORTER_PID=$!
echo "node_exporter.sh has been started with pid=${NODE_EXPORTER_PID}"