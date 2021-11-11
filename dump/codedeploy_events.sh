#!/bin/bash

aws_service_status() {
  echo $(aws deploy get-deployment --deployment-id $1 --query "deploymentInfo.status" --output text)
}

dump_api_events(){
  aws deploy get-deployment --deployment-id $1 --query "deploymentInfo.deploymentOverview" | jq -r '[.Pending, .InProgress, .Succeeded, .Failed, .Skipped, .Ready] | @tsv'
}

STACK_STATUS=$(aws_service_status $1)
echo pending progres success failed skipped ready
while [ "${STACK_STATUS}" = "InProgress" ]
do
  dump_api_events $1
  sleep 2
  STACK_STATUS=$(aws_service_status $1)
done
dump_api_events $1