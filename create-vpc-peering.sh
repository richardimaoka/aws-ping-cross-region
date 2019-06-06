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
    '--region1' )
      if [ -z "$2" ]; then
          echo "option --region1 requires an argument -- $1" 1>&2
          exit 1
      fi
      REGION1="$2"
      shift 2
      ;;
    '--region2' )
      if [ -z "$2" ]; then
          echo "option --region2 requires an argument -- $1" 1>&2
          exit 1
      fi
      REGION2="$2"
      shift 2
      ;;
  esac
done
if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: Option --stack-name needs to be specified"
  ERROR="1"
fi
if [ -z "${REGION1}" ] ; then
  >&2 echo "ERROR: Option --region1 needs to be specified"
  ERROR="1"
fi
if [ -z "${REGION2}" ] ; then
  >&2 echo "ERROR: Option --region2  needs to be specified"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

REGION1_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REGION1}")
REGION2_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REGION2}")

#######################################
# Step 1. Create VPC Peering connection
#######################################
VPC_PEERING_IN_REGION1_VPC=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?Status.Code!='deleted']" --region "${REGION1}")
VPC_PEERING_IN_DIRECTION1=$(echo "${VPC_PEERING_IN_REGION1_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${REGION1_VPC_ID}\") | select(.RequesterVpcInfo.VpcId==\"${REGION2_VPC_ID}\")")
VPC_PEERING_IN_DIRECTION2=$(echo "${VPC_PEERING_IN_REGION1_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${REGION2_VPC_ID}\") | select(.RequesterVpcInfo.VpcId==\"${REGION1_VPC_ID}\")")

# If VPC Peering exists in either direction, do not create the other direction
if [ -n "${VPC_PEERING_IN_DIRECTION1}" ] ; then 
  echo "VPC Peering between ${REGION1} and ${REGION2} already exists"
  VPC_PEERING_ID=$(echo "${VPC_PEERING_IN_DIRECTION1}" | jq -r ".VpcPeeringConnectionId")
  VPC_PEERING_STATUS=$(echo "${VPC_PEERING_IN_DIRECTION1}" | jq -r ".Status.Code")
  ACCEPTER_REGION="${REGION1}"
  REQUESTER_REGION="${REGION2}"
  ACCEPTER_VPC_ID="${REGION1_VPC_ID}"
  REQUESTER_VPC_ID="${REGION2_VPC_ID}"
elif  [ -n "${VPC_PEERING_IN_DIRECTION2}" ] ; then
  echo "VPC Peering between ${REGION2} and ${REGION1} already exists"
  VPC_PEERING_ID=$(echo "${VPC_PEERING_IN_DIRECTION2}" | jq -r ".VpcPeeringConnectionId")  
  VPC_PEERING_STATUS=$(echo "${VPC_PEERING_IN_DIRECTION2}" | jq -r ".Status.Code")
  ACCEPTER_REGION="${REGION2}"
  REQUESTER_REGION="${REGION1}"
  ACCEPTER_VPC_ID="${REGION2_VPC_ID}"
  REQUESTER_VPC_ID="${REGION1_VPC_ID}"
else   
  echo "Creating VPC Peering between requester=${REGION2_VPC_ID}(${REGION2}) and accepter=${REGION1_VPC_ID}(${REGION1})"
  # If it fails, an error message is displayed on stderror
  if ! VPC_PEERING_OUTPUT=$(aws ec2 create-vpc-peering-connection \
    --peer-owner-id "${AWS_ACCOUNT_ID}" \
    --peer-vpc-id "${REGION1_VPC_ID}" \
    --vpc-id "${REGION2_VPC_ID}" \
    --peer-region "${REGION1}" \
    --region "${REGION2}" 
  ) ; then
    exit 1
  fi
  VPC_PEERING_ID=$(echo "${VPC_PEERING_OUTPUT}" | jq -r ".VpcPeeringConnection.VpcPeeringConnectionId")
  VPC_PEERING_STATUS=$(echo "${VPC_PEERING_OUTPUT}" | jq -r ".VpcPeeringConnection.Status.Code")
  ACCEPTER_REGION="${REGION1}"
  REQUESTER_REGION="${REGION2}"
  ACCEPTER_VPC_ID="${REGION1_VPC_ID}"
  REQUESTER_VPC_ID="${REGION2_VPC_ID}"
