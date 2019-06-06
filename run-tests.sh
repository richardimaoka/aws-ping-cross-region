#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

TEST_EXECUTION_UUID=$(uuidgen)
S3_BUCKET_NAME="samplebucket-richardimaoka-sample-sample"
for OPT in "$@"
do
    case "$OPT" in
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
if [ -z "${FILE_NAME}" ] ; then
  if ! EC2_INPUT_JSON=$(./generate-ec2-input-json.sh); then 
    >&2 echo "ERROR: Failed to generate the input json with ./generate-ec2-input-json.sh"
    exit 1
  fi
else
  if ! EC2_INPUT_JSON=$(jq -r "." < "${FILE_NAME}"); then
    >&2 echo "ERROR: Failed to read input JSON from ${FILE_NAME}"
    exit 1
  fi
fi

######################################################
# 2. Create EC2 instances and send the ping command
######################################################
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for SOURCE_REGION in ${REGIONS}
do
  for TARGET_REGION in ${REGIONS}
  do
    if [ "${SOURCE_REGION}" != "${TARGET_REGION}" ]; then

      ######################################################
      # 2.1 Run the EC2 instances and wait
      ######################################################
      echo "Running the EC2 instances in the source region=${SOURCE_REGION} and the target region=${TARGET_REGION}" 
      if ! EC2_OUTPUT=$(echo "${EC2_INPUT_JSON}" | ./run-ec2-instance.sh --source-region "${SOURCE_REGION}" --target-region "${TARGET_REGION}") ; then
        exit 1
      fi

      SOURCE_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".source.instance_id")
      TARGET_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".target.instance_id")
      TARGET_IP_ADDRESS=$(echo "${EC2_OUTPUT}" | jq -r ".target.private_ip_address")

      echo "Waiting for the EC2 instances to be status = ok: source = ${SOURCE_INSTANCE_ID} and target = ${TARGET_INSTANCE_ID}"
      if ! aws ec2 wait instance-status-ok --instance-ids "${SOURCE_INSTANCE_ID}" --region "${SOURCE_REGION}" ; then
        >&2 echo "ERROR: failed to wait on the source EC2 instance = ${SOURCE_INSTANCE_ID}"
        exit 1
      elif ! aws ec2 wait instance-status-ok --instance-ids "${TARGET_INSTANCE_ID}" --region "${TARGET_REGION}" ; then
        >&2 echo "ERROR: failed to wait on the source EC2 instance = ${TARGET_INSTANCE_ID}"
        exit 1
      fi

      ######################################################
      # 2.2 Send the command and sleep to wait
      ######################################################
      echo "Sending command to the source EC"
      if ! aws ssm send-command \
        --instance-ids "${SOURCE_INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --comment "aws-ping command to run ping to all relevant EC2 instances in all the regions" \
        --parameters commands=["/home/ec2-user/aws-ping-cross-region/ping-target.sh --source-region ${SOURCE_REGION} --target-region ${TARGET_REGION} --target-ip ${TARGET_IP_ADDRESS} --test-uuid ${TEST_EXECUTION_UUID} --s3-bucket ${S3_BUCKET_NAME}"] \
        --region "${SOURCE_REGION}" > /dev/null ; then
        >&2 echo "ERROR: failed to send command to = ${SOURCE_INSTANCE_ID}"
      fi

      # There's no quick and wasy way to signal the end of the test, so just sleep enough to wait
      echo "Sleeping to let the test finish"
      sleep 90s

      ######################################################
      # 2.3 Terminate the EC2 instances
      ######################################################
      echo "Terminate the EC2 instances"
      if ! aws ec2 terminate-instances --instance-ids "${SOURCE_INSTANCE_ID}" --region "${SOURCE_REGION}" > /dev/null ; then
        >&2 echo "ERROR: failed terminate the source EC2 instance = ${SOURCE_INSTANCE_ID}"
        exit 1
      fi
      if ! aws ec2 terminate-instances --instance-ids "${TARGET_INSTANCE_ID}" --region "${TARGET_REGION}" > /dev/null ; then
        >&2 echo "ERROR: failed terminate the target EC2 instance = ${TARGET_INSTANCE_ID}"
        exit 1
      fi
      if ! aws ec2 wait instance-terminated --instance-ids "${SOURCE_INSTANCE_ID}" --region "${SOURCE_REGION}" > /dev/null ; then
        >&2 echo "ERROR: failed to wait on the termination of the EC2 instance = ${SOURCE_INSTANCE_ID}"
        exit 1
      fi
      if ! aws ec2 wait instance-terminated --instance-ids "${TARGET_INSTANCE_ID}" --region "${TARGET_REGION}" > /dev/null ; then
        >&2 echo "ERROR: failed to wait  on the termination of the EC2 instance = ${SOURCE_INSTANCE_ID}"
        exit 1
      fi
    fi
  done
  break
done
