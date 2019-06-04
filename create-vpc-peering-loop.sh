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

################################################
# Step 1: Create VPC Peering in all the regions
################################################
for ACCEPTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  EXISTING_VPC_PEERING_REGIONS=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${ACCEPTER_VPC_ID}'].RequesterVpcInfo.Region" --region "${ACCEPTER_REGION}")
  for REQUESTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
  do
    if [ "true" = $(echo "${EXISTING_VPC_PEERING_REGIONS}" | jq -r "contains([\"${ACCEPTER_REGION}\"])") ]; then
      echo "VPC Peering between ${REQUESTER_REGION} and ${ACCEPTER_REGION} already exists"
    else
      # If it fails, an error message is displayed and it continues to the next REGION
      ./create-vpc-peering.sh --stack-name "${STACK_NAME}" -accepter-region "${ACCEPTER_REGION}" --requester-region "${REQUESTER_REGION}"
    fi
  done
done

# ################################################
# # Step 2: Add route for VPC peering
# ################################################

# for SOURCE_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
# do 
#   for TARGET_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
#   do
#     VPC_PEERING_CONNECTION=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${ACCEPTER_VPC_ID}'].RequesterVpcInfo.Region" --region "${SOURCE_REGION}")
#     VPC_CIDR_BLOCK=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCCidrBlock'].OutputValue" --output text --region "${REGION}")

#     if [ -z "$(aws ec2 describe-route-tables --route-table-id "${MAIN_ROUTE_TABLE}" --query "RouteTables[].Routes[?DestinationCidrBlock=='${VPC_CIDR_BLOCK}'].VpcPeeringConnectionId" --output text)" ]; then
#       # Doing this in the shell script, because doing the same in CloudFormation is pretty
#       # tediuos as described in README.md, so doing it in AWS CLI
#       echo "Adding VPC peering route to the route table of the main VPC"
#       aws ec2 create-route \
#         --route-table-id "${MAIN_ROUTE_TABLE}" \
#         --destination-cidr-block "${VPC_CIDR_BLOCK}" \
#         --vpc-peering-connection-id "${VPC_PEERING_CONNECTION}" \
#         --output text
#       echo "Main VPC's route table added a route for VPC Peering in ${REGION}"
#     else
#       echo "Main VPC's route table already has route for VPC Peering in ${REGION}"
#     fi          
#     else
#       echo "ERROR: Could not add VPC peering to the route table of the main VPC"
#     fi
#   fi
# done 
