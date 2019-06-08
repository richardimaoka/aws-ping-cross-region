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

for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text)
do
  echo "Terminating the EC2 instance in ${REGION}"
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:experiment-name,Values=${STACK_NAME}" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text \
    --region "${REGION}"
  )
  aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" --region "${REGION}"
done
