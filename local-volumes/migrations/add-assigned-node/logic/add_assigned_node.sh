#!/bin/bash

if [[ -z "${VOLUME_PARENT_DIR}" ]]; then
  echo "Error: missing dir path, export VOLUME_PARENT_DIR variable"
  exit 1
fi

if [[ -z "${NODE_NAME}" ]]; then
  echo "Error: missing node name, export NODE_NAME variable"
  exit 1
fi

MIGRATED_COUNTER=0

for vol_dir in $(find "${VOLUME_PARENT_DIR}" -mindepth 1 -maxdepth 1 -type d -name "vol-*")
do
  PV_NAME=$(cat ${vol_dir}/pv)
  PATCH="{\"metadata\":{\"annotations\":{\"codefresh.io/assignedNode\":\"$NODE_NAME\"}}}"
  RES=$(kubectl patch pv $PV_NAME -p $PATCH 2>&1)
  EXIT_CODE="$?"

  if echo $RES | grep -q '(NotFound)'; then
    continue
  fi

  echo $RES

  if [[ "0" -eq "$EXIT_CODE" ]]; then
    ((MIGRATED_COUNTER++))
  fi
done

echo "Successfully migrated $MIGRATED_COUNTER PVs"
