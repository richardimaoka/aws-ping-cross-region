#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

for OPT in "$@"
do
  case "$OPT" in
    '--stack-name' )
      if [ -z "$2" ]; then
          echo "option -f or --stack-name requires an argument -- $1" 1>&2
          exit 1
      fi
      STACK_NAME="$2"
      shift 2
      ;;
  esac
done
if [ -z "${STACK_NAME}" ] ; then
  echo "ERROR: Option --stack-name needs to be specified"
  exit 1
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SSH_LOCATION="$(curl ifconfig.co 2> /dev/null)/32"

REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

################################
# Step 1: Create the VPCs
################################
for REGION in ${REGIONS}
do 
  ################################
  # Step 1.1: Create if not exist
  ################################
  if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" > /dev/null 2>&1; then
    echo "Creating a CloudFormation stack=${STACK_NAME} for region=${REGION}"
    # If it fails, an error message is displayed and it continues to the next REGION
    aws cloudformation create-stack \
      --stack-name "${STACK_NAME}" \
      --template-body file://cloudformation-vpc.yaml \
      --capabilities CAPABILITY_NAMED_IAM \
      --parameters ParameterKey=SSHLocation,ParameterValue="${SSH_LOCATION}" \
                    ParameterKey=AWSAccountId,ParameterValue="${AWS_ACCOUNT_ID}" \
      --region "${REGION}" \
      --output text
  fi

  #################################
  # Step 1.2: Wait until it's ready
  #################################
  echo "Waiting until the CloudFormation stack is CREATE_COMPLETE or UPDATE_COMPLETE for ${REGION}"
  if ! aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then
    >&2 echo "ERROR: CloudFormation wait failed for ${REGION}"
    exit 1
  fi    
done 

##################################################################################
# Step 2: Create VPC Peering in all the regions
#
# The CloudFormation template of this repository does not define VPC Peering,
# because of its complex requester-accepter dependencies. Instead, VPC Peering is
# created by AWS CLI calls in create-vpc-peering.sh. See README.md for more detail.
###################################################################################
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

for REGION1 in ${REGIONS}
do
  for REGION2 in ${REGIONS}
  do
    if [ "${REGION1}" != "${REGION2}" ] ; then
      ./create-vpc-peering.sh \
        --aws-account "${AWS_ACCOUNT_ID}" \
        --stack-name "${STACK_NAME}" \
        --region1 "${REGION1}" \
        --region2 "${REGION2}"
    fi      
  done
done
