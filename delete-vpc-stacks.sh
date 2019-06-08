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

REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

#######################################################
# Step 1: Delete Routes for VPC Peering in route tables
#######################################################
for REGION in ${REGIONS}
do
  echo "Deleting VPC-peering routes in ${REGION}s route table"
  ROUTE_TABLE=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='RouteTable'].OutputValue" --output text --region "${REGION}")
  
  for CIDR_BLOCK in $(aws ec2 describe-route-tables \
    --route-table-ids "${ROUTE_TABLE}"\
    --query "RouteTables[].Routes[?VpcPeeringConnectionId].DestinationCidrBlock" \
    --output text \
    --region "${REGION}"
  )
  do
    echo "Deleting Route destinated to "${CIDR_BLOCK}" from ${ROUTE_TABLE}"
    aws ec2 delete-route --route-table-id "${ROUTE_TABLE}" --destination-cidr-block "${CIDR_BLOCK}"
  done
done

###################################################
# Step 2: Delete VPC Peering
###################################################
for REGION in ${REGIONS}
do 
  VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REGION}")
  VPC_CONNECTIONS=$(aws ec2 describe-vpc-peering-connections --region "${REGION}")
  
  for VPC_PEERING_ID in $(echo "${VPC_CONNECTIONS}" | jq -r ".VpcPeeringConnections[] | select(.AccepterVpcInfo.VpcId==\"${VPC_ID}\" or .RequesterVpcInfo.VpcId==\"${VPC_ID}\") | select(.Status.Code!=\"deleted\") | .VpcPeeringConnectionId")
  do
    echo "Deleting ${VPC_PEERING_ID}"
    aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "${VPC_PEERING_ID}" --region "${REGION}"
  done
done 

###################################################
# Step 3: Delete CloudFormation VPC Stacks
###################################################
for REGION in ${REGIONS}
do 
  echo "Deleting the CloudFormation stack=${STACK_NAME} for region=${REGION} if exists."
  aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
done 
