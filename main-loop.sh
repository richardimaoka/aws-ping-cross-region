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
    esac
done

for SOURCE_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
  for TARGET_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
  do
    if [ "${SOURCE_REGION}" != "${TARGET_REGION}" ]; then
      EC2_OUTPUT=$(./create-ec2-instance --source-region "${SOURCE_REGION}" --target-region "${TARGET_REGION}")
      if ! $? ; then
        exit 1
      fi

      SOURCE_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".source.instance_id")
      TARGET_INSTANCE_ID=$(echo "${EC2_OUTPUT}" | jq -r ".target.instance_id")

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
    fi
    break
  done
  break
done
