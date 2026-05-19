#! /usr/bin/env bash

# Required preparation: ssh-copy-id to both hosts so that script can ssh into both nodes without pw prompt.
# If the repository is not public, you need to create access keys for the users on both nodes.
# Set 'AllowAgentForwarding yes' in /etc/ssh/sshd_config on the remote nodes.
# Add github.com to known host for remote node's user by trying to clone any repository.

# Exit the script immediately if an error occurs.
set -e

BUILD_DIR_NAME="buildAuto"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$1" ] ; then
  BRANCH="$1"
fi

echo "Branch to checkout on remote servers: ${BRANCH} (this repository's branch)"

# EMR
USER_HOST1="jotham@192.168.128.73"

# GNR
USER_HOST2="jotham@192.168.128.74"

# Per configuration tuple: <main workload>:<background workload>:<start delay both workload>:<finish background workload strategy>
configurations=(
  # EMR write offset 0 vs GNR read offset 0, 128G, 256G, 384G
  "25-emr-write-cxl-dax-offset-0:25-gnr-read-load-cxl-dax-offset-0-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-0:25-gnr-read-load-cxl-dax-offset-128GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-0:25-gnr-read-load-cxl-dax-offset-256GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-0:25-gnr-read-load-cxl-dax-offset-384GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"

  # EMR write offset 128GB vs GNR read offset 0, 128G, 256G, 384G
  "25-emr-write-cxl-dax-offset-128GB:25-gnr-read-load-cxl-dax-offset-0-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-128GB:25-gnr-read-load-cxl-dax-offset-128GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-128GB:25-gnr-read-load-cxl-dax-offset-256GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-128GB:25-gnr-read-load-cxl-dax-offset-384GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"

  # EMR write offset 256GB vs GNR read offset 0, 128G, 256G, 384G
  "25-emr-write-cxl-dax-offset-256GB:25-gnr-read-load-cxl-dax-offset-0-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-256GB:25-gnr-read-load-cxl-dax-offset-128GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-256GB:25-gnr-read-load-cxl-dax-offset-256GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-256GB:25-gnr-read-load-cxl-dax-offset-384GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"

  # EMR write offset 384GB vs GNR read offset 0, 128G, 256G, 384G
  "25-emr-write-cxl-dax-offset-384GB:25-gnr-read-load-cxl-dax-offset-0-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-384GB:25-gnr-read-load-cxl-dax-offset-128GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-384GB:25-gnr-read-load-cxl-dax-offset-256GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
  "25-emr-write-cxl-dax-offset-384GB:25-gnr-read-load-cxl-dax-offset-384GB-long:60:kill:${USER_HOST1}:${USER_HOST2}"
)

REPO_URL="https://github.com/JothamWong/cxlbench.git"
TARGET_DIR="cxlbench-multiserver"

