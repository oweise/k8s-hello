# k8s-hello

A demo project for:

- Deploying a Kubernetes Cluster in AWS via eksctl. The cluster will have 3 worker nodes of AWS instance type "t2.micro"
- Building a trivial Spring Boot Application via CodePipeline and deploying it into the Kubernetes Cluster

... for usage as a blueprint for further projects to experiment with AWS on Kubernetes.

What you will need:

- [Git CLI](https://git-scm.com/). We are pretty confident you already have it.
- [eksctl CLI](https://github.com/weaveworks/eksctl), a convenience command line tool to create EKS clusters, built by
  Weaveworks.
- An AWS account with the policy "AdministratorAccess" and its access and secret key
- The [AWS CLI](https://aws.amazon.com/de/cli/), an Amazon tool to work with AWS. It must be setup to use the account 
  mentioned above.
- The [kubectl CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/), the default 
  Kubernetes client in version 1.11 or higher. This is not really needed for setup but for everything 
  you want to do with this cluster, so we will ensure that it is configured to access the it.
- The [AWS IAM Authenticator](https://github.com/kubernetes-sigs/aws-iam-authenticator/releases). This is a tool that 
  will allow kubectl to login to EKS with Amazon credentials. You just need to download it and put it somewhere on your
  PATH. You do not need to execute the setup procedure described on the projects README. 

**WARNING:** This deployment will actually cause some costs on your AWS account. These should be kept small 
(*some* dollars) if you destroy the deployment once you finished working with it. If you keep it running for
 a longer time you will cause additional time-based costs for using certain resources (Kubernetes Masters, 
 Load Balancers, EC2 instances depending on the instance type you use) even if there is no actual traffic on it.
 
 **NOTE:** All command line instructions here are for Linux shells. On Windows you might need to change the calls
 accordingly. You might want to consider using the [Linux Subsystem for Windows 10](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 which allows you to use a native Linux shell, seamlessly integrated on Windows 10. Might spare you some nerves :)

## Preparations

These are preparations that you only need to do once for this project. Once they are completed you can create and
destroy the Kubernetes cluster for this project, like described in the later chapters, as often as desired.

### Fork (or copy) this repository

For working with this repository we recommend forking it. This will allow you to bind your specific version of the
 project to your cluster.

Just use the "Fork" button on this repo. Make note of the repo URL of your fork for the next step.
Of course you can also just create a copy if you plan to do something completely independent. 

### Checkout your fork/copy of the repository

To your local file system:

```
git clone <your-forks-repo-url>
```

### Create a Github access token

For automatically checking out your repo via AWS Code Build your Github account needs an access token.

- Got to URL `https://github.com/settings/tokens/new`
- Log in
- You are redirect to the creation of a new access token. Enter a name, e.g. "k8s-hello"
- Check "Repo" under Scopes
- Click button "Generate token"
- Copy the token created and displayed and store it somewhere safe. You will only be able to retrieve it right now!. 
Don't give it away because it enables anybody to use Github via your account!

### Preparing cluster definition file

Also there is a file "eksctl/cluster-definition.yaml". It contains a definition file for
your Kubernetes cluster.

``` 
apiVersion: eksctl.io/v1alpha4
kind: ClusterConfig

metadata:
  name: k8s-hello
  region: eu-west-1
  tags:
    owner: your-user-name

nodeGroups:
- name: ng-1
  instanceType: t2.micro
  desiredCapacity: 3
  ```

Please set individual values in this file for the properties:
 
- "metadata.name" - This is your cluster name. Should be unique on your AWS account.
- "metadata.tags.owner" - Your name that will be stored in a tag named "owner" on all resources that are created
for this cluster

### Prepare parameters file for Cloud Formation

These parameters influence the build process of your project in AWS.

You find a file "cloudformation/parameters-template.json" in this repo, providing the structure of a parameters
file that can be used as input:

```
[
  {
    "ParameterKey": "EksClusterName",
    "ParameterValue": "k8s-hello"
  },
  {
    "ParameterKey": "GitHubToken",
    "ParameterValue": "<your-token>"
  },
  {
    "ParameterKey": "GitHubUser",
    "ParameterValue": "<your-user-name>"
  }
]
```

Copy it over to a location OUTSIDE this repo to keep it from getting checked in. 
Fill it with your individual parameter values. 

This file contains the mandatory parameters, expecting the following values: 
  
- EksClusterName: Name of the EKS cluster. Use the same name as in the previous step.
- GitHubToken: The Github Token for your account created earlier
- GitHubUser: Your Github user name, or more specific, the user name which owns the repository fork
 
Other parameters can be added in the provided syntax. You will need these only if you copied the repository
to create your own projects:

- GitSourceRepo: Name of the GitHub repository for checkout. (Default: k8s-hello)
- GitBranch: The branch to check out (Default: master)
- CodeBuildDockerImage: AWS CodeBuild build image for the build job (Default: aws/codebuild/java:openjdk-8)
- KubectlRoleName: The AWS IAM role by which kubectl works with the cluster (Default: k8s-hello-codebuild-role)

### Ensure correct region for AWS CLI
 
You should ensure that you create the resources in the same AWS region as your cluster has been
created. If you kept the default that is "eu-west-1" (Ireland). If you use the Web Console you can choose the region
by the "region" selector to the top right. If you use the AWS CLI the default region of your client config will be
effective. You can review it by
 
```
aws configure list
```
 
You can set it by:
 
```
aws configure set region eu-west-1
``` 

## Deploying Kubernetes

We will use the eksctl tool for this.

### Create Cluster

eksctl will reuse the AWS credentials that were setup for the AWS CLI, so we do not need to configure it if this is 
setup.

In your command line change to the root dir of the project then execute:

```
eksctl create cluster -f eksctl/cluster-definition.yaml
```

After quite some time (several minutes) of work your Kubernetes Cluster should be up and running.

### Check connection to Kubernetes Cluster via kubectl

After creation your kubectl should already have a context configured by which you can access the cluster.

```
kubectl get nodes
```

Output should be like this after some time:

```
NAME                                       STATUS   ROLES    AGE   VERSION
ip-10-0-0-25.eu-west-1.compute.internal    Ready    <none>   28s   v1.10.3
ip-10-0-1-21.eu-west-1.compute.internal    Ready    <none>   30s   v1.10.3
ip-10-0-1-60.eu-west-1.compute.internal    Ready    <none>   54s   v1.10.3
```

## Deploy Code Pipeline

The code pipeline executes an "AWS CodeBuild" build which does the following:
 
- Checks out your repository
- Builds the maven project according to your pom.xml in the root folder
- Creates a docker image according to the Dockerfile in the root folder
- Deploys a Kubernetes deployment and service according to the k8s.yml in the root folder

This process is defined in file "buildspec.yml", also in the root folder. 

We currently create this process by applying a "CloudFormation" template (which is the native "Infrastructure as Code"
 tool of AWS). For applying it we use can use the AWS CLI (explained below). You could also use the AWS Web Console,
 Service "Cloud Formation",   with the file "cloudformation/code-pipeline.yml" in this repository
 and provide the parameters that are discussed below manually.
 
### Create a cloud formation stack

We do this via AWS CLI. From the project root dir execute the
following command, replacing:
 
- <your-parameters-file-path> with the location of the Cloud Formation parameters file you created
in the preparations
- <your-cluster-name> with the name of your EKS cluster used in the preparations. It has no direct relation to that
name but that way we ensure that the cloud formation stack is also uniquely named. 

```
aws cloudformation create-stack --stack-name=<your-cluster-name> --template-body file://cloudformation/code-pipeline.yml --parameters file://<your-parameters-file-path> --capabilities CAPABILITY_IAM
``` 

This will return immediately with the AWS ARN identifier of this stack, which however is still in the process of being
created. Execute the following command to wait until the stack creation is complete:

```
aws cloudformation wait stack-create-complete --stack-name=<your-cluster-name>
```

After this the code pipeline is effectively set up! The first build will start automatically and in the end deploy
to your Kubernetes cluster. You can watch the deployment, pods and service come up once they are ready:

```
kubectl get all
```

Output should be similar to this after the build finishes:

```
NAME                             READY   STATUS    RESTARTS   AGE
pod/k8s-hello-786cdcbc88-xtwpg   1/1     Running   0          11m
pod/k8s-hello-786cdcbc88-zqwf5   1/1     Running   0          11m

NAME                 TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)        AGE
service/k8s-hello    LoadBalancer   172.20.203.29   <some-dns-name>   80:31274/TCP   11m
service/kubernetes   ClusterIP      172.20.0.1      <none>                                                                   443/TCP        1h

NAME                        DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/k8s-hello   2         2         2            2           11m

NAME                                   DESIRED   CURRENT   READY   AGE
replicaset.apps/k8s-hello-786cdcbc88   2         2         2       11m
```

Specifically watch out for the "service/k8s-hello" entry. The "EXTERNAL-IP" given out there is the DNS name by which
you can reach the endpoint of your application. Using it in the browser should put out something like this:

```
Hi (0, k8s-hello-786cdcbc88-zqwf5)
```

Again, it might take some time for this to get available!

## Additional features

You can deploy a Kubernetes dashboard by following the README instructions in subdir "dashboard" of this repo.

## Clean up

To keep your cluster from causing costs you can pull everything down again like follows:

### Delete kubernetes resources

Although we did not explicitly create Kubernetes resources like deployments and services- the build pipeline did that
for us - we should delete them before we pull down the Kubernetes cluster to to allow connected AWS resources
(f.e. Load Balancers) to also be wiped.

We do this via kubectl. Move to the root directory of the repo and run:

```
kubectl delete -f k8s.yml
```

### Remove CloudFormation Stack with build pipeline

Now onto the build pipeline. Run:

```
aws cloudformation delete-stack --stack-name=k8s-hello
aws cloudformation wait stack-delete-complete --stack-name=k8s-hello
```

### Remove Kubernetes cluster

Move to the root directory of your project then run:

```
eksctl delete cluster -f eksctl/cluster-definition.yaml
```

This will pull everything down. However this command will exit early before everything was deleted.
You can wait for the deletion of the stack by calling:

```
aws cloudformation wait stack-delete-complete --stack-name=eksctl-<your-cluster-name>-cluster
```

After several minutes all AWS resources should be gone again!

### Check that everything causing costs is gone

This is normally not necessary, but just to be sure, go to your AWS console and check that at the following locations
nothing remains that was used for your cluster:

- EC2 Instances
- EC2 Load Balancers
- EKS Clusters