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
  EC2_INPUT_JSON=$(./create-ec2-input-json.sh)
  if [ $? -ne 0 ] ; then
    exit 1
  fi
else
  EC2_INPUT_JSON=$(cat "${FILE_NAME}" | jq -r ".")
  if [ $? -ne 0 ] ; then
    exit 1
  fi
fi

######################################################
# 2. Create EC2 instances and send the ping command
######################################################

for SOURCE_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
  for TARGET_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
  do
    if [ "${SOURCE_REGION}" != "${TARGET_REGION}" ]; then
      echo "testing ping from region=${SOURCE_REGION} to region=${TARGET_REGION}"
  
      EC2_OUTPUT=$(echo "${EC2_INPUT_JSON}" | ./create-ec2-instance.sh --source-region "${SOURCE_REGION}" --target-region "${TARGET_REGION}")
      if [ $? -ne 0 ] ; then
        exit 1
      fi

      SOURCE_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".source.instance_id")
      TARGET_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".target.instance_id")

      echo "Waiting for the EC2 instances to be status = ok: source = ${SOURCE_INSTANCE_ID} and target = ${TARGET_INSTANCE_ID}"
      if ! aws ec2 wait instance-status-ok --instance-ids "${SOURCE_INSTANCE_ID}" ; then
        >&2 echo "ERROR: failed to wait on the source EC2 instance = ${SOURCE_INSTANCE_ID}"
        exit 1
      elif ! aws ec2 wait instance-status-ok --instance-ids "${TARGET_INSTANCE_ID}" ; then
        >&2 echo "ERROR: failed to wait on the source EC2 instance = ${TARGET_INSTANCE_ID}"
        exit 1
      fi

      aws ssm send-command \
        --instance-ids "${SOURCE_INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --comment "aws-ping command to run ping to all relevant EC2 instances in all the regions" \
        --parameters commands=["/home/ec2-user/aws-ping-cross-region/ping-target.sh --source-region ${SOURCE_REGION} --target-region ${TARGET_REGION} --target-ip ${TARGET_IP_ADDRESS} --test-uuid ${TEST_EXECUTION_UUID}" --s3-bucket "${S3_BUCKET_NAME }"] \
        --output text \
        --query "Command.CommandId"
      break
    fi
  done
  break
done
