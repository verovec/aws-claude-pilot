project        = "myapp"
aws_account_id = "123456789012"
environment    = "development"
aws_region     = "us-east-1"

postgres_databases = {
  "app" = {
    instance_class        = "db.t3.micro"
    allocated_storage     = 20
    max_allocated_storage = 100
  }
}

s3_buckets = ["assets"]

# Uncomment to enable HTTPS via ACM + ALB
# acm_domain_name      = "example.com"
# acm_subdomain_prefix = "dev"
# route53_zone_id      = "Z0123456789ABCDEFGHIJ"

# github_org          = "my-org"
# github_repositories = ["my-repo"]

app_image         = "public.ecr.aws/docker/library/busybox:latest"
app_cpu           = 512
app_memory        = 1024
app_desired_count = 1
