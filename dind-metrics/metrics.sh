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

METRICS_dind_pvc_status="${METRICS_DIR}"/dind_pvc_status.prom
METRICS_TMP_dind_pvc_status="${METRICS_DIR}"/dind_pvc_status.prom.tmp.$$

echo "dind_pvc_status metric collected to ${METRICS_dind_pvc_status} "

METRICS_dind_pod_status="${METRICS_DIR}"/dind_pod_status.prom
METRICS_TMP_dind_pod_status="${METRICS_DIR}"/dind_pod_status.prom.tmp.$$
echo "dind_pod_status metric collected to ${METRICS_dind_pod_status} "

METRICS_dind_volume_pod_status="${METRICS_DIR}"/dind_volume_pod_status.prom
METRICS_TMP_dind_volume_pod_status="${METRICS_DIR}"/dind_pod_volume_status.prom.tmp.$$
echo "dind_volume_pod_status metric collected to ${METRICS_dind_volume_pod_status} "

get_dind_pvc_metrics(){

    local METRIC_NAME=${1:-"pvc_status"}
    local LABEL_SELECTOR=${2:-'codefresh-app=dind'}

    local TEMPLATE_GET_PVC='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{.status.phase}}{{"\t"}}{{.spec.storageClassName}}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "pod_namespace" }}{{"\t"}}{{index .metadata.labels "pod_name" }}'
    TEMPLATE_GET_PVC+='{{"\t"}}{{index .metadata.labels "runtime_env" }}{{"\n"}}{{end}}'

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
       LABELS="pvc_namespace=\"${PVC_NAMESPACE}\",pvc_name=\"${PVC_NAME}\",storage_class=\"${STORAGE_CLASS}\",dind_pod_name=\"${POD_NAME}\",dind_pod_namespace=\"${POD_NAME}\",runtime_env=\"${RUNTIME_ENV}\""
       if [[ -n "${PVC_STATUS}" ]]; then
         echo "${METRIC_NAME}{$LABELS} ${PVC_STATUS}"
       fi
    done
}

get_dind_pod_status() {
    ### dind_pod_status
    local METRIC_NAME=${1:-"pod_status"}
    local LABEL_SELECTOR=${2:-'app in (dind,runtime)'}

    local TEMPLATE_GET_PODS='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{.status.phase}}{{"\t"}}{{"\n"}}{{end}}'
    local POD_NAMESPACE
    local POD_NAME
    local PHASE
    local POD_STATUS

    kubectl get pods -a --all-namespaces -l "${LABEL_SELECTOR}" -ogo-template="${TEMPLATE_GET_PODS}" | while read line
    do
       POD_NAMESPACE=$(echo "$line" | cut -f1)
       POD_NAME=$(echo "$line" | cut -f2)
       PHASE=$(echo "$line" | cut -f3)

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
       LABELS="dind_pod_namespace=\"${POD_NAMESPACE}\",dind_pod_name=\"${POD_NAME}\""
       if [[ -n "${POD_STATUS}" ]]; then
         echo "${METRIC_NAME}{$LABELS} ${POD_STATUS}"
       fi
    done
}


while true; do
    cat <<EOF > "${METRICS_TMP_dind_pvc_status}"
# TYPE dind_pvc_status gauge
# HELP dind_pvc_status - status of dind pvc: 0 - Pending, 1 - Bound, -1 - Lost
EOF

    cat <<EOF > "${METRICS_TMP_dind_pod_status}"
# TYPE dind_pod_status gauge
# HELP dind_pod_status - dind pod status 0 - Pending, 1 - Running, 2 - Succeded, 3 - Failed, -1 - Unknown
EOF

    cat <<EOF > "${METRICS_TMP_dind_volume_pod_status}"
# TYPE dind_volume_pod_status gauge
# HELP dind_volume_pod_status - dind volume pod status 0 - Pending, 1 - Running, 2 - Succeded, -1 - Unknown
EOF

    get_dind_pvc_metrics "dind_pvc_status" 'codefresh-app=dind' >> "${METRICS_TMP_dind_pvc_status}"
    get_dind_pod_status "dind_pod_status" 'app in (dind,runtime)' >> "${METRICS_TMP_dind_pod_status}"
    get_dind_pod_status "dind_volume_pod_status" 'codefresh-app=dind' >> "${METRICS_TMP_dind_volume_pod_status}"


    mv "${METRICS_TMP_dind_pvc_status}" "${METRICS_dind_pvc_status}"
    mv "${METRICS_TMP_dind_pod_status}" "${METRICS_dind_pod_status}"
    mv "${METRICS_TMP_dind_volume_pod_status}" "${METRICS_dind_volume_pod_status}"

   sleep $COLLECT_INTERVAL
done
