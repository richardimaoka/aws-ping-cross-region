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

# Start of JSON
echo "{"

LAST_REGION=$(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text | tail -1)
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

  OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[]" --region "${REGION}") 
  SECURITY_GROUP_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="SecurityGroup") | .OutputValue')
  SUBNET_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="Subnet") | .OutputValue')
  SUBNET_CIDR_FIRST_TWO_OCTETS=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="SubnetCidrFirstTwoOctets") | .OutputValue')

  echo "\"${REGION}\": {"
  echo "  \"instance_type\": \"${EC2_INSTANCE_TYPE}\","
  echo "  \"image_id\": \"${AMI_LINUX2}\","
  echo "  \"security_group\": \"${SECURITY_GROUP_ID}\","
  echo "  \"subnet_id\": \"${SUBNET_ID}\","
  echo "  \"private_ip_address\": \"${SUBNET_CIDR_FIRST_TWO_OCTETS}.0.6\"" 
  if [ "$REGION" = "${LAST_REGION}" ]; then
    echo "}"
  else
    echo "},"
  fi
done

# End of JSON
echo "}"
