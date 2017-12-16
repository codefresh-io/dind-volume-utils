#!/bin/bash
#
DIR=$(dirname $0)

METRICS_DIR=${DIR}/../monitor/metrics
METRIC_FILE=${METRICS_DIR}/lv_metrics.prom
METRIC_FILE_TMP=${METRIC_FILE}.$$

COLLECT_INTERVAL=15

echo "Started $0 at $(date) on node $NODE_NAME
METRIC_FILE=${METRIC_FILE}
COLLECT_INTERVAL=${COLLECT_INTERVAL}
"

DOCKER_PS_OUT_FILE=/tmp/docker-ps.out

DF_OUT_FILE=/tmp/df.out
DF_INODES_OUT_FILE=/tmp/df-i.out
if [[ $(uname) == "Linux" ]]; then
   DF_OPTS="-B 1024"
fi

while true; do
     rm -f "${METRIC_FILE_TMP}"

     for ii in $(find "${VOLUME_PARENT_DIR}" -mindepth 1 -maxdepth 1 -type d -name "${VOLUME_DIR_PATTERN}")
     do
        VOLUME_PATH=$ii
        LABELS="node_name=\"${NODE_NAME}\",volume_path=\"${VOLUME_PATH}\""

        if [[ -f ${VOLUME_PATH}/created ]]; then
           CREATED=$(awk 'END {print $1}' < ${VOLUME_PATH}/created)
        else
           CREATED="9999999999"
        fi

        if [[ -f ${VOLUME_PATH}/last_used ]]; then
           LAST_USED=$(awk 'END {print $1}' < ${VOLUME_PATH}/last_used)
        else
           LAST_USED="9999999999"
        fi

        if [[ -f ${VOLUME_PATH}/pods ]]; then
           MOUNTS_COUNT=$(wc -l < ${VOLUME_PATH}/pods)
        else
           MOUNTS_COUNT="0"
        fi

        cat <<EOF >> $METRIC_FILE_TMP
# TYPE local_volume_creation_time gauge
# HELP local_volume_creation_time - local volume creation timestamp
local_volume_creation_time{$LABELS} ${CREATED}

# TYPE local_volume_last_used_time gauge
# HELP local_volume_last_used_time - local volume last_used timestamp
local_volume_last_used_time{$LABELS} ${LAST_USED}

# TYPE local_volume_mounts_count gauge
# HELP local_volume_mounts_count - local volume mounts count
local_volume_mounts_count{$LABELS} ${MOUNTS_COUNT}
EOF
        if [[ -f ${DIR_NAME}/deleted ]]; then
        cat <<EOF >> $METRIC_FILE_TMP
# TYPE local_volume_deleted_since gauge
# HELP local_volume_deleted_since - local volume deletion timestamp
local_volume_creation_time{$LABELS} ${CREATED}
EOF
        fi

     done

   mv ${METRIC_FILE_TMP} ${METRIC_FILE}
   sleep $COLLECT_INTERVAL
done
