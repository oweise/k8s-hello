#!/usr/bin/env bash

. config.sh

mkdir -p tmp

echo "========================================================================="
echo "k8s-hello: Creating EKS cluster"
echo "========================================================================="
if eksctl get cluster ${CLUSTER_NAME} >/dev/null 2>&1; then
   echo "EKS cluster already exists. Skipping ...."
else
  cat eksctl/cluster-definition.yaml | envsubst > tmp/cluster-definition.yaml
  eksctl create cluster -f tmp/cluster-definition.yaml
  rm tmp/cluster-definition.yaml
fi

#echo "========================================================================="
#echo "k8s-hello: Creating Project Pipeline"
#echo "========================================================================="

#cat cloudformation/parameters.json | envsubst > tmp/parameters.json

#if aws cloudformation describe-stack-resources --stack-name=${PIPELINE_STACK_NAME} >/dev/null 2>&1; then
#  echo "Pipeline stack already exists. Updating it  ...."
#  aws cloudformation update-stack \
#        --stack-name=${PIPELINE_STACK_NAME} \
#        --template-body file://cloudformation/code-pipeline.yml \
#        --parameters file://tmp/parameters.json \
#        --capabilities CAPABILITY_IAM
#
#    if [ "$?" == "0" ]; then
#        aws cloudformation wait stack-update-complete \
#            --stack-name=${PIPELINE_STACK_NAME}
#    fi
#
#    rm tmp/parameters.json
#else
    aws cloudformation create-stack \
        --stack-name=${PIPELINE_STACK_NAME} \
        --template-body file://cloudformation/code-pipeline.yml \
        --parameters file://tmp/parameters.json \
        --capabilities CAPABILITY_IAM
#
#    rm tmp/parameters.json

#    aws cloudformation wait stack-create-complete \
#        --stack-name=${PIPELINE_STACK_NAME}
#fi

#echo "========================================================================="
#echo "k8s-hello: Grant CodeBuild User Kubernetes Access"
#echo "========================================================================="

#quotedRole=$(aws cloudformation describe-stack-resource \
#    --stack-name=${PIPELINE_STACK_NAME} \
#    --logical-resource-id=CodeBuildServiceRole --query StackResourceDetail.PhysicalResourceId)
#quotedRole="${quotedRole%\"}"
#quotedRole="${quotedRole#\"}"
#export AWS_ROLE_NAME=$quotedRole

#export AWS_ROLE_ARN=$(aws iam get-role --role-name ${AWS_ROLE_NAME} --output json \
#    --query Role.Arn)

#cat eksctl/aws-auth.yaml | envsubst | kubectl apply -f -

echo "========================================================================="
echo "k8s-hello: FINISHED"
echo "========================================================================="

rmdir tmp