#!/bin/sh

STACK_NAME="PingCrossRegionExperiment"

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

  echo "\"${REGION}\": {"
  echo "  \"image_id\": \"${AMI_LINUX2}\","
  echo "  \"security_group\": \"${SECURITY_GROUP_ID}\","
  echo "  \"subnet_id\": \"${SUBNET_ID}\"
  if [ "$REGION" = "${LAST_REGION}" ]; then
    echo "}"
  else
    echo "},"
  fi
done

# End of JSON
echo "}"
