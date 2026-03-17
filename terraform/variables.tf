variable "project" {
  type        = string
  description = "Project name used as prefix for all resources"
}

variable "aws_account_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# --- Data stores ---

variable "postgres_databases" {
  type = map(object({
    instance_class        = string
    allocated_storage     = number
    max_allocated_storage = number
    db_name               = optional(string)
  }))
  default = {}
}

# --- CI/CD ---

variable "github_org" {
  type    = string
  default = ""
}

variable "github_repositories" {
  type    = list(string)
  default = []
}

# --- S3 ---

variable "s3_buckets" {
  type    = list(string)
  default = []
}

# --- ACM / ALB (optional -- set both to enable HTTPS) ---

variable "acm_domain_name" {
  type    = string
  default = ""
}

variable "acm_subdomain_prefix" {
  type    = string
  default = ""
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

# --- Template application ---

variable "app_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
  description = "Container image URI for the application service."
}

variable "app_cpu" {
  type    = number
  default = 512
}

variable "app_memory" {
  type    = number
  default = 1024
}
