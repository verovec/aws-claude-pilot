variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "name" {
  type        = string
  description = "Secret name suffix."
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "placeholder_keys" {
  type        = list(string)
  description = "Keys to seed in the initial JSON. All set to PLACEHOLDER."
}

variable "recovery_window_in_days" {
  type    = number
  default = 7
}
