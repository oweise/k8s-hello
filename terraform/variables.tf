variable "access_key" {}
variable "secret_key" {}
variable "region" {
  default = "eu-west-1"
}
variable "cluster-name" {
  default = "k8s-hello"
  type    = "string"
}
variable "user_name" {}
variable "project_name" {}