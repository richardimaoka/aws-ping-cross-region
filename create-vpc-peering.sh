#!/bin/sh

for OPT in "$@"
do
  case "$OPT" in
    '--aws-account' )
      if [ -z "$2" ]; then
          echo "option --aws-account requires an argument -- $1" 1>&2
          exit 1
      fi
      AWS_ACCOUNT_ID="$2"
      shift 2
      ;;
    '--stack-name' )
      if [ -z "$2" ]; then
          echo "option --stack-name requires an argument -- $1" 1>&2
          exit 1
      fi
      STACK_NAME="$2"
      shift 2
      ;;
    '--accepter-region' )
      if [ -z "$2" ]; then
          echo "option --accepter-region requires an argument -- $1" 1>&2
          exit 1
      fi
      ACCEPTER_REGION="$2"
      shift 2
      ;;
    '--requester-region' )
      if [ -z "$2" ]; then
          echo "option --requester-region requires an argument -- $1" 1>&2
          exit 1
      fi
      REQUESTER_REGION="$2"
      shift 2
      ;;
  esac
done
if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: Option --stack-name needs to be specified"
  ERROR="1"
fi
if [ -z "${ACCEPTER_REGION}" ] ; then
  >&2 echo "ERROR: Option --accepter-region needs to be specified"
  ERROR="1"
fi
if [ -z "${REQUESTER_REGION}" ] ; then
  >&2 echo "ERROR: Option --requester-region  needs to be specified"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

ACCEPTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${ACCEPTER_REGION}")
REQUESTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REQUESTER_REGION}")

#######################################
# Step 1. Create VPC Peering connection
#######################################

VPC_PEERING_IN_ACCEPTER_VPC=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?Status.Code!='deleted']" --region "${ACCEPTER_REGION}")
VPC_PEERING_IN_DIRECTION1=$(echo "${VPC_PEERING_IN_ACCEPTER_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${ACCEPTER_VPC_ID}\") | select(.RequesterVpcInfo.VpcId==\"${REQUESTER_VPC_ID}\")")
VPC_PEERING_IN_DIRECTION2=$(echo "${VPC_PEERING_IN_ACCEPTER_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${REQUESTER_VPC_ID}\") | select(.RequesterVpcInfo.VpcId==\"${ACCEPTER_VPC_ID}\")")

# If VPC Peering exists in either direction, do not create the other direction
if [ -n "${VPC_PEERING_IN_DIRECTION1}" ] ; then 
  echo "VPC Peering between ${ACCEPTER_REGION} and ${REQUESTER_REGION} already exists"
  VPC_PEERING_ID=$(echo "${VPC_PEERING_IN_DIRECTION1}" | jq -r ".VpcPeeringConnection.VpcPeeringConnectionId")  
elif  [ -n "${VPC_PEERING_IN_DIRECTION2}" ] ; then
  echo "VPC Peering between ${REQUESTER_REGION} and ${ACCEPTER_REGION} already exists"
  VPC_PEERING_ID=$(echo "${VPC_PEERING_IN_DIRECTION2}" | jq -r ".VpcPeeringConnection.VpcPeeringConnectionId")  
else   
  echo "Creating VPC Peering between requester=${REQUESTER_VPC_ID}(${REQUESTER_REGION}) and accepter=${ACCEPTER_VPC_ID}(${ACCEPTER_REGION})"
  # If it fails, an error message is displayed on stderror
  if ! VPC_PEERING_OUTPUT=$(aws ec2 create-vpc-peering-connection \
    --peer-owner-id "${AWS_ACCOUNT_ID}" \
    --peer-vpc-id "${ACCEPTER_VPC_ID}" \
    --vpc-id "${REQUESTER_VPC_ID}" \
    --peer-region "${ACCEPTER_REGION}" \
    --region "${REQUESTER_REGION}" 
  ) ; then
    exit 1
  fi
  VPC_PEERING_ID=$(echo "${VPC_PEERING_OUTPUT}" | jq -r ".VpcPeeringConnection.VpcPeeringConnectionId")
fi

#######################################
# Step 2. Accept VPC Peering connection
#######################################
echo "Accepting ${VPC_PEERING_ID} in ${ACCEPTER_REGION}"
# If it fails, an error message is displayed on stderror
if ! aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id "${VPC_PEERING_ID}" \
  --region "${ACCEPTER_REGION}" > /dev/null ; then
  exit 1
fi

#######################################
# Step 3. Accept VPC Peering connection
#######################################
ACCEPTER_ROUTE_TABLE=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='RouteTable'].OutputValue" --output text --region "${ACCEPTER_REGION}")
ACCEPTER_CIDR_BLOCK=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${ACCEPTER_VPC_ID}'].RequesterVpcInfo.Region" --region "${ACCEPTER_REGION}")
REQUESTER_ROUTE_TABLE=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='RouteTable'].OutputValue" --output text --region "${REQUESTER_REGION}")
REQUESTER_CIDR_BLOCK=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${REQUESTER_VPC_ID}'].RequesterVpcInfo.Region" --region "${REQUESTER_REGION}")

echo "Adding VPC peering route to the route table of the main VPC"
aws ec2 create-route \
  --route-table-id "${ACCEPTER_ROUTE_TABLE}" \
  --destination-cidr-block "${REQUESTER_CIDR_BLOCK}" \
  --vpc-peering-connection-id "${VPC_PEERING_ID}" \
  --output text > /dev/null

aws ec2 create-route \
  --route-table-id "${REQUESTER_ROUTE_TABLE}" \
  --destination-cidr-block "${ACCEPTER_CIDR_BLOCK}" \
  --vpc-peering-connection-id "${VPC_PEERING_ID}" \
  --output text > /dev/null