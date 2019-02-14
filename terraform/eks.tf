provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

# This data source is included for ease of sample architecture deployment
# and can be swapped out as necessary.
data "aws_availability_zones" "available" {}

# This data source provides access to the effective Account ID, User ID,
# and ARN
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    user = "${var.user_name}",
    project = "${var.project_name}"
  }
}

#
# Setup the VPC with:
# - two subnets
# - an internet gateway
# - a router
#

resource "aws_vpc" "k8s_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = "${merge(
    local.common_tags,
    map(
     "Name", "${var.cluster-name}-node",
     "kubernetes.io/cluster/${var.cluster-name}", "shared"
    )
  )}"
}

resource "aws_subnet" "k8s_subnet" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = "${aws_vpc.k8s_vpc.id}"

  tags = "${merge(
    local.common_tags,
    map(
     "Name", "${var.cluster-name}-node",
     "kubernetes.io/cluster/${var.cluster-name}", "shared"
    )
  )}"
}

resource "aws_internet_gateway" "k8s_ig" {
  vpc_id = "${aws_vpc.k8s_vpc.id}"

  tags = "${merge(
    local.common_tags,
    map(
    "Name", "${var.cluster-name}"
    )
  )}"
}

resource "aws_route_table" "k8s_rt" {
  vpc_id = "${aws_vpc.k8s_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.k8s_ig.id}"
  }

  tags = "${local.common_tags}"
}

resource "aws_route_table_association" "k8s_rta" {
  count = 2

  subnet_id      = "${aws_subnet.k8s_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.k8s_rt.id}"
}

#
# Create CodePipeline Role
#

output "account_id" {
  value = "${data.aws_caller_identity.current.account_id}"
}

# create role for CodeBuild that can interact with EKS cluster
resource "aws_iam_role" "codebuild-role" {
  name = "${var.cluster-name}-codebuild-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = "${local.common_tags}"
}

resource "aws_iam_role_policy" "codebuild-role-policy" {
  name = "${var.cluster-name}-codebuild-role-policy"
  role = "${aws_iam_role.codebuild-role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "eks:Describe*",
      "Effect": "Allow",
      "Resource":"*"
    }
  ]
}
EOF
}


#
# EKS Master Cluster
#

# Setup the EKS Master Cluster IAM Role
# Amazon EKS makes calls to other AWS services on your behalf to manage the
# resources that you use with the service. Before you can use the service, you
# must create an IAM role with the following IAM policies:
# - AmazonEKSServicePolicy
# - AmazonEKSClusterPolicy
# More details on the policies can be found here:
# https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html#create-service-role

resource "aws_iam_role" "master_role" {
  name = "${var.cluster-name}-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = "${local.common_tags}"
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.master_role.name}"
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.master_role.name}"
}


# EKS Master Cluster Security Group
# This security group controls networking access to the Kubernetes masters.
# We will later configure this with an ingress rule to allow traffic from the
# worker nodes.

resource "aws_security_group" "master_sg" {
  name        = "${var.cluster-name}-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.k8s_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${merge(
    local.common_tags,
    map(
    "Name", "${var.cluster-name}"
    )
  )}"
}

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
#resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
#  cidr_blocks       = ["94.185.91.252/32"]
#  description       = "Allow workstation to communicate with the cluster API Server"
#  from_port         = 443
#  protocol          = "tcp"
#  security_group_id = "${aws_security_group.master_sg.id}"
#  to_port           = 443
#  type              = "ingress"
#}


# EKS Master Cluster
# This resource is the actual Kubernetes master cluster.

resource "aws_eks_cluster" "demo" {
  name            = "${var.cluster-name}"
  role_arn        = "${aws_iam_role.master_role.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.master_sg.id}"]
    subnet_ids         = ["${aws_subnet.k8s_subnet.*.id}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy",
  ]
}

# The below Terraform output generates a sample kubectl configuration to connect
# to your cluster. This can be placed into a Kubernetes configuration file:
# e.g. ~/.kube/config
# Alternatively the AWS CLI eks update-kubeconfig command provides a simple
# method to create or update configuration files. Refer to here:
# https://docs.aws.amazon.com/cli/latest/reference/eks/update-kubeconfig.html

