#!/bin/sh

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

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

###################################################
# Step 1: Wait on CloudFormation VPC stack creation
###################################################
for REGION in ${REGIONS}
do
  echo "Waiting until the CloudFormation stack is CREATE_COMPLETE for ${REGION}"
  if ! aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then
    >&2 echo "ERROR: CloudFormation wait failed for ${REGION}"
    exit 1
  fi
done

################################################
# Step 2: Create VPC Peering in all the regions
################################################
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
