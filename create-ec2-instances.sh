#!/bin/sh

read INPUT

TEST_EXECUTION_UUID=$(uuidgen)

for SOURCE_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
  for TARGET_REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
  
    SOURCE_INSTANCE_TYPE=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".instance_type")
    SOURCE_IMAGE_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".image_id")
    SOURCE_SECURITY_GROUP_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".security_group")
    SOURCE_SUBNET_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".subnet_id")
    SOURCE_PRIVATE_IP_ADDRESS=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".private_ip_address")

    SOURCE_OUTPUTS=$(aws ec2 run-instances \
      --image-id "${SOURCE_IMAGE_ID}" \
      --instance-type "${SOURCE_INSTANCE_TYPE}" \
      --key-name "demo-key-pair" \
      --network-interfaces \
        "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${SOURCE_SECURITY_GROUP_ID},SubnetId=${SOURCE_SUBNET_ID}" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
      --user-data file:\\user-data.txt
    )

    INSTANCE_TYPE=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".instance_type")
    IMAGE_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".image_id")
    SECURITY_GROUP_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".security_group")
    SUBNET_ID=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".subnet_id")
    PRIVATE_IP_ADDRESS=$(echo "${INPUT}" | jq -r ".\"$SOURCE_REGION\".private_ip_address")

    TARGET_OUTPUTS=$(aws ec2 run-instances \
      --image-id "${AMI_LINUX2}" \
      --instance-type "${EC2_INSTANCE_TYPE}" \
      --key-name "demo-key-pair" \
      --network-interfaces \
        "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${TARGET_SECURITY_GROUP_ID},SubnetId=${TARGET_SUBNET_ID}" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]" \
      --user-data file:\\user-data.txt
    )

    if ! aws ec2 wait instance-status-ok --instance-ids "${SOURCE_INSTANCE_ID}" ; then
      echo "failed to wait on the source EC2 instance = "${SOURCE_INSTANCE_ID}""
    fi

    if ! aws ec2 wait instance-status-ok --instance-ids "${TARGET_INSTANCE_ID}" ; then
      echo "failed to wait on the target EC2 instance = "${TARGET_INSTANCE_ID}""
    fi

    aws ssm send-command \
      --instance-ids "${SOURCE_INSTANCE_ID}" \
      --document-name "AWS-RunShellScript" \
      --comment "aws-ping command to run ping to all relevant EC2 instances in all the regions" \
      --parameters commands=["/home/ec2-user/aws-ping-cross-region/ping-target.sh --source-region ${SOURCE_REGION} --target-region ${TARGET_REGION} --target-ip ${TARGET_IP_ADDRESS} --test-uuid "${TEST_EXECUTION_UUID}" ] \
      --output text \
      --query "Command.CommandIad"
  done
done
