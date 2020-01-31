#!/bin/bash
#
DIR=$(dirname $0)

METRICS_DIR=${DIR}/../monitor/metrics

COLLECT_INTERVAL=15

echo "Started $0 at $(date) on node $NODE_NAME
COLLECT_INTERVAL=${COLLECT_INTERVAL}
"

if [[ ! -d "${METRICS_DIR}" ]]; then
   mkdir -p "${METRICS_DIR}"
fi

### Creating Metric Variables for temporary file names
METRIC_NAMES=(
         dind_volume_last_mount_ts
         # dind_volume_mount_count
)

for i in ${METRIC_NAMES[@]}; do
    eval METRICS_${i}="${METRICS_DIR}"/${i}.prom
    eval METRICS_TMP_${i}="${METRICS_DIR}"/${i}.prom.tmp.$$
    eval echo "$i metric collected to \$METRICS_${i} "
done

create_metrics_headers(){
    cat <<EOF > "${METRICS_TMP_dind_volume_mount_count}"
# TYPE dind_volume_mount_count gauge
# HELP dind_volume_mount_count volume mounts count
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_last_mount_ts}"
# TYPE dind_volume_last_mount_ts gauge
# HELP dind_volume_last_mount_ts volume last mount timestamp
EOF
}


get_dind_volumes_metrics(){
    local TEMPLATE_GET_PV='{{range .items}}'

    TEMPLATE_GET_PV+='{{.metadata.name}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{.spec.storageClassName}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{.status.phase}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{.spec.persistentVolumeReclaimPolicy}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.annotations "codefresh.io/mount-count" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.annotations "codefresh.io/backendVolumeTimestamp" }}'

    TEMPLATE_GET_PV+='{{"\t"}}{{- if (index .metadata.annotations "codefresh.io/lastUsedTimestamp" )}}'
    TEMPLATE_GET_PV+='   {{index .metadata.annotations "codefresh.io/lastUsedTimestamp"}}'
    TEMPLATE_GET_PV+='{{- else}}{{.metadata.creationTimestamp }}{{- end }}'

    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "backend-volume-type" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.annotations "backend-volume-id" }}'
   
    TEMPLATE_GET_PV+='{{"\t"}}{{if .spec.claimRef }}{{index .spec.claimRef "name" }}{{ end}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{if .spec.claimRef }}{{index .spec.claimRef "namespace" }}{{ end}}'

    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pod_namespace" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pod_name" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "runtime_env" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "io.codefresh.accountName" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pipeline_id" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "backend-volume-id-md5" }}'

    TEMPLATE_GET_PV+='{{"\n"}}{{end}}'

    local LABELS
    local PV_NAME
    local STORAGE_CLASS    
    local PHASE
    local RECLAIM_POLICY
    local MOUNT_COUNT
    local VOLUME_CREATION_TS
    local LAST_MOUNT_TS
    local BACKEND_VOLUME_TYPE
    local BACKEND_VOLUME_ID

    local POD_NAMESPACE
    local POD_NAME
    local RUNTIME_ENV
    local ACCOUNT_NAME
    local PIPELINE_ID
    local BACKEND_VOLUME_ID_MD5

    local VOLUMES_METRICS=(
      dind_volume_last_mount_ts
      # dind_volume_mount_count
    )

    local dind_volume_phase_VALUE
    local dind_volume_creation_ts_VALUE
    local dind_volume_mount_count_VALUE
    local dind_volume_last_mount_ts_VALUE

    kubectl get pv -l 'codefresh-app in (dind,workspace)' -ogo-template="$TEMPLATE_GET_PV" | while read line
    do
       PV_NAME=$(echo "$line" | cut -f1)
       STORAGE_CLASS=$(echo "$line" | cut -f2)
       PHASE=$(echo "$line" | cut -f3)
       RECLAIM_POLICY=$(echo "$line" | cut -f4)
       MOUNT_COUNT=$(echo "$line" | cut -f5)
       LAST_MOUNT_TS=$(echo "$line" | cut -f7)
       BACKEND_VOLUME_TYPE=$(echo "$line" | cut -f8)
       BACKEND_VOLUME_ID=$(echo "$line" | cut -f9)
       
       POD_NAMESPACE=$(echo "$line" | cut -f12)
       POD_NAME=$(echo "$line" | cut -f13)
       RUNTIME_ENV=$(echo "$line" | cut -f14)
       ACCOUNT_NAME=$(echo "$line" | cut -f15)
       PIPELINE_ID=$(echo "$line" | cut -f16)
       BACKEND_VOLUME_ID_MD5=$(echo "$line" | cut -f17)
       
       case $PHASE in
           Pending)
              dind_volume_phase_VALUE="0"
           ;;
           Bound)
              dind_volume_phase_VALUE="1"
           ;;
           Released)
              dind_volume_phase_VALUE="2"
           ;;
           Failed)
              dind_volume_phase_VALUE="3"
           ;;
           Unknown)
              dind_volume_phase_VALUE="-1"
           ;;
           *)
       esac

       # dind_volume_mount_count_VALUE=${MOUNT_COUNT}

       dind_volume_last_mount_ts_VALUE=$(date -d ${LAST_MOUNT_TS} +%s ) || echo "Invalid LAST_MOUNT_TS for $PV_NAME"
       
       LABELS="pod_name=\"POD_NAME\",storage_class=\"${STORAGE_CLASS}\",reclaim_policy=\"${RECLAIM_POLICY}\",backend_volume_type=\"${BACKEND_VOLUME_TYPE}\",backend_volume_id=\"${BACKEND_VOLUME_ID}\",backend_volume_id_md5=\"${BACKEND_VOLUME_ID_MD5}\""
       
       for i in ${VOLUMES_METRICS[@]}; do
         local METRIC_VALUE=$(eval echo \$${i}_VALUE)
         local METRIC_TMP_FILE=$(eval echo \$METRICS_TMP_${i})
         if [[ -n "${METRIC_VALUE}" ]]; then
           echo "${i}{$LABELS} ${METRIC_VALUE}" >> ${METRIC_TMP_FILE}
         fi
       done

    done

}

while true; do

    create_metrics_headers

    get_dind_volumes_metrics

    for i in ${METRIC_NAMES[@]}; do
       eval mv \$METRICS_TMP_${i} \$METRICS_${i}
    done

   sleep $COLLECT_INTERVAL
done
