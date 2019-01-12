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
METRIC_NAMES=(dind_pvc_status dind_pod_status dind_pod_cpu_request \
         dind_volume_phase dind_volume_creation_ts dind_volume_mount_count dind_volume_last_mount_ts \ 
         dind_pvc_volume_phase dind_pvc_volume_creation_ts dind_pvc_volume_mount_count dind_pvc_volume_last_mount_ts )

for i in ${METRIC_NAMES[@]}; do
    eval METRICS_${i}="${METRICS_DIR}"/${i}.prom
    eval METRICS_TMP_${i}="${METRICS_DIR}"/${i}.prom.tmp.$$
    eval echo "$i metric collected to \$METRICS_${i} "
done

create_metrics_headers(){
        cat <<EOF > "${METRICS_TMP_dind_pvc_status}"
# TYPE dind_pvc_status gauge
# HELP dind_pvc_status - status of dind pvc: 0 - Pending, 1 - Bound, -1 - Lost
EOF

    cat <<EOF > "${METRICS_TMP_dind_pod_status}"
# TYPE dind_pod_status gauge
# HELP dind_pod_status - dind pod status 0 - Pending, 1 - Running, 2 - Succeded, 3 - Failed, -1 - Unknown
EOF

    cat <<EOF > "${METRICS_TMP_dind_pod_cpu_request}"
# TYPE dind_pod_cpu_request gauge
# HELP dind_pod_cpu_request pod cpu requests in mCpu
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_phase}"
# TYPE dind_volume_phase gauge
# HELP dind_volume_phase - volume phase 0 - Pending, 1 - Bound, 2 - Released, 3 - Failed, -1 - Unknown
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_creation_ts}"
# TYPE dind_volume_creation_ts gauge
# HELP dind_volume_creation_ts backend volume creation timestamp
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_mount_count}"
# TYPE dind_volume_mount_count gauge
# HELP dind_volume_mount_count volume mounts count
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_last_mount_ts}"
# TYPE dind_volume_last_mount_ts gauge
# HELP dind_volume_last_mount_ts volume last mount timestamp
EOF

    cat <<EOF > "${METRICS_TMP_dind_pvc_volume_phase}"
# TYPE dind_pvc_volume_phase gauge
# HELP dind_pvc_volume_phase - volume phase 0 - Pending, 1 - Bound, 2 - Released, 3 - Failed, -1 - Unknown
EOF

    cat <<EOF > "${METRICS_TMP_dind_pvc_volume_creation_ts}"
# TYPE dind_pvc_volume_creation_ts gauge
# HELP dind_pvc_volume_creation_ts backend volume creation timestamp
EOF

    cat <<EOF > "${METRICS_TMP_dind_pvc_volume_mount_count}"
# TYPE dind_pvc_volume_mount_count gauge
# HELP dind_pvc_volume_mount_count volume mounts count
EOF

    cat <<EOF > "${METRICS_TMP_dind_pvc_volume_last_mount_ts}"
# TYPE dind_pvc_volume_last_mount_ts gauge
# HELP dind_pvc_volume_last_mount_ts volume last mount timestamp
EOF
}


