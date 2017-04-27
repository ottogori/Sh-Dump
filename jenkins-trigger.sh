#!/bin/bash -e

# GLOBALS
#--------
JENKINS_SERVER=
JOB_NAME=
JENKINS_USERNAME=
TOKEN=
BUILD_NUMBER=
TIMEOUT=30
MONITOR_QUERY_INTERVAL=5

# Parse Args
#-----------
while [[ $# -gt 0 ]]
do
  key="$1"
  case $key in
      -s|--server)
        JENKINS_SERVER="$2"
        shift # past argument
        ;;
      -j|--job)
        JOB_NAME="$2"
        shift # past argument
        ;;
      -u|--user)
        JENKINS_USERNAME="$2"
        shift # past argument
        ;;
      --t|--token)
        TOKEN="$2"
        shift
        ;;
      --timeout)
        TIMEOUT="$2"
        shift
        ;;
      --debug)
        set -x
        ;;
      *)
        # unknown option
      ;;
  esac
  shift # past argument or value
done

# Validate Args
#--------------
if [ -z ${JENKINS_SERVER+x} ] || [ -z ${JOB_NAME+x} ] || [ -z ${JENKINS_USERNAME+x} ] || [ -z ${TOKEN+x} ]; then
  echo " "
  echo "  usage: $0 --server [server ip] --job [job name] --user [username] --token [token]"
  echo "  optional parameters: --timeout [timeout in seconds]"
  echo " "
  exit 1
fi

start_time=$(date +%s)

# Trigger build
#--------------

build_url=$JENKINS_SERVER/job/$JOB_NAME/build?delay=0sec

echo " "
echo "  Building job $JOB_NAME at $JENKINS_SERVER"
echo " "

curl -f --silent -X POST $build_url --user $JENKINS_USERNAME:$TOKEN \
  ||   echo "  Failed to get trigger build at $status_url" \
    && echo "  " \
    && exit 2

# Fetch build number
#-------------------

build_number_url=$JENKINS_SERVER/job/$JOB_NAME/api/json
query_string="tree=builds[number,building,result]{0}"

output=$(curl -f --data-urlencode $query_string --silent "$build_number_url" --user $JENKINS_USERNAME:$TOKEN)

if [ $? -ne 0 ]; then
  echo "  Failed to fetch build number at $build_number_url"
  echo " "
  exit 2
fi

BUILD_NUMBER=$(echo $output | sed -E 's/.+"number":([^,]+),.+/\1/g')
building=$(echo $output | sed -E 's/.+"building":([^,]+),.+/\1/g')
result=$(echo $output | sed -E 's/.+"result":([^,]+),.+/\1/g')

if [ -z $BUILD_NUMBER ]; then
  echo "  Failed to parse build number from json output [$output] "
  echo " "
  exit 2
fi

# Monitor status
#---------------

status_url=$JENKINS_SERVER/job/$JOB_NAME/$BUILD_NUMBER/api/json?tree=result

echo "  Waiting for job to complete..."
echo " "

while
  sleep $MONITOR_QUERY_INTERVAL
  output=$(curl -f --silent $status_url --user $JENKINS_USERNAME:$TOKEN)
  
  if [ $? -ne 0 ]; then
    echo "  Failed to get updated job status at $status_url"
    echo "  "
    exit 2
  fi
  
  echo $output | grep result\":\"SUCCESS\" > /dev/null
  successful=$?
  
  echo $output | grep result\":\"FAILURE\" > /dev/null
  failed=$?
  
  time=$(date +%s)
  (( $successful && $failed && $time - $start_time < $TIMEOUT ))
do :; done

# Echo output
#------------

if (( !$failed )); then
  echo "  Job execution failed "
  echo "  "
  exit 1
else
  echo "  Job executed successfully "
  echo "  "
  exit 0
fi