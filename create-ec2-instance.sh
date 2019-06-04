#!/bin/sh

INPUT_JSON=$(cat)

for OPT in "$@"
do
    case "$OPT" in
      '--source-region' )
        if [ -z "$2" ]; then
            echo "option --source-region requires an argument -- $1" 1>&2
            exit 1
        fi
        SOURCE_REGION="$2"
        ;;
      '--target-region' )
        if [ -z "$2" ]; then
            echo "option --target-region requires an argument -- $1" 1>&2
            exit 1
        fi
        TARGET_REGION="$2"
        ;;
    esac
done

if [ -z "${SOURCE_REGION}" ] ; then
  >&2 echo "ERROR: option --source-region needs to be passed"
  ERROR="1"
fi
if [ -z "${TARGET_REGION}" ] ; then
  >&2 echo "ERROR: option --target-region needs to be passed"
  ERROR="1"
fi
if ! echo "${INPUT_JSON}" | jq ; then
  >&2 echo "ERROR: the input is not valid json:"
  >&2 echo "${INPUT_JSON}"
  ERROR="1"
fi
if [ -n ERROR ] ; then
  exit 1
fi

SOURCE_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".instance_type")
SOURCE_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".image_id")
SOURCE_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".security_group")
SOURCE_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".subnet_id")

aws ec2 run-instances \
  --image-id "${SOURCE_IMAGE_ID}" \
  --instance-type "${SOURCE_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${SOURCE_SECURITY_GROUP_ID},SubnetId=${SOURCE_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
  --user-data file:\\user-data.txt \
  --region 


TARGET_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".instance_type")
TARGET_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".image_id")
TARGET_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".security_group")
TARGET_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".subnet_id")

aws ec2 run-instances \
  --image-id "${TARGET_IMAGE_ID}" \
  --instance-type "${TARGET_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${TARGET_SECURITY_GROUP_ID},SubnetId=${TARGET_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
  --user-data file:\\user-data.txt


# if ! aws ec2 wait instance-status-ok --instance-ids "${SOURCE_INSTANCE_ID}" ; then
#   >&2 echo "ERROR: failed to wait on the source EC2 instance = ${SOURCE_INSTANCE_ID}"
#   exit 1
# fi

# if ! aws ec2 wait instance-status-ok --instance-ids "${TARGET_INSTANCE_ID}" ; then
#   >&2 echo "ERROR: failed to wait on the target EC2 instance = ${TARGET_INSTANCE_ID}"
#   exit
# fi

# echo "{ \"source_instance_id\": \"${SOURCE_INSTANCE_ID}\", \"target_instance_id\": \"${TARGET_INSTANCE_ID}\" }"