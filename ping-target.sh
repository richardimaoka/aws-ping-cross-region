#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

#######################################################
# Step 1: Parse options and error check
#######################################################
for OPT in "$@"
do
  case "$OPT" in
    '--target-region' )
      if [ -z "$2" ]; then
          echo "option --target-region requires an argument -- $1" 1>&2
          exit 1
      fi
      TARGET_REGION="$2"
      shift 2
      ;;
    '--target-ip' )
      if [ -z "$2" ]; then
          echo "option --target-ip requires an argument -- $1" 1>&2
          exit 1
      fi
      TARGET_IP="$2"
      shift 2
      ;;
    '--target-instance' )
      if [ -z "$2" ]; then
          echo "option --target-instance requires an argument -- $1" 1>&2
          exit 1
      fi
      TARGET_INSTANCE_ID="$2"
      shift 2
      ;;
    '--s3-bucket' )
      if [ -z "$2" ]; then
          echo "option --s3-bucket requires an argument -- $1" 1>&2
          exit 1
      fi
      S3_BUCKET_NAME="$2"
      shift 2
      ;;
    '--test-uuid' )
      if [ -z "$2" ]; then
          echo "option --test-uuid requires an argument -- $1" 1>&2
          exit 1
      fi
      TEST_EXECUTION_UUID="$2"
      shift 2
      ;;
    -*)
      echo "illegal option -- $1" 1>&2
      exit 1
      ;;
  esac
done

if [ -z "${TARGET_REGION}" ] ; then
  echo "ERROR: Option --target-region needs to be specified"
  ERROR="1"
fi
if [ -z "${TARGET_IP}" ] ; then
  echo "ERROR: Option --target-ip needs to be specified"
  ERROR="1"
fi
if [ -z "${TARGET_INSTANCE_ID}" ] ; then
  echo "ERROR: Option --target-instance needs to be specified"
  ERROR="1"
fi
if [ -z "${TEST_EXECUTION_UUID}" ] ; then
  echo "ERROR: Option --test-uuid needs to be specified"
  ERROR="1"
fi
if [ -z "${S3_BUCKET_NAME}" ] ; then
  echo "ERROR: Option --s3-bucket needs to be specified"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

echo "TARGET_REGION=${TARGET_REGION}"
echo "TARGET_IP=${TARGET_IP}"
echo "TARGET_INSTANCE_ID=${TARGET_INSTANCE_ID}"
echo "TEST_EXECUTION_UUID=${TEST_EXECUTION_UUID}"
echo "S3_BUCKET_NAME=${S3_BUCKET_NAME}"

##########################################################
# Info about self
##########################################################
SOURCE_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
SOURCE_INSTANCE_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.instanceId')
echo "SOURCE_REGION=${SOURCE_REGION}"
echo "SOURCE_INSTANCE_ID=${SOURCE_INSTANCE_ID}"

##########################################################
# Step 2: Generate the json from ping result and metadata
##########################################################
echo "Start pinging the target, and saving to a file, ping_result.json"
ping -c 30 "${TARGET_IP}" | ping-to-json/ping_to_json.sh > ping_result.json

echo "Saving the metadata to a file, ping_metadata.json"
echo "{ \"metadata\": {\"source_region\": \"${SOURCE_REGION}\", \"target_region\": \"${TARGET_REGION}\", \"test_uuid\": \"${TEST_EXECUTION_UUID}\"  } }" | ping_metadata.json

#######################################################
# Step 3: Merge the json files and upload to S3
#######################################################
echo "Merging ping_result.json nd ping_metadata.json into result-from-${SOURCE_REGION}-to-${TARGET_REGION}.log.json"
jq -s '.[0] * .[1]' ping_result.json ping_metadata.json | jq -c "." > "result-from-${SOURCE_REGION}-to-${TARGET_REGION}.log"

#######################################################
# Step 4: move the result file to S3
#######################################################
echo "------------------------------------------------"
echo "Copying result-from-${SOURCE_REGION}-to-${TARGET_REGION}.log to s3://${S3_BUCKET_NAME}/aws-ping-cross-region/${TEST_EXECUTION_UUID}/"
aws s3 cp \
  "result-from-${SOURCE_REGION}-to-${TARGET_REGION}.log" \
  "s3://${S3_BUCKET_NAME}/aws-ping-cross-region/${TEST_EXECUTION_UUID}/result-from-${SOURCE_REGION}-to-${TARGET_REGION}.log"

