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

###################################################
# Step 1: Wait on CloudFormation VPC stack creation
###################################################
for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
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

for ACCEPTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  ACCEPTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${ACCEPTER_REGION}")
  VPC_PEERING_IN_ACCEPTER_VPC=$(aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?Status.Code!='deleted']" --region "${ACCEPTER_REGION}")
  
  for REQUESTER_REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
  do
    if [ "${ACCEPTER_REGION}" != "${REQUESTER_REGION}" ] ; then
      REQUESTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REQUESTER_REGION}")


      if [ -n $(echo "${VPC_PEERING_IN_ACCEPTER_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${ACCEPTER_REGION}\") | select(.RequesterVpcInfo.VpcId==\"${REQUESTER_REGION}\")") ] || \
         [ -n $(echo "${VPC_PEERING_IN_ACCEPTER_VPC}" | jq -r ".[] | select(.AccepterVpcInfo.VpcId==\"${REQUESTER_REGION}\") | select(.RequesterVpcInfo.VpcId==\"${ACCEPTER_REGION}\")") ] ; then
        echo "VPC Peering between ${ACCEPTER_REGION} and ${REQUESTER_REGION} already exists"
      else
        echo "Creating VPC Peering between ACCEPTER_REGION=${ACCEPTER_REGION} and REQUESTER_REGION=${REQUESTER_REGION}"
        # If it fails, an error message is displayed and it continues to the next REGION
        VPC_PEERING_OUTPUT=$(aws ec2 create-vpc-peering-connection \
          --peer-owner-id "${AWS_ACCOUNT_ID}" \
          --peer-vpc-id "${ACCEPTER_VPC_ID}" \
          --vpc-id "${REQUESTER_VPC_ID}" \
          --peer-region "${ACCEPTER_REGION}" \
          --region "${REQUESTER_REGION}" 
        )
      fi
    fi      
  done
done

################################################
# Step 3: Accept VPC Peering requests
################################################
# for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
# do 
#   for VPC_PEERING_ID in aws ec2 describe-vpc-peering-connections --query "VpcPeeringConnections[?AccepterVpcInfo.VpcId=='${ACCEPTER_VPC_ID}' && Status.Code=='pending'].VpcPeeringConnectionId" --region "${REGION}")
#   do
#     echo "Accepting ${VPC_PEERING_ID} in ${REGION}"
#     # If it fails, an error message is displayed and it continues to the next REGION
#     aws ec2 accept-vpc-peeringq-connection --vpc-peering-connection-id "${VPC_PEERING_ID}" --region "${ACCEPTER_REGION}"
#   done
# done

# ################################################
# # Step 3: Add route for VPC peering
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
