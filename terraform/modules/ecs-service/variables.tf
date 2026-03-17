variable "project" {
  type    = string
  default = "myapp"
}

variable "environment" {
  type = string
}

variable "name" {
  type        = string
  description = "Service name. Used in task family, service name, log stream prefix."
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "ecs_cluster_arn" {
  type = string
}

variable "task_execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "container_image" {
  type        = string
  description = "Full container image URI with tag"
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "command" {
  type        = list(string)
  default     = null
  description = "Override CMD. null = use Dockerfile CMD."
}

variable "cpu" {
  type        = number
  default     = 256
  description = "Task-level CPU units (256 = 0.25 vCPU, 512 = 0.5, 1024 = 1, 2048 = 2, 4096 = 4)"
}

variable "memory" {
  type        = number
  default     = 512
  description = "Task-level memory in MiB"
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables set directly on the container definition"
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "Secrets from AWS Secrets Manager injected as env vars. Key = env var name, value = secret ARN or ARN:json_key::."
}

variable "log_group_name" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "health_check_path" {
  type        = string
  default     = null
  description = "HTTP health check path. When null, no health check is configured."
}

variable "health_check_interval" {
  type    = number
  default = 30
}

variable "health_check_start_period" {
  type        = number
  default     = 60
  description = "Grace period in seconds before health checks start counting failures"
}

variable "enable_alb" {
  type    = bool
  default = false
}

variable "alb_listener_arn" {
  type    = string
  default = null
}

variable "alb_host" {
  type    = string
  default = null
}

variable "alb_listener_priority" {
  type    = number
  default = null
}

variable "alb_path_pattern" {
  type    = string
  default = null
}

variable "vpc_id" {
  type    = string
  default = null
}

variable "capacity_provider" {
  type    = string
  default = "FARGATE"
}
