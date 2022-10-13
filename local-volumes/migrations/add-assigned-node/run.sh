#!/bin/bash

VOLUME_PARENT_DIR="/var/lib/codefresh/dind-volumes"

if [[ -z "${MIGRATOR_IMAGE}" ]]; then
  MIGRATOR_IMAGE="quay.io/codefresh/lv-pv-migrator:latest"
fi

if [[ -z "${NAMESPACE}" ]]; then
  echo "Error: missing namespace, export NAMESPACE variable"
  exit 1
fi

echo "Using kube context: '$(kubectl config current-context)'"
echo "Using node label selector: '${NODE_LABEL_SELECTOR}'"
echo "Using namespace: '${NAMESPACE}'"
echo "Using migrator image: '${MIGRATOR_IMAGE}'"

echo "==="

run_on_node() {
  local node_name="$1"
  echo "running on node $node_name"

  local res=$(echo "
  apiVersion: v1
  kind: Pod
  metadata:
    generateName: lv-pv-migrator-
    namespace: $NAMESPACE
    labels:
      app.kubernetes.io/name: lv-pv-migrator
  spec:
    containers:
      - name: pv-migrator
        image: $MIGRATOR_IMAGE
        imagePullPolicy: Always
        env:
          - name: VOLUME_PARENT_DIR
            value: ${VOLUME_PARENT_DIR}
          - name: NODE_NAME
            valueFrom:
              fieldRef:
                fieldPath: spec.nodeName
        volumeMounts:
          - mountPath: ${VOLUME_PARENT_DIR}
            name: dind-volume-dir
    serviceAccountName: volume-provisioner-runner
    restartPolicy: Never
    nodeName: $node_name
    volumes:
    - hostPath:
        path: ${VOLUME_PARENT_DIR}
        type: ""
      name: dind-volume-dir
  " | kubectl create -f -)

  local pod_name=$(echo "$res" | sed s@pod/@@ | sed s@\ created@@)
  echo "created pod: $pod_name, waiting for logs..."

  for (( i=1; i<=15; i++ ))
  do
    if eval kubectl logs -f -n $NAMESPACE $pod_name > /dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
  kubectl logs -f -n $NAMESPACE $pod_name
  echo "<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
}

# Get nodes
if [[ -z "${NODE_LABEL_SELECTOR}" ]]; then
  RES=`kubectl get nodes 2>&1`
else
  RES=`kubectl get nodes -l ${NODE_LABEL_SELECTOR} 2>&1`
fi

if [[ "$RES" == "No resources found" ]]; then
  echo "Error: No nodes found"
  exit 1
fi

NODE_COUNTER=0
NODES=$(echo "$RES" | awk 'NR!=1 {print $1}')
for node in $NODES
do
  run_on_node $node
  ((NODE_COUNTER++))
done

echo "Done migrating local volume PVs on ${NODE_COUNTER} nodes!"
