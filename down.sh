#!/usr/bin/env bash

. config.sh

mkdir -p tmp

echo "========================================================================="
echo "k8s-hello: Delete Kubernetes entities"
echo "========================================================================="

kubectl delete -f k8s.yml

echo "========================================================================="
echo "k8s-hello: Deleting Project Pipeline"
echo "========================================================================="

if aws cloudformation describe-stack-resources --stack-name=${PIPELINE_STACK_NAME} >> /dev/null; then
    aws cloudformation delete-stack --stack-name=${PIPELINE_STACK_NAME}
    aws cloudformation wait stack-delete-complete --stack-name=${PIPELINE_STACK_NAME}
    aws s3 rb s3://${PIPELINE_STACK_NAME}-bucket --force >> /dev/null
    aws ecr delete-repository --repository-name=${PIPELINE_STACK_NAME}-repository --force >> /dev/null
else
    echo "Pipeline stack does not exist. Skipping ..."
fi

echo "========================================================================="
echo "k8s-hello: Deleting Deploy role"
echo "========================================================================="
if aws cloudformation describe-stack-resources --stack-name=${DEPLOYER_ROLE_STACK_NAME} >> /dev/null; then
    aws cloudformation delete-stack --stack-name=${DEPLOYER_ROLE_STACK_NAME}
    aws cloudformation wait stack-delete-complete --stack-name=${DEPLOYER_ROLE_STACK_NAME}
else
    echo "Deployer role stack does not exist. Skipping ..."
fi

echo "========================================================================="
echo "k8s-hello: Deleting EKS cluster"
echo "========================================================================="

if eksctl get cluster ${CLUSTER_NAME} > /dev/null; then
    cat eksctl/cluster-definition.yaml | envsubst > tmp/cluster-definition.yaml
    eksctl delete cluster -f tmp/cluster-definition.yaml
    aws cloudformation wait stack-delete-complete --stack-name=eksctl-${CLUSTER_NAME}-cluster
    rm tmp/cluster-definition.yaml
else
    echo "EKS cluster does not exist. Skipping ..."
fi

echo "========================================================================="
echo "k8s-hello: FINISHED"
echo "========================================================================="

rmdir tmp