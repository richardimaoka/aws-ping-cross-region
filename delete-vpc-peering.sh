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

for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REGION}")
  
  for VPC_PEERING_ID in $(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${VPC_ID}'].VpcPeeringConnectionId" --output text --region "${REGION}")
  do
    echo "Deleting ${VPC_PEERING_ID}"
    aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "${VPC_PEERING_ID}" --region "${REGION}"
  done
done 