# echo "Debug exit " && exit 0
get_dind_pvc_metrics(){

    local LABEL_SELECTOR=${1:-'codefresh-app=dind'}

    local TEMPLATE_GET_PVC='{{range .items}}'
    TEMPLATE_GET_PVC+='{{.metadata.namespace}}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{.metadata.name}}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{.status.phase}}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{.spec.storageClassName}}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "pod_namespace" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "pod_name" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "runtime_env" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "account_name" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "pipeline_id" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{.metadata.annotations.workflow_url}}'
    TEMPLATE_GET_PVC+='{{"\n"}}{{end}}'

    local LABELS
    local PVC_NAMESPACE
    local PVC_NAME
    local PHASE
    local STORAGE_CLASS
    local POD_NAMESPACE
    local POD_NAME
    local RUNTIME_ENV
    local PVC_STATUS

    local TMP_FILE=/tmp/get_dind_pvc_metrics.tmp.$$
    ### Metric dind_pvc_status
    kubectl get pvc -a --all-namespaces -l "$LABEL_SELECTOR" -ogo-template="$TEMPLATE_GET_PVC" > ${TMP_FILE}
    cat ${TMP_FILE} | while read line
    do
       PVC_NAMESPACE=$(echo "$line" | cut -f1 )
       PVC_NAME=$(echo "$line" | cut -f2 )
       PHASE=$(echo "$line" | cut -f3)
       STORAGE_CLASS=$(echo "$line" | cut -f4)
       POD_NAMESPACE=$(echo "$line" | cut -f5)
       POD_NAME=$(echo "$line" | cut -f6)
       RUNTIME_ENV=$(echo "$line" | cut -f7)
       ACCOUNT_NAME=$(echo "$line" | cut -f8)
       PIPELINE_ID=$(echo "$line" | cut -f9)
       WORKFLOW_URL=$(echo "$line" | cut -f10)

       case $PHASE in
           Pending)
              PVC_STATUS="0"
           ;;
           Bound)
              PVC_STATUS="1"
           ;;
           Lost)
              PVC_STATUS="-1"
           ;;
           *)
              PVC_STATUS="-2"
           ;;
       esac
       LABELS="pvc_namespace=\"${PVC_NAMESPACE}\",pvc_name=\"${PVC_NAME}\",storage_class=\"${STORAGE_CLASS}\""
       LABELS+=",dind_pod_name=\"${POD_NAME}\",dind_pod_namespace=\"${POD_NAMESPACE}\""
       LABELS+=",runtime_env=\"${RUNTIME_ENV}\",account_name=\"${ACCOUNT_NAME}\",pipeline_id=\"${PIPELINE_ID}\",workflow_url=\"${WORKFLOW_URL}\""
       if [[ -n "${PVC_STATUS}" ]]; then
         echo "dind_pvc_status{$LABELS} ${PVC_STATUS}" >> ${METRICS_TMP_dind_pvc_status}
       fi
    done
}

