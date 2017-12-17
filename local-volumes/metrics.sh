#!/bin/bash
#
DIR=$(dirname $0)

source ${DIR}/config

METRICS_DIR=${DIR}/../monitor/metrics
METRIC_FILE=${METRICS_DIR}/lv_metrics.prom

COLLECT_INTERVAL=15

echo "Started $0 at $(date) on node $NODE_NAME
METRIC_FILE=${METRIC_FILE}
COLLECT_INTERVAL=${COLLECT_INTERVAL}
"

if [[ -d "${METRICS_DIR}" ]]; then
   mkdir -p "${METRICS_DIR}"
fi

METRICS_dind_volume_creation_time="${METRICS_DIR}"/dind_volume_creation_time.prom
METRICS_TMP_dind_volume_creation_time="${METRICS_DIR}"/dind_volume_creation_time.prom.tmp.$$

METRICS_dind_volume_last_used_time="${METRICS_DIR}"/dind_volume_last_used_time.prom
METRICS_TMP_dind_volume_last_used_time="${METRICS_DIR}"/dind_volume_last_used_time.prom.tmp.$$

METRICS_dind_volume_mounts_count="${METRICS_DIR}"/dind_volume_mounts_count.prom
METRICS_TMP_dind_volume_mounts_count="${METRICS_DIR}"/dind_volume_mounts_count.prom.tmp.$$

METRICS_dind_volume_deleted_since="${METRICS_DIR}"/dind_volume_deleted_since.prom
METRICS_TMP_dind_volume_deleted_since="${METRICS_DIR}"/dind_volume_deleted_since.prom.tmp.$$

while true; do
    cat <<EOF > "${METRICS_TMP_dind_volume_creation_time}"
# TYPE local_volume_creation_time gauge
# HELP local_volume_creation_time - local volume creation timestamp
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_last_used_time}"
# TYPE local_volume_last_used_time gauge
# HELP local_volume_last_used_time - local volume last_used timestamp
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_mounts_count}"
# TYPE local_volume_mounts_count gauge
# HELP local_volume_mounts_count - local volume mounts count
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_deleted_since}"
# TYPE local_volume_deleted_since gauge
# HELP local_volume_deleted_since - local volume deletion timestamp
EOF

    for ii in $(find "${VOLUME_PARENT_DIR}" -mindepth 1 -maxdepth 1 -type d -name "${VOLUME_DIR_PATTERN}")
    do
        VOLUME_PATH=$ii
        LABELS="node_name=\"${NODE_NAME}\",volume_path=\"${VOLUME_PATH}\",backend_type=\"local\""

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

        echo "local_volume_creation_time{$LABELS} ${CREATED}" >> "${METRICS_TMP_dind_volume_creation_time}"
        echo "local_volume_last_used_time{$LABELS} ${LAST_USED}" >> "${METRICS_TMP_dind_volume_last_used_time}"
        echo "local_volume_mounts_count{$LABELS} ${MOUNTS_COUNT}" >> "${METRICS_TMP_dind_volume_mounts_count}"
        if [[ -f ${DIR_NAME}/deleted ]]; then
            DELETED=$(awk 'END {print $1}' < ${VOLUME_PATH}/deleted)
            echo "local_volume_deleted_since{$LABELS} ${CREATED}" >> "${METRICS_TMP_dind_volume_deleted_since}"
        fi

    done

    mv "${METRICS_TMP_dind_volume_creation_time}" "${METRICS_dind_volume_creation_time}"
    mv "${METRICS_TMP_dind_volume_last_used_time}" "${METRICS_dind_volume_last_used_time}"
    mv "${METRICS_TMP_dind_volume_mounts_count}" "${METRICS_dind_volume_mounts_count}"
    mv "${METRICS_TMP_dind_volume_deleted_since}" "${METRICS_dind_volume_deleted_since}"

   sleep $COLLECT_INTERVAL
done
