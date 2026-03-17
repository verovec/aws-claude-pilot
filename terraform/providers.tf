provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "route53"
  region = "us-east-1"
}
