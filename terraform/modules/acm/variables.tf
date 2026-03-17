variable "environment" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "domain_name" {
  type        = string
  description = "Base domain name (e.g., example.com)"
}

variable "subdomain_prefix" {
  type        = string
  description = "Subdomain prefix for this environment (e.g., dev, staging, app)"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID"
}

variable "create_wildcard" {
  type        = bool
  default     = true
  description = "Create wildcard certificate for the subdomain"
}
