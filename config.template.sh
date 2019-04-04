#!/usr/bin/env bash
export CLUSTER_NAME=k8s-hello
export GITHUB_TOKEN="<enter token here>"
export GITHUB_USER="<enter user here>"
export CODEBUILD_DOCKERIMAGE="aws/codebuild/java:openjdk-8"
export OWNER="<your name here>"

export DEPLOYER_ROLE_NAME=k8s-deployer
export DEPLOYER_ROLE_STACK_NAME=${CLUSTER_NAME}-deployer-role
export PIPELINE_STACK_NAME=${CLUSTER_NAME}-pipeline
export GIT_BRANCH=$(git branch | grep \* | cut -d ' ' -f2)