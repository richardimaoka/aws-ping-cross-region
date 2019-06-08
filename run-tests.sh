#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

TEST_EXECUTION_UUID=$(uuidgen)
S3_BUCKET_NAME="samplebucket-richardimaoka-sample-sample"
for OPT in "$@"
do
    case "$OPT" in
      '--stack-name' )
        if [ -z "$2" ]; then
            echo "option --stack-name requires an argument -- $1" 1>&2
            exit 1
        fi
        STACK_NAME="$2"
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
      '-f' | '--file-name' )
        if [ -z "$2" ]; then
            echo "option -f or --file-name requires an argument -- $1" 1>&2
            exit 1
        fi
        FILE_NAME="$2"
        shift 2
        ;;
    esac
done

#################################
# 1. Prepare the input json
#################################
if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: option --stack-name needs to be passed"
  ERROR="1"
fi
if [ -z "${FILE_NAME}" ] ; then
  if ! EC2_INPUT_JSON=$(./generate-ec2-input-json.sh); then 
    >&2 echo "ERROR: Failed to generate the input json with ./generate-ec2-input-json.sh"
    ERROR="1"
  fi
else
  if ! EC2_INPUT_JSON=$(jq -r "." < "${FILE_NAME}"); then
    >&2 echo "ERROR: Failed to read input JSON from ${FILE_NAME}"
    ERROR="1"
  fi
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

######################################################
# 2. regions
######################################################
# The $REGION_PAIRS variable to hold text like below, delimited by new lines, split by a whitespace:
#   >ap-northeast-2 eu-west-2
#   >ap-northeast-2 eu-west-1
#   >ap-northeast-2 ap-northeast-1
#   >...
#   >sa-east-1 eu-north-1
#   >sa-east-1 eu-west-1
#   >...
REGIONS=$(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
REGIONS_INNER_LOOP=$(echo "${REGIONS}") # to avoid the same pair appear twice
TEMPFILE=$(mktemp)
for REGION1 in $REGIONS
do
  REGIONS_INNER_LOOP=$(echo "${REGIONS_INNER_LOOP}" | grep -v "${REGION1}")
  for REGION2 in $REGIONS_INNER_LOOP
  do
    echo "${REGION1} ${REGION2}" >> "${FILENAME}"
  done
done

######################################################
# 3. main loop
######################################################
# Pick up one region pair at a time
# REGION_PAIRS will remove the picked-up element at the end of an iteration
REGION_PAIRS=$(cat "${TEMPFILE}")
while PICKED_UP=$(echo "${REGION_PAIRS}" | shuf -n 1) && [ -n "${PICKED_UP}" ]
do
  SOURCE_REGION=$(echo "${PICKED_UP}" | awk '{print $1}')
  TARGET_REGION=$(echo "${PICKED_UP}" | awk '{print $2}')

  echo "PAIR: ${SOURCE_REGION} ${TARGET_REGION}"

  SOURCE_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:experiment-name,Values=${STACK_NAME}" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text \
    --region "${SOURCE_REGION}"
  )
  TARGET_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:experiment-name,Values=${STACK_NAME}" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text \
    --region "${TARGET_REGION}"
  )

  if [ -z "${SOURCE_INSTANCE_ID}" ] && [ -z "${TARGET_INSTANCE_ID}" ] ; then
    echo "Running the EC2 instances in the source region=${SOURCE_REGION} and the target region=${TARGET_REGION}" 
    # Run this in background, so that the next iteration can be started without waiting
    (echo "${EC2_INPUT_JSON}" | \
      ./run-ec2-instance.sh \
        --stack-name "${STACK_NAME}" \
        --source-region "${SOURCE_REGION}" \
        --target-region "${TARGET_REGION}" \
        --test-uuid "${TEST_EXECUTION_UUID}" \
        --s3-bucket "${S3_BUCKET_NAME}"
    ) &

    ######################################################
    # For the next iteration
    ######################################################
    REGION_PAIRS=$(echo "${REGION_PAIRS}" | grep -v "${PICKED_UP}")
    sleep 5s # To let EC2 be captured the by describe-instances commands
  fi
done
