variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
