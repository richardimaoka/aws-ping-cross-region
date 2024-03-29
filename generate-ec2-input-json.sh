#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

STACK_NAME="PingCrossRegionExperiment"

FILE_NAME=$(tempfile)

# Start of JSON
echo "{" >> "${FILE_NAME}"

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
  IAM_INSTANCE_PROFILE=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="InstanceProfile") | .OutputValue')

  echo "\"${REGION}\": {" >> "${FILE_NAME}"
  echo "  \"image_id\": \"${AMI_LINUX2}\"," >> "${FILE_NAME}"
  echo "  \"security_group\": \"${SECURITY_GROUP_ID}\"," >> "${FILE_NAME}"
  echo "  \"instance_profile\": \"${IAM_INSTANCE_PROFILE}\"," >> "${FILE_NAME}"
  echo "  \"subnet_id\": \"${SUBNET_ID}\"" >> "${FILE_NAME}"
  if [ "$REGION" = "${LAST_REGION}" ]; then 
    echo "}" >> "${FILE_NAME}"
  else
    echo "}," >> "${FILE_NAME}"
  fi
done

# End of JSON
echo "}" >> "${FILE_NAME}"

jq -s '.[0] * .[1]' "${FILE_NAME}" instance-types.json

rm "${FILE_NAME}"
