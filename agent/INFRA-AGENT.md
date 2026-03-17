# Infrastructure Agent: AWS Claude Pilot

This file is the Terraform and deployment knowledge base. It is read by the `/sync` command and by any agent performing infrastructure work.

## Terraform Layout

All paths relative to `terraform/`.

### Module Inventory

| Module | Purpose |
|--------|---------|
| `modules/kms` | Encryption key for RDS, S3, CloudWatch |
| `modules/vpc` | VPC, subnets, NAT gateways, security groups |
| `modules/ecs` | ECS Fargate cluster + CloudWatch log group |
| `modules/iam` | ECS task roles, GitHub OIDC, ECR repos, CI/CD roles |
| `modules/rds` | PostgreSQL RDS instances with auto-generated credentials |
| `modules/s3` | Encrypted S3 buckets with public access block |
| `modules/acm` | ACM certificate with Route53 DNS validation (optional) |
| `modules/alb` | Application Load Balancer with HTTPS + HTTP redirect |
| `modules/ecs-service` | ECS Fargate service with optional ALB integration |
| `modules/app-secret` | Secrets Manager secret with placeholder keys |
| `modules/monitoring` | CloudWatch dashboard (ECS CPU/memory, RDS, logs) |
| `modules/bastion` | SSM-managed bastion for RDS access |

### ECS Service Module Interface

Every ECS service uses `source = "./modules/ecs-service"`:

```hcl
module "<service_name>" {
  source = "./modules/ecs-service"

  project                 = var.project
  environment             = var.environment
  name                    = "<ecs-service-name>"
  ecs_cluster_arn         = module.ecs.cluster_arn
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  private_subnet_ids      = module.vpc.private_subnet_ids
  security_group_ids      = [module.vpc.ecs_tasks_security_group_id]
  log_group_name          = module.ecs.log_group_name
  aws_region              = var.aws_region

  container_image = var.<service>_image
  container_port  = <port>
  cpu             = var.<service>_cpu
  memory          = var.<service>_memory
  desired_count   = 1

  # Optional: override Docker CMD
  # command = ["bash", "-c", "..."]

  health_check_path         = "<path>"
  health_check_start_period = 120

  environment_variables = local.app_env
  secrets               = local.app_secrets

  # ALB integration (only for publicly-accessible services)
  # enable_alb            = length(module.alb) > 0
  # vpc_id                = module.vpc.vpc_id
  # alb_listener_arn      = length(module.alb) > 0 ? module.alb[0].https_listener_arn : null
  # alb_path_pattern      = "/api*"
  # alb_listener_priority = 100

  common_tags = local.common_tags
}
```

### Unit Conversion

| YAML | Terraform |
|------|-----------|
| `cpu: 2` | `cpu = 2048` (multiply by 1024) |
| `cpu: 1` | `cpu = 1024` |
| `cpu: 0.5` | `cpu = 512` |
| `cpu: 0.25` | `cpu = 256` |
| `memory_gb: 2` | `memory = 2048` (multiply by 1024) |
| `memory_gb: 4` | `memory = 4096` |

### Variables Pattern

For each ECS service, three variables exist in `variables.tf`:

```hcl
variable "<service>_image" {
  type    = string
  default = "public.ecr.aws/docker/library/busybox:latest"
}

variable "<service>_cpu" {
  type    = number
  default = 512
}

variable "<service>_memory" {
  type    = number
  default = 1024
}
```

## YAML Schema

Each file in `deploy/<env>/` describes one ECS service.

```yaml
service:
  name: <ecs-service-name>
  port: <number>
  dockerfile: <path>
  public_path: <path>         # if present, enables ALB routing

env:                           # direct environment variables
  KEY: value

secrets:                       # secret groups to inject
  - rds:                       # maps to RDS credentials secret
      DB_HOST: host
      DB_PORT: port
  - app:                       # maps to app secret
      SECRET_KEY: SECRET_KEY

resources:
  cpu: <vcpu>
  memory_gb: <gb>

scaling:
  min_instances: <n>
  max_instances: <n>
  cpu_target: <float>

health_check: <path>

monitoring:
  dashboard: <application-name>
  category: <api|worker|scheduler>
```

## Scope Boundary for /sync

**In scope** (generated/updated by `/sync`):
- `module "app_secret"` -- placeholder keys
- `locals` block -- `app_env` and `app_secrets`
- `module "<service>*"` -- ECS service module blocks
- `module "monitoring"` -- `ecs_services` map
- `variables.tf` -- service image/cpu/memory variables
- `environments/<env>.tfvars` -- service variable values

**Out of scope** (never touch):
- `module "kms"`, `module "vpc"`, `module "ecs"`, `module "iam"` -- shared platform
- `module "rds"`, `module "s3"` -- data stores
- `module "acm"`, `module "alb"` -- shared resources
- `module "bastion"` -- operational tooling
- `providers.tf`, `backend.tf`, `outputs.tf` -- root config
- `modules/` -- module source code
