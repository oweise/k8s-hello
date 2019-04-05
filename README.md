# k8s-hello

A demo project for:

- Deploying a Kubernetes Cluster in AWS via eksctl. The cluster will have 3 
  worker nodes of AWS instance type "t2.micro"
- Building a trivial Spring Boot Application via CodePipeline and deploying it 
  into the Kubernetes Cluster

... for usage as a blueprint for further projects to experiment with AWS on 
Kubernetes.

What you will need:

- [Git CLI](https://git-scm.com/). We are pretty confident you already have it.
- [eksctl CLI](https://github.com/weaveworks/eksctl), a convenience command 
  line tool to create EKS clusters, built by Weaveworks.
- An AWS account with the policy "AdministratorAccess" and its access and 
  secret key
- The [AWS CLI](https://aws.amazon.com/de/cli/), an Amazon tool to work with 
  AWS. It must be setup to use the account mentioned above.
- The [kubectl CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/), 
  the default Kubernetes client in version 1.11 or higher. This is not really 
  needed for setup but for everything you want to do with this cluster, so we 
  will ensure that it is configured to access the it.
- The [AWS IAM Authenticator](https://github.com/kubernetes-sigs/aws-iam-authenticator/releases).
  This is a tool that will allow kubectl to login to EKS with Amazon 
  credentials. You just need to download it and put it somewhere on your PATH. 
  You do not need to execute the setup procedure described on the projects 
  README. 

**WARNING:** 
This deployment will actually cause some costs on your AWS account. These 
should be kept small (*some* dollars) if you destroy the deployment once you 
finished working with it. If you keep it running for a longer time you will 
cause additional time-based costs for using certain resources (Kubernetes 
Masters, Load Balancers, EC2 instances depending on the instance type you use)
even if there is no actual traffic on it.
 
 **NOTE:**
 All command line instructions here are for Linux shells. On Windows you might 
 need to change the calls accordingly. You might want to consider using the 
 [Linux Subsystem for Windows 10](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 which allows you to use a native Linux shell, seamlessly integrated on Windows 
 10. Might spare you some nerves :)

## Preparations

These are preparations that you only need to do once for this project. Once 
they are completed you can create and destroy the Kubernetes cluster for this 
project, like described in the later chapters, as often as desired.

### Fork (or copy) this repository

For working with this repository we recommend forking it. This will allow you 
to bind your specific version of the project to your cluster.

Just use the "Fork" button on this repo. Make note of the repo URL of your fork 
for the next step. Of course you can also just create a copy if you plan to do 
something completely independent. 

### Checkout your fork/copy of the repository

To your local file system:

```
git clone <your-forks-repo-url>
```

### Create a Github access token

For automatically checking out your repo via AWS Code Build your Github account 
needs an access token.

- Got to URL `https://github.com/settings/tokens/new`
- Log in
- You are redirect to the creation of a new access token. Enter a name, e.g.
  "k8s-hello"
- Check "Repo" under Scopes
- Click button "Generate token"
- Copy the token created and displayed and store it somewhere safe. You will
  only be able to retrieve it right now! Don't give it away because it enables
  anybody to use Github via your account!


### Preparing environment variables ###

Within the root directory of the project, you will find a file 
`config.template.sh`. Copy this file to to `config.sh` in the same directory 
and edit its values accordingly.

---
***Hint***

To prevent accidental commitment of the file `config.sh` to your repository, 
you can add it to `.git/info/exclude`:
```
echo "config.sh" >> .git/info/exclude
```
---

### Preparing cluster definition file

Also there is a file "eksctl/cluster-definition.yaml". It contains a definition 
file for your Kubernetes cluster. Most of it is configured through 
aforementioned `config.sh`. For debugging purposes, however, it is recommended 
to add the path to your public SSH key:
``` 
apiVersion: eksctl.io/v1alpha4
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: eu-west-1
  tags:
    owner: ${OWNER}

nodeGroups:
- name: ng-1
  ami: ami-0a9006fb385703b54
  instanceType: m5.large
  desiredCapacity: 3
  allowSSH: true
  sshPublicKeyPath: <path to your ssh-key>
```

### Prepare parameters file for Cloud Formation

These parameters influence the build process of your project in AWS.

You find a file "cloudformation/parameters.json" in this repo which, again, is 
feeded with the environment variables from `config.sh`. Replacement of the 
environment variables through its values is done by the scripts `up.sh` and 
`down.sh` by calling `cat cloudformation/parameter.json | envsubst`.

```
[
  {
    "ParameterKey": "EksClusterName",
    "ParameterValue": "${CLUSTER_NAME}"
  },
  {
    "ParameterKey": "EksDeployerRoleName",
    "ParameterValue": "${DEPLOYER_ROLE_NAME}"
  },
  {
    "ParameterKey": "GitHubToken",
    "ParameterValue": "${GITHUB_TOKEN}"
  },
  {
    "ParameterKey": "GitHubUser",
    "ParameterValue": "${GITHUB_USER}"
  },
  {
    "ParameterKey": "GitBranch",
    "ParameterValue": "${GIT_BRANCH}"
  }
]
```

This file contains the mandatory parameters, expecting the following values: 
  
- GitHubToken: The Github Token for your account created earlier
- GitHubUser: Your Github user name, or more specific, the user name which owns 
  the repository fork
 
Other parameters can be added in the provided syntax. You will need these only 
if you copied the repository to create your own projects:

- GitSourceRepo: Name of the GitHub repository for checkout. 
- GitBranch: The branch to check out.
- CodeBuildDockerImage: AWS CodeBuild build image for the build job 

### Ensure correct region for AWS CLI
 
You should ensure that you create the resources in the same AWS region as your 
cluster has been created. If you kept the default that is "eu-west-1" 
(Ireland). If you use the Web Console you can choose the region by the "region" 
selector to the top right. If you use the AWS CLI the default region of your 
client config will be effective. You can review it by
 
```
aws configure list
```
 
You can set it by:
 
```
aws configure set region eu-west-1
``` 
 
## Deploy the cluster and a sample deployment

All you have to do is to call `./up.sh`. The script deplyos the AWS cluster,
3 worker nodes and a sample deployment for you.

To connect to the cluster, you need to update your `~/.kube/config`. This can 
be done through

```
aws eks update-kubeconfig --name <your-cluster-name>
```

After that, you should be able to see the nodes of the cluster:
```
kubectl get nodes
NAME                                       STATUS   ROLES    AGE   VERSION
ip-x-y-z-a.eu-west-1.compute.internal      Ready    <none>   28s   v1.10.3
ip-x-y-z-b.eu-west-1.compute.internal      Ready    <none>   30s   v1.10.3
ip-x-y-z-c.eu-west-1.compute.internal      Ready    <none>   54s   v1.10.3
```

If the code has already been built and deployed through the code pipeline, you
can see its services:

```
kubectl get services
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)        AGE
k8s-hello    LoadBalancer   10.100.56.190   aaa273255576f11e99b6206ef50eda23-317929946.eu-west-1.elb.amazonaws.com   80:31696/TCP   1m
kubernetes   ClusterIP      10.100.0.1      <none>                                                                   443/TCP        17h

```

Accessing the `EXTERNAL-IP` of the `LoadBalancer` in a browser should show the 
following (or a similar) result:
```
Hi (0, k8s-hello-786cdcbc88-zqwf5)
```

## Additional features

You can deploy a Kubernetes dashboard by following the README instructions in 
subdir "dashboard" of this repo.

## Clean up

As with deployment, shutdown is done through a script `down.sh`, that removes
resources created (including the kubernetes-deployment, worker nodes, and the 
cluster itself).

Please pay close attention to any error messages during shutdown to catch 
potentially undeleted resources. 