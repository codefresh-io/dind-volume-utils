#!/usr/bin/env bash
#
# Script deletes dind local volumes if disk space or inode usage reaches the threshold
#
# If everything ok, a volume should be deleted by dind-volume-provisioner
# dind-volume-provisioner submits deletion pod a volume has:
#  - persistentVolumeReclaimPolicy=Delete
#  - annotation node_requested_deletion=<current-node-name>
#
# But we should also consider cases when volume is set for deletion, but actually it still exists
# So the script does that:
#
# We will loop in all folders in VOLUME_PARENT_DIR matched the pattern
# For each folder we are checking named files with special meaning: deleted, pods, last_used, created
#   vol-xxxxxx/deleted - this script puts here deletion timestamp. so if it exists and 600s passed since its deletions
#                        something going wrong and we just delete it by rm -rf
#   vol-xxxxxx/created - creation timestamp, we use it for sorting
#   vol-xxxxxx/last_used - last_used timestamp

# 1. If we see deleted and its context (delete timestamp) is more than 10min past now, we delete it by rm -rf and continue
# 2. Write all candidates for deletion to VOLUMES_TO_DELETE_LIST tmp file
# 3. Sort VOLUMES_TO_DELETE_LIST by created date, writed "deleted" file and pass first of them to delete_local_volume
# 4. Continue loop, so if we deleted one volume and disk usage returned to normal, we dont need to delete more

# Debuging / Tesing env:
#DRY_RUN=1
#SLEEP_INTERVAL=3
#LOG_DF_EVERY=60
#KB_USAGE_THRESHOLD=10



VOLUME_PARENT_DIR=${VOLUME_PARENT_DIR:-/opt/codefresh/dind-volumes}
NODE_NAME=${NODE_NAME:-$(hostname)}
KB_USAGE_THRESHOLD=${KB_USAGE_THRESHOLD:-80}
INODE_USAGE_THRESHOLD=${INODE_USAGE_THRESHOLD:-80}
DELETE_BY_RM_AFTER=${DELETE_BY_RM_AFTER:-7200}

SLEEP_INTERVAL=${SLEEP_INTERVAL:-60}
LOG_DF_COUNTER=0
LOG_DF_EVERY=${LOG_DF_EVERY:-1800}

VOLUME_DIR_PATTERN=${VOLUME_DIR_PATTERN:-"vol-*"}

if [[ $(uname) == "Linux" ]]; then
   DF_OPTS="-B 1024"
else
   DRY_RUN=1
fi

if [[ ! -d ${VOLUME_PARENT_DIR} ]]; then
  echo "Directory ${VOLUME_PARENT_DIR} does not exists - creating ..."
  mkdir -p ${VOLUME_PARENT_DIR}
fi

echo "Stating $0 at $(date) at node $NODE_NAME "

debug_trap(){
  # Just switch debug on/off on SIGUSR1

  if [[ -z "${DEBUG}" ]]; then
     echo "debug_trap: Switching DEBUG ON"
     DEBUG="1"
  else
     echo "debug_trap: Switching DEBUG OFF"
     unset DEBUG
  fi
}
trap debug_trap SIGUSR1

pause_trap(){
  if [[ -z "${PAUSE}" ]]; then
     echo "pause_trap: Switching PAUSE ON"
     PAUSE="1"
  else
     echo "pause_trap: Switching PAUSE ON"
     unset PAUSE
  fi
}
trap pause_trap SIGUSR2

debug(){
  if [[ -n "${DEBUG}" ]]; then
    echo -e $1
  fi
}

display_df(){
    echo -e "\nCurrent disk space usage of $VOLUME_PARENT_DIR at $(date) is: "
    df ${VOLUME_PARENT_DIR}

    echo -e"\nCurrent inode usage of $VOLUME_PARENT_DIR at $(date)  is: "
    df -i ${VOLUME_PARENT_DIR}

    echo "---------------------"
}

get_volume_kb_usage(){
   df ${DF_OPTS} ${VOLUME_PARENT_DIR} | awk 'NR==2 {printf "%d", $3 / $2 * 100}'
}

