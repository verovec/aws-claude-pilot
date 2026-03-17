variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "bucket_name" {
  type = string
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for S3 encryption. Uses AES256 if not specified."
}
