#!/bin/sh

for OPT in "$@"
do
  case "$OPT" in
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

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ACCEPTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${ACCEPTER_REGION}")
REQUESTER_VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[?OutputKey=='VPCId'].OutputValue" --output text --region "${REQUESTER_REGION}")

VPC_PEERING_OUTPUT=$(aws ec2 create-vpc-peering-connection \
  --peer-owner-id "${AWS_ACCOUNT_ID}" \
  --peer-vpc-id "${ACCEPTER_VPC_ID}" \
  --vpc-id "${REQUESTER_VPC_ID}" \
  --peer-region "${ACCEPTER_REGION}" \
  --region "${REQUESTER_REGION}" 
)
if [ $? -ne 0 ] ; then
  exit 1
fi

VPC_PEERING_ID=$(echo "${VPC_PEERING_OUTPUT}" | jq -r ".VpcPeeringConnection.VpcPeeringConnectionId")
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "${VPC_PEERING_ID}" --region "${ACCEPTER_REGION}" > /dev/null
if [ $? -ne 0 ] ; then
  exit 1
fi