get_volume_inode_usage(){
   df -i ${DF_OPTS} ${VOLUME_PARENT_DIR} | awk 'NR==2 {printf "%d", $3 / $2 * 100}'
}

get_volume_by_path() {
   local VOLUME_PATH=$1
   TEMPLATE='{{range .items}}{{.metadata.name}}    {{ .spec.local.path }}{{"\n"}}{{end}}'
   if [[ -z "${DRY_RUN}" ]]; then
      VOLUME_NAME=$(kubectl get pv -l codefresh-app=dind -ogo-template="$TEMPLATE" | awk -v volume_path=${VOLUME_PATH} '$2 == volume_path {print $1}')
   else
      VOLUME_NAME=$(basename ${VOLUME_PATH})
   fi
   echo ${VOLUME_NAME}
}

delete_local_volume() {
   # Here we just annotate pod with node_name and set persistentVolumeReclaimPolicy to delete
   local VOLUME_NAME=$1
   echo -e "\n---------------\nDeleting volume ${VOLUME_NAME} on node ${NODE_NAME} "
   KUBECTL=kubectl
   if [[ -n "${DRY_RUN}" ]]; then
      echo "DRY_RUN mode - just echo kubectl commands"
      KUBECTL="echo kubectl"
   fi

   $KUBECTL annotate pv ${VOLUME_NAME} node_requested_deletion="${NODE_NAME}" || (echo "Cannot Annotate volume ${VOLUME_NAME} " && return 1 )
   $KUBECTL patch pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}' ${VOLUME_NAME} || (echo "Cannot Patch volume ${VOLUME_NAME} " && return 1 )
}

# we will loop for all directories
VOLUMES_TO_DELETE_LIST=/tmp/dir-list.$$

display_df

echo "
DRY_RUN=${DRY_RUN}
VOLUME_PARENT_DIR=${VOLUME_PARENT_DIR}
NODE_NAME=${NODE_NAME}
KB_USAGE_THRESHOLD=${KB_USAGE_THRESHOLD}
INODE_USAGE_THRESHOLD=${INODE_USAGE_THRESHOLD}
DELETE_BY_RM_AFTER=${DELETE_BY_RM_AFTER}

SLEEP_INTERVAL=${SLEEP_INTERVAL}
LOG_DF_EVERY=${LOG_DF_EVERY}
VOLUME_DIR_PATTERN=${VOLUME_DIR_PATTERN}
"

while true
do
  if [[ -n "${PAUSE}" ]]; then
     echo "$0 Paused - send SIGUSR2 to resume"
     sleep ${SLEEP_INTERVAL}
     continue
  fi

  VOLUMES_KB_USAGE=$(get_volume_kb_usage)
  VOLUMES_INODES_USAGE=$(get_volume_inode_usage)
  debug "date: $(date) -  VOLUMES_KB_USAGE=${VOLUMES_KB_USAGE} of threshold ${KB_USAGE_THRESHOLD}% , VOLUMES_INODES_USAGE=${VOLUMES_INODES_USAGE} of threshold ${INODE_USAGE_THRESHOLD}% "
  if [[ ${VOLUMES_KB_USAGE} -ge ${KB_USAGE_THRESHOLD} || ${VOLUMES_INODES_USAGE} -ge ${INODE_USAGE_THRESHOLD} ]]; then
     echo -e "\n!!!!!!!!!! THRESHOLD Reached - VOLUMES_KB_USAGE=${VOLUMES_KB_USAGE}>${KB_USAGE_THRESHOLD} or VOLUMES_INODES_USAGE=${VOLUMES_INODES_USAGE}>${INODE_USAGE_THRESHOLD}"
     echo "Current date: $(date) , timestamp = $(date +%s) "
     [[ -f ${VOLUMES_TO_DELETE_LIST} ]] && rm -f ${VOLUMES_TO_DELETE_LIST}

     NORMAL_DELETE_FAILED=""
     for ii in $(find "${VOLUME_PARENT_DIR}" -mindepth 1 -maxdepth 1 -type d -name "${VOLUME_DIR_PATTERN}")
     do
        DIR_NAME=$ii

        # Check if we have already deleted this volume using  delete_local_volume()
        if [[ -f ${DIR_NAME}/deleted ]]; then
          echo "WARNING: volume ${DIR_NAME} marked for deletion but still exists"
          DELETION_DATE=$(cat ${DIR_NAME}/deleted)
          DELETED_DIFF=$(( $(date +%s) - DELETION_DATE ))
          [[ $? != 0 || -z "${DELETED_DIFF}" ]] && DELETED_DIFF=999999
          echo "DELETION_DATE=${DELETION_DATE} , so it was deleted ${DELETED_DIFF} seconds ago"
          if [[ ${DELETED_DIFF} -gt ${DELETE_BY_RM_AFTER} ]]; then
             echo "WARNING: volume ${DIR_NAME} was deleted more then ${DELETE_BY_RM_AFTER}s ago, so something went wrong"
             # Commented the below - will alert
