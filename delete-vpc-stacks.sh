#!/bin/sh

STACK_NAME="PingCrossRegionExperiment"

for REGION in $(aws ec2 describe-regions --query "Regions[].RegionName" | jq -r '.[]')
do 
  echo "Deleting the CloudFormation stack=${STACK_NAME} for region=${REGION} if exists."
  aws cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}"
done 