get_dind_pod_status() {
    local LABEL_SELECTOR=${1:-'app in (dind,runtime)'}

    local TEMPLATE_GET_PODS='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{.status.phase}}{{"\t"}}{{(index .spec.containers 0).resources.requests.cpu}}{{"\t"}}{{.metadata.annotations.workflow_url}}{{"\t"}}{{ .spec.nodeName}}{{"\t"}}{{"\n"}}{{end}}'
    local POD_NAMESPACE
    local POD_NAME
    local PHASE
    local POD_STATUS
    local POD_CPU_REQUEST

    kubectl get pods -a --all-namespaces -l "${LABEL_SELECTOR}" -ogo-template="${TEMPLATE_GET_PODS}" | while read line
    do
       POD_NAMESPACE=$(echo "$line" | cut -f1)
       POD_NAME=$(echo "$line" | cut -f2)
       PHASE=$(echo "$line" | cut -f3)
       POD_CPU_REQUEST=$(echo "$line" | cut -f4)
       WORKFLOW_URL=$(echo "$line" | cut -f5)
       NODE_NAME=$(echo "$line" | cut -f6)

       case $PHASE in
           Pending)
              POD_STATUS="0"
           ;;
           Running)
              POD_STATUS="1"
           ;;
           Succeeded)
              POD_STATUS="2"
           ;;
           Failed)
              POD_STATUS="3"
           ;;
           Unknown)
              POD_STATUS="-1"
           ;;
           *)
              POD_STATUS="-2"
           ;;
       esac
       LABELS="dind_pod_namespace=\"${POD_NAMESPACE}\",dind_pod_name=\"${POD_NAME}\",dind_node_name=\"${NODE_NAME}\",workflow_url=\"${WORKFLOW_URL}\""
       if [[ -n "${POD_STATUS}" ]]; then
         echo "dind_pod_status{$LABELS} ${POD_STATUS}" >> ${METRICS_TMP_dind_pod_status}
       fi
       if [[ -n "${POD_CPU_REQUEST}" && ( ${POD_STATUS} == 0 || ${POD_STATUS} == 1 ) ]]; then
         echo "dind_pod_cpu_request{$LABELS} ${POD_CPU_REQUEST%m}" >> ${METRICS_TMP_dind_pod_cpu_request}
       fi
    done
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

    TEMPLATE_GET_PV+='{{"\t"}}{{- if .spec.local }}local{{"\t"}}{{ .spec.local.path }}'
    TEMPLATE_GET_PV+='  {{- else if .spec.rbd }}rbd{{"\t"}}{{ .spec.rbd.image }}'
    TEMPLATE_GET_PV+='  {{- else if .spec.awsElasticBlockStore }}ebs{{"\t"}}{{ .spec.awsElasticBlockStore.volumeID }}{{- end }}'

    TEMPLATE_GET_PV+='{{"\t"}}{{if .spec.claimRef }}{{index .spec.claimRef "name" }}{{ end}}'
    TEMPLATE_GET_PV+='{{"\t"}}{{if .spec.claimRef }}{{index .spec.claimRef "namespace" }}{{ end}}'

    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pod_namespace" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pod_name" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "runtime_env" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "account_name" }}'
    TEMPLATE_GET_PV+='{{"\t"}}{{index .metadata.labels "pipeline_id" }}'

    TEMPLATE_GET_PV+='{{"\n"}}{{end}}'

    local LABELS
    local LABELS_PVC
    local PV_NAME
    local STORAGE_CLASS    
    local PHASE
    local RECLAIM_POLICY
    local MOUNT_COUNT
    local VOLUME_CREATION_TS
    local LAST_MOUNT_TS
    local BACKEND_VOLUME_TYPE
    local BACKEND_VOLUME_ID

    local PVC_NAMESPACE
    local PVC_NAME
    local POD_NAMESPACE
    local POD_NAME
    local RUNTIME_ENV
    local ACCOUNT_NAME
    local PIPELINE_ID

    local VOLUMES_METRICS=(dind_volume_phase dind_volume_creation_ts dind_volume_mount_count dind_volume_last_mount_ts)
    local VOLUMES_PVC_METRICS=(dind_pvc_volume_phase dind_pvc_volume_creation_ts dind_pvc_volume_mount_count dind_pvc_volume_last_mount_ts)

    local dind_volume_phase_VALUE
    local dind_volume_creation_ts_VALUE
    local dind_volume_mount_count_VALUE
    local dind_volume_last_mount_ts_VALUE

    local dind_pvc_volume_phase_VALUE
    local dind_pvc_volume_creation_ts_VALUE
    local dind_pvc_volume_mount_count_VALUE
    local dind_pvc_volume_last_mount_ts_VALUE    

    kubectl get pv -l codefresh-app=dind -ogo-template="$TEMPLATE_GET_PV" | while read line
    do
       PV_NAME=$(echo "$line" | cut -f1)
       STORAGE_CLASS=$(echo "$line" | cut -f2)
       PHASE=$(echo "$line" | cut -f3)
       RECLAIM_POLICY=$(echo "$line" | cut -f4)
       MOUNT_COUNT=$(echo "$line" | cut -f5)
       VOLUME_CREATION_TS=$(echo "$line" | cut -f6)
       LAST_MOUNT_TS=$(echo "$line" | cut -f7)
       BACKEND_VOLUME_TYPE=$(echo "$line" | cut -f8)
       BACKEND_VOLUME_ID=$(echo "$line" | cut -f9)
       
       PVC_NAMESPACE=$(echo "$line" | cut -f10)
       PVC_NAME=$(echo "$line" | cut -f11)       
       POD_NAMESPACE=$(echo "$line" | cut -f12)
       POD_NAME=$(echo "$line" | cut -f13)
       RUNTIME_ENV=$(echo "$line" | cut -f14)
       ACCOUNT_NAME=$(echo "$line" | cut -f15)
       PIPELINE_ID=$(echo "$line" | cut -f16)
       
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
       dind_pvc_volume_phase_VALUE=${dind_volume_phase_VALUE}

       dind_volume_mount_count_VALUE=${MOUNT_COUNT}
       dind_pvc_volume_mount_count_VALUE=${dind_volume_mount_count_VALUE}

       dind_volume_creation_ts_VALUE=$(date -d ${VOLUME_CREATION_TS} +%s ) || echo "Invalid VOLUME_CREATION_TS for $PV_NAME"
       dind_pvc_volume_creation_ts_VALUE=${dind_volume_creation_ts_VALUE}

       dind_volume_last_mount_ts_VALUE=$(date -d ${LAST_MOUNT_TS} +%s ) || echo "Invalid LAST_MOUNT_TS for $PV_NAME"
       dind_pvc_volume_last_mount_ts_VALUE=${dind_volume_last_mount_ts_VALUE}
       
       LABELS="storage_class=\"${STORAGE_CLASS}\",reclaim_policy=\"${RECLAIM_POLICY}\",backend_volume_type=\"${BACKEND_VOLUME_TYPE}\",backend_volume_id=\"${BACKEND_VOLUME_ID}\""
       
       LABELS_PVC=${LABELS}
       LABELS_PVC+=",volume_name=\"${PV_NAME}\",pvc_namespace=\"${PVC_NAMESPACE}\",pvc_name=\"${PVC_NAME}\",storage_class=\"${STORAGE_CLASS}\""
       LABELS_PVC+=",dind_pod_name=\"${POD_NAME}\",dind_pod_namespace=\"${POD_NAMESPACE}\""
       LABELS_PVC+=",runtime_env=\"${RUNTIME_ENV}\",account_name=\"${ACCOUNT_NAME}\",pipeline_id=\"${PIPELINE_ID}\""

       for i in ${VOLUMES_METRICS[@]}; do
         local METRIC_VALUE=$(eval echo \$${i}_VALUE)
         local METRIC_TMP_FILE=$(eval echo \$METRICS_TMP_${i})
         if [[ -n "${METRIC_VALUE}" ]]; then
           echo "${i}{$LABELS} ${METRIC_VALUE}" >> ${METRIC_TMP_FILE}
         fi
       done

       for i in ${VOLUMES_PVC_METRICS[@]}; do
         local METRIC_VALUE=$(eval echo \$${i}_VALUE)
         local METRIC_TMP_FILE=$(eval echo \$METRICS_TMP_${i})
         if [[ -n "${METRIC_VALUE}" ]]; then
           echo "${i}{$LABELS_PVC} ${METRIC_VALUE}" >> ${METRIC_TMP_FILE}
         fi
       done

    #    #dind_volume_phase dind_volume_creation_ts dind_volume_mount_count dind_volume_last_mount_ts
    #    echo "dind_volume_phase{$LABELS} ${PHASE_VALUE}" >> ${METRICS_TMP_dind_volume_phase}
    #    echo "dind_volume_mount_count{$LABELS} ${MOUNT_COUNT}" >> ${METRICS_TMP_dind_volume_mount_count}
    #    echo "dind_volume_creation_ts{$LABELS} ${VOLUME_CREATION_TS_VALUE}" >> ${METRICS_TMP_dind_volume_creation_ts}
    #    echo "dind_volume_last_mount_ts{$LABELS} ${LAST_MOUNT_TS_VALUE}" >> ${METRICS_TMP_dind_volume_last_mount_ts}   

    done

}

while true; do

    create_metrics_headers

    get_dind_pvc_metrics 'codefresh-app=dind'

    get_dind_pod_status 'app in (dind,runtime)'
    get_dind_pod_status 'codefresh-app=dind'

    get_dind_volumes_metrics

    for i in ${METRIC_NAMES[@]}; do
       eval mv \$METRICS_TMP_${i} \$METRICS_${i}
    done

    # mv "${METRICS_TMP_dind_pvc_status}" "${METRICS_dind_pvc_status}"
    # mv "${METRICS_TMP_dind_pod_status}" "${METRICS_dind_pod_status}"
    # mv "${METRICS_TMP_dind_pod_cpu_request}" "${METRICS_dind_pod_cpu_request}"

   sleep $COLLECT_INTERVAL
done
