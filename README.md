# AWS Claude Pilot

AI-assisted AWS infrastructure management. Define ECS services in YAML, let Claude reconcile them to Terraform.

## What you get

- **Terraform modules**: VPC, ECS Fargate cluster, RDS PostgreSQL, S3, KMS, ALB, ACM, IAM (GitHub OIDC CI/CD), CloudWatch monitoring, SSM bastion
- **YAML service descriptors**: one file per ECS service, human-readable, no Terraform noise
- **`/sync` command**: Claude reads your YAML files and generates/updates Terraform ECS modules, variables, and tfvars automatically
- **Infrastructure agent**: `agent/INFRA-AGENT.md` -- Claude's knowledge base for your infra, referenced by `/sync`

## Quick start

### 1. Configure your project

Edit `terraform/environments/dev.tfvars`:

```hcl
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
```

### 2. Bootstrap Terraform

```bash
cd terraform

# Configure S3 backend (create bucket + DynamoDB table first)
terraform init \
  -backend-config="bucket=myapp-tf-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=myapp-tf-locks"

terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### 3. Define your services

Create a YAML file per service in `deploy/<env>/`:

```yaml
service:
  name: myapp-api
  port: 8080
  public_path: /api

env:
  APP_ENV: production

secrets:
  - rds:
      DB_HOST: host
      DB_PASSWORD: password
  - app:
      SECRET_KEY: SECRET_KEY

resources:
  cpu: 1
  memory_gb: 2

health_check: /health

monitoring:
  dashboard: myapp
  category: api
```

### 4. Run /sync

In Claude Code or Cursor with Claude, run:

```
/sync dev
```

Claude reads all YAML files, generates Terraform ECS module blocks, updates `variables.tf` and `tfvars`, and shows you the diff. Then `terraform apply`.

## Project structure

```
.claude/commands/sync.md      -- the /sync command
agent/INFRA-AGENT.md          -- infra knowledge base (read by /sync)
deploy/
  dev/
    app.yaml                  -- template service descriptor
terraform/
  main.tf                    -- root module (platform + services)
  variables.tf               -- root variables
  outputs.tf                 -- root outputs
  locals.tf                  -- project name, common tags
  providers.tf               -- AWS provider config
  backend.tf                 -- S3 backend
  environments/
    dev.tfvars               -- dev environment values
  modules/
    kms/                     -- encryption key
    vpc/                     -- networking + security groups
    ecs/                     -- Fargate cluster + log group
    iam/                     -- roles, ECR, GitHub OIDC
    rds/                     -- PostgreSQL + auto-credentials
    s3/                      -- encrypted buckets
    acm/                     -- SSL certificate (optional)
    alb/                     -- load balancer (optional)
    ecs-service/             -- Fargate service + ALB wiring
    app-secret/              -- Secrets Manager placeholders
    monitoring/              -- CloudWatch dashboard
    bastion/                 -- SSM-managed DB access
```

## Adding a new service

1. Create `deploy/dev/worker.yaml`
2. Run `/sync dev`
3. Review the generated Terraform diff
4. `terraform apply`

## Optional: HTTPS

Uncomment the ACM/Route53 variables in your tfvars to enable the ALB with HTTPS. You need a Route53 hosted zone for DNS validation.

## Credits

Authors: **Clement VEROVE**

Contacts: verove.clement@gmail.com
