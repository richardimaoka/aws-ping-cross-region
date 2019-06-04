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
        shift 2
        ;;
      '--target-region' )
        if [ -z "$2" ]; then
            echo "option --target-region requires an argument -- $1" 1>&2
            exit 1
        fi
        TARGET_REGION="$2"
        shift 2
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
if ! echo "${INPUT_JSON}" | jq -r "." > /dev/null ; then
  >&2 echo "ERROR: the input is not valid json:"
  >&2 echo "${INPUT_JSON}"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

######################################
# 1. Create the source EC2 instance
######################################

SOURCE_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".instance_type")
SOURCE_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".image_id")
SOURCE_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".security_group")
SOURCE_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".subnet_id")

SOURCE_OUTPUTS=$(aws ec2 run-instances \
  --image-id "${SOURCE_IMAGE_ID}" \
  --instance-type "${SOURCE_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${SOURCE_SECURITY_GROUP_ID},SubnetId=${SOURCE_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
  --user-data file:\\user-data.txt \
  --region "${SOURCE_REGION}"
)

######################################
# 1. Create the target EC2 instance
######################################

TARGET_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".instance_type")
TARGET_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".image_id")
TARGET_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".security_group")
TARGET_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".subnet_id")

TARGET_OUTPUTS=$(aws ec2 run-instances \
  --image-id "${TARGET_IMAGE_ID}" \
  --instance-type "${TARGET_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${TARGET_SECURITY_GROUP_ID},SubnetId=${TARGET_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
  --user-data file:\\user-data.txt \
  --region "${TARGET_REGION}"
)

SOURCE_INSTANCE_ID=$(echo "${SOURCE_OUTPUTS}" | jq -r ".Instances[].InstanceId")
SOURCE_PRIVATE_IP=$(echo "${SOURCE_OUTPUTS}" | jq -r ".Instances[].NetworkInterfaces[].PrivateIpAddress")
TARGET_INSTANCE_ID=$(echo "${TARGET_OUTPUTS}" | jq -r ".Instances[].InstanceId")
TARGET_PRIVATE_IP=$(echo "${TARGET_OUTPUTS}" | jq -r ".Instances[].NetworkInterfaces[].PrivateIpAddress")

echo "{ "
echo "  \"source\" {"
echo "    \"instance_id\": \"${SOURCE_INSTANCE_ID}\","
echo "    \"private_ip_address\": \"${SOURCE_INSTANCE_ID}\","
echo "    \"region\": \"${SOURCE_REGION}\""
echo "  },"
echo "  \"target\" {"
echo "    \"instance_id\": \"${TARGET_INSTANCE_ID}\","
echo "    \"private_ip_address\": \"${TARGET_PRIVATE_IP}\","
echo "    \"region\": \"${TARGET_REGION}\""
echo "  }"
echo "}"
