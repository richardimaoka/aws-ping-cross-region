#!/bin/sh

# parse options
EC2_INSTANCE_TYPE="t2.micro"
STACK_NAME="PingCrossRegionExperiment"
for OPT in "$@"
do
    case "$OPT" in
      '--instance-type' )
        if [ -z "$2" ]; then
          echo "option --instance-type requires an argument -- $1" 1>&2
          exit 1
        fi
        EC2_INSTANCE_TYPE="$2"
        shift 2
        ;;
    esac
done


############################
# Create a json file
############################
echo "{"

for REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami.html
  AMI_LINUX2=$(aws ec2 describe-images \
    --region "${REGION}" \
    --owners amazon \
    --filters 'Name=name,Values=amzn2-ami-hvm-2.0.????????-x86_64-gp2' 'Name=state,Values=available' \
    --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" \
    --output text
  )
  SECURITY_GROUP_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='SecurityGroup'].OutputValue" --output text --region "${REGION}")
  SUBNET_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='Subnet'].OutputValue" --output text --region "${REGION}")
  SUBNET_CIDR_FIRST_TWO_OCTETS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='SubnetCidrFirstTwoOctets'].OutputValue" --output text --region "${REGION}")
 
  echo "\"${REGION}\": {"
  echo "  \"instance_type\": \"${EC2_INSTANCE_TYPE}\","
  echo "  \"image_id\": \"${AMI_LINUX2}\","
  echo "  \"security_group\": \"${SECURITY_GROUP_ID}\","
  echo "  \"subnet_id\": \"${SUBNET_ID}\","
  echo "  \"private_ip_address\": \"${SUBNET_CIDR_FIRST_TWO_OCTETS}.0.6\"" 
  echo "}"

#  aws ec2 run-instances \
#    --image-id "${AMI_LINUX2}" \
#    --instance-type "${EC2_INSTANCE_TYPE}" \
#    --key-name "demo-key-pair" \
#    --network-interfaces \
#      "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${SECURITY_GROUP_ID},SubnetId=${SUBNET_ID},PrivateIpAddresses=[{Primary=true,PrivateIpAddress=${PRIVATE_IP_ADDRESS}}]" \
#    --tag-specifications \
#      "ResourceType=instance,Tags=[{Key=experiment-name,Value=aws-ping-cross-region}]"
done