#             echo "deleting by rm -rf ${DIR_NAME}"
#             RM=rm
#             if [[ -n "${DRY_RUN}" ]]; then
#                echo "DRY_RUN mode - just echo rm commands"
#                RM="echo rm"
#             fi
#
#             $RM -rf ${DIR_NAME}
#             NORMAL_DELETE_FAILED="Y"
#             break
#          else
#             continue
          fi
        fi

        CREATED="9999999999"
        LAST_USED="9999999999"

        # Look for Volume to delete

        if [[ -f ${DIR_NAME}/created ]]; then
           CREATED=$(awk 'END {print $1}' < ${DIR_NAME}/created)
        fi

        if [[ -f ${DIR_NAME}/last_used ]]; then
           LAST_USED=$(awk 'END {print $1}' < ${DIR_NAME}/last_used)
        fi

        echo "${DIR_NAME}"    "${CREATED}"    "${LAST_USED}" >> $VOLUMES_TO_DELETE_LIST
     done


     if [[ ! -f ${VOLUMES_TO_DELETE_LIST} ]]; then
        echo "WARNING: disk full, but there is not any valid local volume in ${VOLUME_PARENT_DIR} "
     elif [[ -n "${NORMAL_DELETE_FAILED}" ]]; then
        echo "WARNING: we just deleted some volume by rm -rf, so continue to main loop"
        sleep 10
        continue
     else
        # Sorting dir_list file - taking oldest like
        #VOLUME_CLEAN_DATA=$(sort -k3 -n ${DIR_LIST_TMP} | awk 'NR==1')

        echo "Trying to clean oldest volume first "
        sort -k2 -n ${VOLUMES_TO_DELETE_LIST} | while read VOLUME_DELETE_DATA
        do
            echo "    marking for deletion volume_data: ${VOLUME_DELETE_DATA} "
            VOLUME_PATH=$(echo ${VOLUME_DELETE_DATA} | cut -d' ' -f1)
            echo "        dir ${VOLUME_PATH} , getting volume to delete"
            echo "    marking for deletion volume_data: ${VOLUME_DELETE_DATA} - by timestamp $(date +%s)"
            if [[ -n ${DRY_RUN} ]]; then
              echo "date +%s > ${VOLUME_PATH}/deleted"
            else
              date +%s > ${VOLUME_PATH}/deleted
            fi

            VOLUME_TO_DELETE=$(get_volume_by_path ${VOLUME_PATH} )
            if [[ $? != 0 || -z "${VOLUME_TO_DELETE}" ]]; then
              echo "WARNING: cannot get persistentVolume by pod ${LAST_USED_POD_TO_DELETE} "
              continue
            fi
            delete_local_volume ${VOLUME_TO_DELETE}
            if [[ $? == 0 ]]; then
              echo "volume ${VOLUME_TO_DELETE} submitted for deletion to dind-volume-provisioner, we break the loop"
              break
            fi
        done
     fi
  fi

  (( LOG_DF_COUNTER++ ))
  if [[ ${LOG_DF_COUNTER} -eq 180 ]]; then
     display_df
     LOG_DF_COUNTER=0
  fi

  sleep $SLEEP_INTERVAL
done