USER_HOSTS=($USER_HOST1 $USER_HOST2)
NUM_HOSTS=${#USER_HOSTS[@]}

CLONE_CMD="if [ ! -d \"$TARGET_DIR\" ]; then git clone $REPO_URL $TARGET_DIR; else echo 'Skipping clone.'; fi"

# Delete
for (( i=0; i<$NUM_HOSTS; i++)); do
  USER_HOST="${USER_HOSTS[$i]}"
  echo "Delete dir ($USER_HOST)"
  ssh ${USER_HOST} "rm -rf ~/$TARGET_DIR" &
done
wait
echo "Delete done"

# Clone
for (( i=0; i<$NUM_HOSTS; i++)); do
  USER_HOST="${USER_HOSTS[$i]}"
  echo "Setup ($USER_HOST)"
  ssh ${USER_HOST} "$CLONE_CMD" &
done
wait
echo "Clone done"

# Build
for (( i=0; i<$NUM_HOSTS; i++)); do
  USER_HOST="${USER_HOSTS[$i]}"
  echo "Build ($USER_HOST)"
  ssh ${USER_HOST} "cd $TARGET_DIR && git checkout "$BRANCH" && ./scripts/build.sh $BUILD_DIR_NAME" &
done
wait
echo "Build done"

# Prepare and run workloads
for config in "${configurations[@]}"; do
  IFS=":" read -r workload background_workload start_delay bg_mode user_host_main user_host_background <<< "$config"
  echo "Workload: $workload | Load workload: $background_workload | Start delay [s]: $start_delay | Background workload finish: $bg_mode | User Host Workload: $user_host_main | User Host Background Workload: $user_host_background"
  if ssh ${user_host_main} "pgrep -fa 'cxlbench -r' | grep -v pgrep"; then
    echo "${TARGET_DIR} is running (${user_host_main}). Exiting script."
    exit 1
  fi
  if ssh ${user_host_background} "pgrep -fa 'cxlbench -r' | grep -v pgrep"; then
    echo "${TARGET_DIR} is running (${user_host_background}). Exiting script."
    exit 1
  fi
  START_TIME=$(eval date "+%FT%H-%M-%S-%N")
  RESULT_DIRS=("~/results-cxlbench-multiserver/${workload}_${background_workload}/$START_TIME" "~/results-cxlbench-multiserver/${workload}_${background_workload}/$START_TIME")
  LOG_FILES=("${RESULT_DIRS[0]}/execution.log" "${RESULT_DIRS[1]}/execution.log")

  # Prepare workloads and create result dirs
  if [[ "$workload" != "none" ]]; then
    ssh ${user_host_main} "cd $TARGET_DIR/$BUILD_DIR_NAME && ../scripts/reset_workload.sh $workload" \
      "&& mkdir -p ${RESULT_DIRS[0]}" &
  fi

  if [[ "$background_workload" != "none" ]]; then
    ssh ${user_host_background} "cd $TARGET_DIR/$BUILD_DIR_NAME && ../scripts/reset_workload.sh $background_workload" \
      "&& mkdir -p ${RESULT_DIRS[1]}" &
  fi
  wait
  echo "Workload config done & result directories created."

  # Run workloads
  echo "Running workload ..."

  # Set start timestamp
  if [[ "$start_delay" == 0 ]]; then
    start_timestamp_ms=0
  else
    start_timestamp_ms=$(date -d "+${start_delay} seconds" +%s%3N)
  fi

  if [[ "$background_workload" != "none" ]]; then
    echo "Running load generating background workload"
    BACKGROUND_WORKLOAD_PID=$(ssh "${user_host_background}" "
      cd $TARGET_DIR/$BUILD_DIR_NAME && \
      { ./cxlbench -r ${RESULT_DIRS[1]} -s $start_timestamp_ms -d ${start_delay} > ${LOG_FILES[1]} 2>&1 & echo \$!; }
    ")
    echo "PID for background workload (${user_host_background}): $BACKGROUND_WORKLOAD_PID"
  fi

#  sleep $seconds_delay

  if [[ "$workload" != "none" ]]; then
    echo "Running main workload"
    echo "${RESULT_DIRS[0]}"
    WORKLOAD_PID=$(ssh ${user_host_main} "
      cd $TARGET_DIR/$BUILD_DIR_NAME && \
      { ./cxlbench -r ${RESULT_DIRS[0]} -s $start_timestamp_ms -d ${start_delay} > ${LOG_FILES[0]} 2>&1 & echo \$!; }
    ")
    echo "PID for main workload (${user_host_main}): $WORKLOAD_PID"
  fi

  if [[ -n "$WORKLOAD_PID" ]]; then
    # Wait for completion of main workload
    ssh ${user_host_main} "while kill -0 $WORKLOAD_PID 2>/dev/null; do sleep 5; done"
    echo "Workload execution done"
  fi

  if [[ -n "$BACKGROUND_WORKLOAD_PID" ]]; then
    if [[ "$bg_mode" == "kill" ]]; then
      # Kill load workload
      ssh "${user_host_background}" "kill -9 $BACKGROUND_WORKLOAD_PID 2>/dev/null"
      echo "Killed background workload"
    elif [[ "$bg_mode" == "wait" ]]; then
      # Wait for completion of background workload
      ssh ${user_host_background} "while kill -0 $BACKGROUND_WORKLOAD_PID 2>/dev/null; do sleep 5; done"
      echo "Workload execution done"
    else
      echo "Unknown mode for deadling with background workload: ${bw_mode}"
      exit 1
    fi
  fi

  echo "Retrieving results..."
  local_results_dir="./results"
  host_main_name=$(echo "${user_host_main}" | cut -d'@' -f2)
  host_bg_name=$(echo "${user_host_background}" | cut -d'@' -f2)

  if [[ "$workload" != "none" ]]; then
    mkdir -p "${local_results_dir}/${host_main_name}/${workload}_${background_workload}/$START_TIME"
    rsync -avz "${user_host_main}:${RESULT_DIRS[0]}/" "${local_results_dir}/${host_main_name}/${workload}_${background_workload}/$START_TIME/"
  fi

  if [[ "$background_workload" != "none" ]]; then
    mkdir -p "${local_results_dir}/${host_bg_name}/${workload}_${background_workload}/$START_TIME"
    rsync -avz "${user_host_background}:${RESULT_DIRS[1]}/" "${local_results_dir}/${host_bg_name}/${workload}_${background_workload}/$START_TIME/"
  fi
done

cleanup() {
  if [[ -n "$BACKGROUND_WORKLOAD_PID" ]]; then
    ssh "${USER_HOST2}" "kill -9 $BACKGROUND_WORKLOAD_PID 2>/dev/null"
  fi

  if [[ -n "$WORKLOAD_PID" ]]; then
    ssh "${USER_HOST1}" "kill -9 $WORKLOAD_PID 2>/dev/null"
  fi

  ssh "${USER_HOST1}"
}

trap cleanup SIGINT SIGTERM EXIT
kill 0
