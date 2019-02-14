# k8s-hello

A demo project for:

- Deploying a Kubernetes Cluster in AWS via Terraform. The cluster will have 3 worker nodes of AWS instance type "t2.micro"
- Building a trivial Spring Boot Application via CodePipeline and deploying it into the Kubernetes Cluster

... for usage as a blueprint for further projects to experiment with AWS on Kubernetes.

What you will need:

- [Git CLI](https://git-scm.com/)
- [Terraform CLI](https://www.terraform.io/)
- [kubectl CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- An AWS account with the policy "AdministratorAccess" and its access and secret key
- The [AWS CLI](https://aws.amazon.com/de/cli/), setup to use the account mentioned above

**WARNING:** This deployment will actually cause some costs on your AWS account. These should be kept small 
(*some* dollars) if you destroy the deployment once you finished working with it. If you keep it running for
 a longer time you will cause additional time-based costs for using certain resources (Kubernetes Masters, Load Balancers)
 even if there is no actual traffic on it.
 
 **NOTE:** All command line instructions here are for Linux shells. On Windows you might need to change the calls
 accordingly. You might want to consider using the [Linux Subsystem for Windows 10](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 which allows you to use a native Linux shell, seamlessly integrated on Windows 10.

## Preparations

These are preparations that you only need to do once for this project. Once they are completed you can create and
destroy your Kubernetes cluster, like described in the later chapters, as often as desired based on your
project.

### Fork (or copy) this repository

For working with this repository we recommend forking it. This will allow you to bind your specific version of the
 project to your cluster.

Just use the "Fork" button on this repo. Make note of the repo URL of your fork for the next step.
Of course you can also just create a copy if you plan to do something completely independent. 

### Checkout your fork of the repository

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

### Prepare AWS credential file

You need to create a terraform variable file containing your AWS account credentials.
That is a simple text file with the following content:

```
access_key = "<Replace with AWS access key>"
secret_key = "<Replace with AWS secret key>"
```

You find a template of it under "terraform/aws-credentials-template.vars" in this repo. Copy it
over to a location OUTSIDE this repository to keep it from being checked in. Fill it with your information. 

### Prepare parameters file for Cloud Formation

These parameters influence the build process of your project in AWS.

You find a file "cloudformation/parameters-template.json" in this repo, providing the structure of a parameters
file that can be used as input:

```
[
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
  
- GitHubToken: The Github Token for your account created earlier
- GitHubUser: Your Github user name, or more specific, the user name which owns the repository fork
 
Other parameters can be added in the provided syntax. You will need these only if you create your own projects
based on this one with different settings or if you want to modify how this build works:

- EksClusterName: Name of the cluster. Needs to be the same as in Terraform (Default: k8s-hello)
- GitSourceRepo: Name of the GitHub repository for checkout (Default: k8s-hello)
- GitBranch: The branch to check out (Default: master)
- CodeBuildDockerImage: AWS CodeBuild build image for the build job (Default: aws/codebuild/java:openjdk-8)
- KubectlRoleName: The AWS IAM role by which kubectl works with the cluster (Default: k8s-hello-codebuild-role)

### Preparing project tags file

Also there is a file "terraform/project-tags.auto.tfvars". It contains values that will end up
as tags of the created AWS resources. You can use these tags later to determine the resources that were
created on behalf of your project.

Please set individual values in this file for the "user_name" and "project_name" variables.

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

### Initialize Terraform

Terraform needs to initialize the state of this project and download necessary addons. On command line move into
subdir "terraform" and run:

```
terraform init 
```

## Deploying Kubernetes

We will mainly use Terraform templates for this stored in subfolder "terraform" of this repository.

### Initialize and apply terraform templates

In your command line change to the subdir "terraform" of this repository. Then execute

```
terraform apply --var-file=<your-aws-credentials-file>
```
Terraform will first check what resources to create, then list them to you. To actually start deploying type "yes" 
and hit enter.

After quite some time (several minutes) of work your Kubernetes Cluster should be up and running.

**NOTE:** The cluster will be created in AWS region "eu-west-1" (Ireland). To change this you could provide a var
"region" with your preferred region identifier via command line parameter "--var 'regionÜ=<your-identifier>'". But
You will need to also use that region further down this setup.

### Connect to Kubernetes Cluster via kubectl

After execution Terraform is able to put out a kubectl configuration to connect to the new cluster via the following
command (still in the "terraform" directory):

```
terraform output kubeconfig
```

Move that into a file. For example, to store it into the ".kube" directory: 

```
terraform output kubeconfig > ~/.kube/config-eks-on-aws
```

You can use this config for kubectl by pointing environment variable "KUBECONFIG" to it:

```
export KUBECONFIG=$KUBECONFIG:~/.kube/config-eks-on-aws
```

Then you can try if your kubectl can access the cluster. For example, to list the pods on the cluster:

```
kubectl get pods --all-namespaces
```

After some time the output might be similar to this:

```
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
kube-system   coredns-7554568866-k78w7   0/1     Pending   0          5m
kube-system   coredns-7554568866-vpl6d   0/1     Pending   0          5m
```

### Register Kubernetes nodes

One additional step is needed to actually register the Kubernetes worker nodes created by Terraform with
the cluster. Terraform can put out a Kubernetes config map that this necessary contains registration information.
Generate it and store it in some temporary file:

```
terraform output config_map_aws_auth > <temp-configmap-file-name> 
```

Then use kubectl to apply it:

``` 
kubectl apply -f <temp-configmap-file-name>
```

After that check that the nodes actually connect:

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

We do this via AWS CLI. On command line move to the "cloudformation" subdir in this repository, then execute the
following, replacing <your-parameters-file-path> with the location of the Cloud Formation parameters file you created
in the preparations:

```
aws cloudformation create-stack --stack-name=k8s-hello --template-body file://code-pipeline.yml --parameters file://<your-parameters-file-path> --capabilities CAPABILITY_IAM
``` 

This will return immediately with the AWS ARN identifier of this stack, which however is still in the process of being
created. Execute the following command to wait until the stack creation is complete:

```
aws cloudformation wait stack-create-complete --stack-name=k8s-hello
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

Again move to the "terraform" directory of your repository then run:

```
terraform destroy --var-file=<your-aws-credentials-file>
```

Terraform will again list all resources that will get removed. Type "yes" to confirm.

After several minutes all AWS resources should be gone again!

**NOTE:** In some occasions the terraform destroy command may time out before the some resources, mostly the internet
gateway, the subnets and the VPC have been removed. In that case you can simply repeat the destroy operation until
everything has been removed!