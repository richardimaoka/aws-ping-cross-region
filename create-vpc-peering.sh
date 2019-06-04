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

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
SSH_LOCATION="$(curl ifconfig.co 2> /dev/null)/32"

################################################
# Step 1: Create VPC Peering in all the regions
################################################

for ACCEPTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  EXISTING_VPC_PEERING_REGIONS=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[].RequesterVpcInfo.Region")
  ACCEPTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCPeeringConnection'].OutputValue" --output text --region "${ACCEPTER_REGION}")

  for REQUESTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
  do
    if [ "true" = $(echo "${EXISTING_VPC_PEERING_REGIONS}" | jq -r "contains([\"ACCEPTER_REGION\"])") ]; then
      echo "VPC Peering between ${REQUESTER_REGION} and ${ACCEPTER_REGION} already exists"
    else
      REQUESTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCPeeringConnection'].OutputValue" --output text --region "${REQUESTER_REGION}")

      VPC_PEERING_OUTPUT=$(aws ec2 create-vpc-peering-connection \
        --peer-owner-id "${AWS_ACCOUNT_ID}" \
        --peer-vpc-id "${ACCEPTER_VPC_ID}" \
        --vpc-id "${REQUESTER_VPC_ID}" \
        --peer-region "${ACCEPTER_REGION}" \
        --region "${REQUESTER_REGION}" 
      )

      VPC_PEERING_OUTPUT
      accept-vpc-peering-connection --vpc-peering-connection-id 

    fi
  done
done

################################################
# Step 2: Add route for VPC peering
################################################

for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  if [ "${REGION}" != "${DEFAULT_REGION}" ]; then
    echo "Waiting until the Cloudformation stack is CREATE_COMPLETE for ${REGION}"
    if aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then     
      VPC_PEERING_CONNECTION=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCPeeringConnection'].OutputValue" --output text --region "${REGION}")
      VPC_CIDR_BLOCK=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCCidrBlock'].OutputValue" --output text --region "${REGION}")

      if [ -z "$(aws ec2 describe-route-tables --route-table-id "${MAIN_ROUTE_TABLE}" --query "RouteTables[].Routes[?DestinationCidrBlock=='${VPC_CIDR_BLOCK}'].VpcPeeringConnectionId" --output text)" ]; then
        # Doing this in the shell script, because doing the same in CloudFormation is pretty
        # tediuos as described in README.md, so doing it in AWS CLI
        echo "Adding VPC peering route to the route table of the main VPC"
        aws ec2 create-route \
          --route-table-id "${MAIN_ROUTE_TABLE}" \
          --destination-cidr-block "${VPC_CIDR_BLOCK}" \
          --vpc-peering-connection-id "${VPC_PEERING_CONNECTION}" \
          --output text
        echo "Main VPC's route table added a route for VPC Peering in ${REGION}"
      else
        echo "Main VPC's route table already has route for VPC Peering in ${REGION}"
      fi          
    else
      echo "ERROR: Could not add VPC peering to the route table of the main VPC"
    fi
  fi
done 
