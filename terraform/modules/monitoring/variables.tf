variable "project" {
  type    = string
  default = "myapp"
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "application_name" {
  type        = string
  description = "Application identifier used in dashboard name"
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_services" {
  type = map(object({
    service_name = string
    category     = string
  }))
  description = "Map of ECS services to monitor. Key is a human label, value contains ECS service name and category (api, worker, scheduler)."
}

variable "log_group_name" {
  type = string
}

variable "rds_instances" {
  type        = map(string)
  default     = {}
  description = "Map of label -> RDS instance identifier to monitor"
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