locals {
  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.demo.endpoint}
    certificate-authority-data: ${aws_eks_cluster.demo.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.cluster-name}"
KUBECONFIG
}

output "kubeconfig" {
  value = "${local.kubeconfig}"
}

#
# Kubernetes Worker Nodes
#

# The EKS service does not currently provide managed resources for running
# worker nodes. Here we will create a few operator managed resources so that
# Kubernetes can properly manage other AWS services, networking access, and
# finally a configuration that allows automatic scaling of worker nodes.

# The below is an example IAM role and policy to allow the worker nodes to
# manage or retrieve data from other AWS services. It is used by Kubernetes to
# allow worker nodes to join the cluster.

resource "aws_iam_role" "worker-role" {
  name = "${var.cluster-name}-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY

  tags = "${local.common_tags}"
}

resource "aws_iam_role_policy_attachment" "demo-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.worker-role.name}"
}

resource "aws_iam_role_policy_attachment" "demo-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.worker-role.name}"
}

resource "aws_iam_role_policy_attachment" "demo-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.worker-role.name}"
}

resource "aws_iam_instance_profile" "demo-node" {
  name = "${var.cluster-name}"
  role = "${aws_iam_role.worker-role.name}"
}


# Worker Node Security Group
# This security group controls networking access to the Kubernetes worker nodes.

resource "aws_security_group" "worker_sg" {
  name        = "${var.cluster-name}-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.k8s_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${merge(
    local.common_tags,
    map(
     "Name", "${var.cluster-name}-node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned"
    )
  )}"
}

resource "aws_security_group_rule" "demo-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.worker_sg.id}"
  source_security_group_id = "${aws_security_group.worker_sg.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "demo-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.worker_sg.id}"
  source_security_group_id = "${aws_security_group.master_sg.id}"
  to_port                  = 65535
  type                     = "ingress"
}

# Worker Node Access to EKS Master Cluster
# Now that we have a way to know where traffic from the worker nodes is coming
# from, we can allow the worker nodes networking access to the EKS master
# cluster.

resource "aws_security_group_rule" "demo-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.master_sg.id}"
  source_security_group_id = "${aws_security_group.worker_sg.id}"
  to_port                  = 443
  type                     = "ingress"
}

# Worker Node AutoScaling Group

# fetch the latest Amazon Machine Image (AMI) that Amazon provides with an EKS compatible Kubernetes baked in.
data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# create an AutoScaling Launch Configuration that uses all our prerequisite resources to define how to create EC2 instances using them.

# This data source is included for ease of sample architecture deployment
# and can be swapped out as necessary.
data "aws_region" "current" {}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We utilize a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  eks-worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.demo.endpoint}' --b64-cluster-ca '${aws_eks_cluster.demo.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "demo" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.demo-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "${var.worker_instance_type}"
  name_prefix                 = "${var.cluster-name}"
  security_groups             = ["${aws_security_group.worker_sg.id}"]
  user_data_base64            = "${base64encode(local.eks-worker-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

# create an AutoScaling Group that actually launches EC2 instances based on the AutoScaling Launch Configuration.

resource "aws_autoscaling_group" "demo" {
  desired_capacity     = 3
  launch_configuration = "${aws_launch_configuration.demo.id}"
  max_size             = 3
  min_size             = 1
  name                 = "${var.cluster-name}"
  vpc_zone_identifier  = ["${aws_subnet.k8s_subnet.*.id}"]

  tag {
    key                 = "Name"
    value               = "${var.cluster-name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "user"
    value               = "${lookup(local.common_tags, "user")}"
    propagate_at_launch = true
  }

  tag {
    key                 = "project"
    value               = "${lookup(local.common_tags, "project")}"
    propagate_at_launch = true
  }
}

# Required Kubernetes Configuration to Join Worker Nodes.
# To output an example IAM Role authentication ConfigMap from your
# Terraform configuration:
# Example of how to apply the required Kubernetes ConfigMap via kubectl
#
locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.codebuild-role.arn}
      username: build
      groups:
        - system:masters
    - rolearn: ${aws_iam_role.worker-role.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
}
