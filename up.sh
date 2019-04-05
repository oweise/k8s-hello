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

echo "========================================================================="
echo "k8s-hello: Create Deploy Role and grant Kubernetes Access"
echo "========================================================================="

if aws cloudformation describe-stack-resources --stack-name=${DEPLOYER_ROLE_STACK_NAME} > /dev/null 2>&1; then
  echo "Role stack already exists. Updating it  ...."
  aws cloudformation update-stack \
        --stack-name=${DEPLOYER_ROLE_STACK_NAME} \
        --template-body file://cloudformation/create-deployer-role.yml \
        --parameters ParameterKey=DeployerRoleName,ParameterValue=${DEPLOYER_ROLE_NAME} \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    > /dev/null 2>&1
else
  aws cloudformation create-stack \
        --stack-name=${DEPLOYER_ROLE_STACK_NAME} \
        --template-body file://cloudformation/create-deployer-role.yml \
        --parameters ParameterKey=DeployerRoleName,ParameterValue=${DEPLOYER_ROLE_NAME} \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      > /dev/null 2>&1
  aws cloudformation wait stack-create-complete --stack-name ${DEPLOYER_ROLE_STACK_NAME}
fi

aws eks --region eu-west-1 update-kubeconfig --name ${CLUSTER_NAME} >/dev/null 2>&1

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE="    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/${DEPLOYER_ROLE_NAME}\n      username: build\n      groups:\n        - system:masters"

kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > tmp/aws-auth-patch.yml

kubectl patch configmap/aws-auth -n kube-system --patch "$(cat tmp/aws-auth-patch.yml)"

kubectl patch configmap/aws-auth -n kube-system --patch "$(cat tmp/aws-auth-patch.yml)" >/dev/null 2>&1
rm tmp/aws-auth-patch.yml

echo "========================================================================="
echo "k8s-hello: Creating Project Pipeline"
echo "========================================================================="

cat cloudformation/parameters.json | envsubst > tmp/parameters.json

if aws cloudformation describe-stack-resources --stack-name=${PIPELINE_STACK_NAME} > /dev/null 2>&1; then
  echo "Pipeline stack already exists. Updating it  ...."
  aws cloudformation update-stack \
        --stack-name=${PIPELINE_STACK_NAME} \
        --template-body file://cloudformation/code-pipeline.yml \
        --parameters file://tmp/parameters.json \
        --capabilities CAPABILITY_IAM \
      > /dev/null 2>&1

    if [ "$?" == "0" ]; then
        aws cloudformation wait stack-update-complete \
            --stack-name=${PIPELINE_STACK_NAME}
    fi

    rm tmp/parameters.json
else
    aws cloudformation create-stack \
          --stack-name=${PIPELINE_STACK_NAME} \
          --template-body file://cloudformation/code-pipeline.yml \
          --parameters file://tmp/parameters.json \
          --capabilities CAPABILITY_IAM \
        > /dev/null 2>&1

    rm tmp/parameters.json

    aws cloudformation wait stack-create-complete \
        --stack-name=${PIPELINE_STACK_NAME}
fi

echo "========================================================================="
echo "k8s-hello: FINISHED"
echo "========================================================================="

rmdir tmp