fi

#######################################
# Step 2. Accept VPC Peering connection
#######################################
if [ "active" = "${VPC_PEERING_STATUS}" ] ; then
  echo "VPC Peering ${VPC_PEERING_ID} is already accepted and active"
elif ! aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-id "${VPC_PEERING_ID}" ; then
  >&2 echo "ERROR: Failed to wait on ${VPC_PEERING_ID}"
  exit 1
else 
  echo "Accepting ${VPC_PEERING_ID} in ${ACCEPTER_REGION}"
  # If it fails, an error message is displayed on stderror
  if ! aws ec2 accept-vpc-peering-connection \
    --vpc-peering-connection-id "${VPC_PEERING_ID}" \
    --region "${ACCEPTER_REGION}" > /dev/null ; then
    exit 1
  fi
fi

#######################################
# Step 3. Accept VPC Peering connection
#######################################
ACCEPTER_ROUTE_TABLE=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='RouteTable'].OutputValue" --output text --region "${ACCEPTER_REGION}")
REQUESTER_ROUTE_TABLE=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='RouteTable'].OutputValue" --output text --region "${REQUESTER_REGION}")

VPC_PEERING_CONNECTION=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${ACCEPTER_VPC_ID}' && RequesterVpcInfo.VpcId=='${REQUESTER_VPC_ID}']" --region "${ACCEPTER_REGION}")
ACCEPTER_CIDR_BLOCK=$(echo "${VPC_PEERING_CONNECTION}" | jq -r ".[].AccepterVpcInfo.CidrBlock")
REQUESTER_CIDR_BLOCK=$(echo "${VPC_PEERING_CONNECTION}" | jq -r ".[].RequesterVpcInfo.CidrBlock")

if [ -n "$(aws ec2 describe-route-tables --route-table-ids "${ACCEPTER_ROUTE_TABLE}" --query "RouteTables[].Routes[?DestinationCidrBlock=='${REQUESTER_CIDR_BLOCK}']" --output text --region "${ACCEPTER_REGION}")" ] ; then
  echo "Route table ${ACCEPTER_ROUTE_TABLE} in ${ACCEPTER_REGION} already has a route for ${VPC_PEERING_ID}"
else
  echo "Adding a route to a route table ${ACCEPTER_ROUTE_TABLE} in ${ACCEPTER_REGION} for ${VPC_PEERING_ID}"
  aws ec2 create-route \
    --route-table-id "${ACCEPTER_ROUTE_TABLE}" \
    --destination-cidr-block "${REQUESTER_CIDR_BLOCK}" \
    --vpc-peering-connection-id "${VPC_PEERING_ID}" \
    --output text \
    --region "${ACCEPTER_REGION}" > /dev/null
fi

if [ -n "$(aws ec2 describe-route-tables --route-table-ids "${REQUESTER_ROUTE_TABLE}" --query "RouteTables[].Routes[?DestinationCidrBlock=='${ACCEPTER_CIDR_BLOCK}']" --output text --region "${REQUESTER_REGION}")" ] ; then
  echo "Route table ${REQUESTER_ROUTE_TABLE} in ${REQUESTER_REGION} already has a route for ${VPC_PEERING_ID}"
else
  echo "Adding a route to a route table ${REQUESTER_ROUTE_TABLE} in ${REQUESTER_REGION} for ${VPC_PEERING_ID}"
  aws ec2 create-route \
    --route-table-id "${REQUESTER_ROUTE_TABLE}" \
    --destination-cidr-block "${ACCEPTER_CIDR_BLOCK}" \
    --vpc-peering-connection-id "${VPC_PEERING_ID}" \
    --output text \
    --region "${REQUESTER_REGION}" > /dev/null
fi
