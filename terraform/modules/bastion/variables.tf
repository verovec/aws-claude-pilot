variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type        = string
  description = "Private subnet for the bastion instance"
}

variable "postgres_security_group_id" {
  type        = string
  description = "Postgres security group -- an ingress rule will be added for the bastion"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
