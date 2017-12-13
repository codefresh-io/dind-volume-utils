#!/usr/bin/env bash
#
#
VOLUME_PARENT_DIR=${VOLUME_PARENT_DIR:-/opt/codefresh/dind-volumes}
NODE_NAME=${NODE_NAME:-$(hostname)}
KB_USAGE_THRESHOLD=${KB_USAGE_THRESHOLD:-80}
INODE_USAGE_THRESHOLD=${INODE_USAGE_THRESHOLD:-80}

SLEEP_INTERVAL=${SLEEP_INTERVAL:-60}
LOG_DF_COUNTER=0
LOG_DF_EVERY=${LOG_DF_EVERY:-180}

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

get_volume_by_po() {
   TEMPLATE='{{range .items}}{{.metadata.name}}    {{index .metadata.annotations "codefresh.io/usedBy" }}{{"\n"}}{{end}}'

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
DIR_LIST_TMP=/tmp/dir-list.$$

display_df

while true
do

  VOLUMES_KB_USAGE=$(get_volume_kb_usage)
  VOLUMES_INODES_USAGE=$(get_volume_inode_usage)
  if [[ ${VOLUMES_KB_USAGE} -ge ${KB_USAGE_THRESHOLD} ||  ${VOLUMES_INODES_USAGE} -ge ${INODE_USAGE_THRESHOLD} ]]; then
     echo -e "\n!!!!!!!!!! THRESHOLD Reached - VOLUMES_KB_USAGE=${VOLUMES_KB_USAGE}>${KB_USAGE_THRESHOLD} or VOLUMES_INODES_USAGE=${VOLUMES_INODES_USAGE}>${INODE_USAGE_THRESHOLD}"
     [[ -f ${DIR_LIST_TMP} ]] && rm -f ${DIR_LIST_TMP}

     for ii in $(find "${VOLUME_PARENT_DIR}" -mindepth 1 -maxdepth 1 -type d -name "${VOLUME_DIR_PATTERN}")
     do
        DIR_NAME=$ii
        LAST_USED_POD=""
        CREATED="9999999999"
        LAST_USED="9999999999"
        # Look for Volume to delete
        if [[ -f ${DIR_NAME}/pods ]]; then
           LAST_USED_POD=$(awk '/dind/ {d=$1} END {print d}' < ${DIR_NAME}/pods)
        fi

        if [[ -z "${LAST_USED_POD}" ]]; then
           echo "ERROR - cannot get LAST_USED_POD for volume ${DIR_NAME} "
           continue
        fi

        if [[ -f ${DIR_NAME}/created ]]; then
           CREATED=$(awk 'END {print $1}' < ${DIR_NAME}/created)
        fi

        if [[ -f ${DIR_NAME}/last_used ]]; then
           LAST_USED=$(awk 'END {print $1}' < ${DIR_NAME}/last_used)
        fi

        echo "${DIR_NAME}"    "${LAST_USED_POD}"    "${CREATED}"    "${LAST_USED}" >> $DIR_LIST_TMP
     done

     if [[ -f ${DIR_LIST_TMP} ]]; then
        echo "WARNING: disk full, but there is not any valid local volume in ${VOLUME_PARENT_DIR} "
     else
        # Sorting dir_list file - taking oldest like
        VOLUME_CLEAN_CANDIDATE=$(sort -k3 -n ${DIR_LIST_TMP} | awk 'NR==1')

        echo "Trying to clean oldest volume - ${VOLUME_CLEAN_CANDIDATE} "
        LAST_USED_POD_TO_CLEAN=$(echo ${VOLUME_CLEAN_CANDIDATE} | cut -d' ' -f2)


     fi

  fi

  (( LOG_DF_COUNTER++ ))
  if [[ ${LOG_DF_COUNTER} -eq 180 ]]; then
     display_df
     LOG_DF_COUNTER=0
  fi

  sleep $SLEEP_INTERVAL
done
