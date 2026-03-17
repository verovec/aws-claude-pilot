variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "name" {
  type        = string
  description = "Database name used for RDS identifier, secret path, and as default for db_name/username."
}

variable "db_name" {
  type        = string
  default     = null
  description = "PostgreSQL database name. Must be alphanumeric. Defaults to var.name if null."
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "postgres_security_group_id" {
  type = string
}

variable "postgres_instance_class" {
  type = string
}

variable "postgres_allocated_storage" {
  type = number
}

variable "postgres_max_allocated_storage" {
  type    = number
  default = 100
}

variable "postgres_backup_retention_period" {
  type    = number
  default = 21
}

variable "postgres_backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "postgres_maintenance_window" {
  type    = string
  default = "Mon:04:00-Mon:05:00"
}

variable "postgres_multi_az" {
  type    = bool
  default = true
}

variable "postgres_engine_version" {
  type    = string
  default = "17"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for RDS encryption."
}
