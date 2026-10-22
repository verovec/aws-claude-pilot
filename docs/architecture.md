# Architecture

aws-claude-pilot is an infrastructure reconciler. YAML service descriptors in `deploy/<env>/` are
the source of truth; Claude, through the `/sync` slash command, generates and updates the
Terraform under `terraform/` to match. There is no application code, only infrastructure
definitions and Claude commands. `agent/INFRA-AGENT.md` is the authoritative knowledge base
(Component Registry, scope boundary, module interface, YAML schema, unit conversion); this page
summarises it.

## Layout

```
.claude/
  commands/
    sync.md                     the /sync command
    secrets.md                  unified secrets management
    sync-alerts.md              alerting reconciler (planned, not in the repository yet)
  scripts/
    edit-secrets.sh             temp file editor for /secrets (code --wait, or vim)
agent/INFRA-AGENT.md            infra knowledge base (Component Registry, read by /sync)
deploy/
  dev/
    app.yaml                    template service descriptor
    alerts.yaml                 alert definitions (planned)
terraform/
  main.tf                       root module (platform + services)
  variables.tf                  root variables
  outputs.tf                    root outputs
  locals.tf                     project name, common tags (Project, Environment, ManagedBy)
  providers.tf                  AWS provider, plus an alias "route53" pinned to us-east-1
  backend.tf                    S3 backend, encrypted, configured at init time
  environments/
    dev.tfvars                  dev environment values
  modules/
    kms/                        encryption key
    vpc/                        networking + security groups
    ecs/                        Fargate cluster + log group
    iam/                        roles, ECR, GitHub OIDC
    rds/                        PostgreSQL + auto-credentials
    s3/                         encrypted buckets
    acm/                        SSL certificate (optional)
    alb/                        load balancer (optional)
    ecs-service/                Fargate service + ALB wiring
    app-secret/                 Secrets Manager placeholders
    monitoring/                 CloudWatch dashboard
    bastion/                    SSM-managed DB access
    slack-notifier/             Slack webhook Lambda (planned)
    log-alert-runner/           Logs Insights query Lambda (planned)
    alerting/                   CloudWatch alarms from YAML (planned)
```

## Module inventory

| Module | Purpose | Notes from the code |
|--------|---------|---------------------|
| `modules/kms` | Encryption key for RDS, S3, CloudWatch | key plus alias |
| `modules/vpc` | VPC, subnets, NAT gateways, security groups | `10.0.0.0/16`, two private and two public subnets, one NAT gateway per AZ, security groups for Postgres, the ALB and the ECS tasks |
| `modules/ecs` | ECS Fargate cluster + CloudWatch log group | Container Insights on, `FARGATE` and `FARGATE_SPOT` capacity providers, log group `/ecs/<project>-<env>` encrypted with the KMS key |
| `modules/iam` | ECS task roles, GitHub OIDC, ECR repos, CI/CD roles | task execution role with Secrets Manager access, task role with S3, SSM and secrets policies, one ECR repository and CI/CD role per GitHub repository |
| `modules/rds` | PostgreSQL RDS instances with auto-generated credentials | engine version 17 by default, multi-AZ, 21 days of backups, password generated and stored in Secrets Manager |
| `modules/s3` | Encrypted S3 buckets with public access block | versioning, KMS encryption, a policy denying insecure transport |
| `modules/acm` | ACM certificate with Route53 DNS validation (optional) | requires the `aws.route53` provider alias; `hashicorp/aws >= 6.27.0` |
| `modules/alb` | Application Load Balancer with HTTPS + HTTP redirect | created only when ACM is enabled |
| `modules/ecs-service` | ECS Fargate service with optional ALB integration | task definition, service, target group and listener rule; container health check with `curl` on the health path |
| `modules/app-secret` | Secrets Manager secret (data-source lookup or placeholder) | `<project>/<env>/<name>/<name>-credentials`, placeholder values, `ignore_changes` on `secret_string` |
| `modules/monitoring` | CloudWatch dashboard (ECS CPU/memory, RDS, logs) | one dashboard per application, fed by the `ecs_services` map |
| `modules/bastion` | SSM-managed bastion for RDS access | Amazon Linux 2023 `t3.micro` in a private subnet, no SSH, SSM session only |

In `main.tf`, `rds` and `s3` are instantiated with `for_each` over `postgres_databases` and
`s3_buckets`; `acm` and `alb` with `count`, only when `acm_domain_name` and `route53_zone_id` are
set. The template application `module "app"` is a single `ecs-service` wired to the ALB on `/*`
with listener priority 100.

## Component Registry

A component is a logical group of ECS services sharing the same YAML source directory,
Terraform prefix and locals block. `/sync` iterates over every component listed in
`agent/INFRA-AGENT.md`, processing all environments. The template ships one component:

| Key | Value |
|-----|-------|
| YAML source | `deploy/<env>/` |
| Terraform prefix | `app` |
| Service name prefix | `<project>-app` (uses `var.project`) |
| Locals env | `local.app_env` |
| Locals secrets | `local.app_secrets` |
| Monitoring module | `module "monitoring"` |
| ALB listener priority | `100` |
| Docker image tag | `app-latest` |
| Known Terraform-expression env vars | `APP_ENVIRONMENT = var.environment` |

For single-service components the module name equals the prefix, so variables are `app_image`,
`app_cpu`, and so on. For multi-service components a suffix is appended:
`<prefix>_<suffix>_image`.

## Scope boundary

`/sync` only operates within each component's ECS section of `main.tf`.

```
module "kms" "vpc" "ecs" "iam"            OUT OF SCOPE   shared platform
module "rds" "s3"                         OUT OF SCOPE   data stores
module "acm" "alb"                        OUT OF SCOPE   shared resources

# --- <component> section ---
module "<prefix>_secret"                  IN SCOPE   secret resource with placeholders, /sync verifies the block exists
module "<prefix>_<additional_secret>"     IN SCOPE   auto-managed by /sync from any YAML group other than rds and app
locals { <prefix>_* }                     IN SCOPE   secrets map, env map and version_ref locals reconciled; ARN lines manual
module "<prefix>_*"                       IN SCOPE   ECS service module blocks generated by /sync
module "monitoring"                       IN SCOPE   ecs_services map regenerated by /sync

module "bastion"                          OUT OF SCOPE   operational tooling
providers.tf backend.tf outputs.tf locals.tf   OUT OF SCOPE   root config
modules/                                  OUT OF SCOPE   module source code
```

Also in scope: `variables.tf` (service image, cpu, memory, desired_count variables and one
`<prefix>_<group>_secret_version` per secret group) and `environments/<env>.tfvars` (the matching
values, the version transcribed verbatim from each YAML).

## Secrets architecture

The `locals` block of each component has four parts:

1. ARN definitions, manually maintained, referencing module outputs:
   `<prefix>_rds_secret_arn = module.rds["<key>"].credentials_secret_arn` and
   `<prefix>_app_secret_arn = module.<prefix>_secret.secret_arn`.
2. Version-ref locals, one per secret group, reconciled by `/sync`:
   ```hcl
   <prefix>_<group>_version_ref = can(regex("^[0-9a-f]{8}-", var.<prefix>_<group>_secret_version)) ? ":${var.<prefix>_<group>_secret_version}" : "${var.<prefix>_<group>_secret_version}:"
   ```
   A UUID is written as the version-id fragment (`:<uuid>`), a staging label as the
   version-stage fragment (`<label>:`). The ECS `secrets[]` value format is
   `arn:json-key:version-stage:version-id`, so exactly one of the two trailing slots is filled.
3. The env map, rebuilt from the union of the YAML `env` sections, known Terraform-expression
   variables preserved.
4. The secrets map, rebuilt from the union of the YAML `secrets` sections, every entry
   `"${arn}:<json_key>:${version_ref}"`.

Secret groups map to Terraform as follows:

| Group name | Terraform source | Secret ARN local |
|------------|------------------|------------------|
| `rds` | `module.rds["<key>"].credentials_secret_arn` | `local.<prefix>_rds_secret_arn` |
| `app` | `module.<prefix>_secret.secret_arn` | `local.<prefix>_app_secret_arn` |
| `<custom>` | `module.<prefix>_<custom>.secret_arn` (an `app-secret` module added by `/sync`, hyphens replaced by underscores) | `local.<prefix>_<custom>_secret_arn` |

The committed `main.tf` is the template before the first `/sync`: its secrets map still uses the
`:key::` form without `version_ref` locals. The first run adds the version variables, the
`version_ref` locals and the tfvars assignments.

Every `version:` value in YAML is either a 36-character `VersionId` (the standard case after
`/secrets` has run once) or a staging label such as `AWSCURRENT`, which floats: the task
definition will not change when the secret rotates, so `/sync` warns on every non-UUID value.

## YAML schema

```yaml
service:
  name: <ecs-service-name>
  port: <number>
  dockerfile: <path>
  public_path: <path>         # if present, enables ALB routing (alb_path_pattern = "<path>*")
  entrypoint: [...]           # if present, maps to the Terraform command

env:
  KEY: value

secrets:
  - rds:                       # maps to the RDS credentials secret
      version: <uuid|AWSCURRENT>   # pinned VersionId; updated by /secrets on push
      keys:
        DB_HOST: host
        DB_PORT: port
        DB_PASSWORD: password
  - app:                       # maps to the app secret module
      version: <uuid|AWSCURRENT>
      keys:
        SECRET_KEY: SECRET_KEY
  - <additional-name>:         # maps to an additional secret module (auto-managed)
      version: <uuid|AWSCURRENT>
      keys:
        ENV_VAR: json_key

resources:
  cpu: <vcpu>
  memory_gb: <gb>

scaling:
  min_instances: <n>           # becomes the desired_count default
  max_instances: <n>

shutdown:
  strategy: rolling            # or drain-queue for workers
  stop_timeout_sec: <seconds>

health_check: <path>

monitoring:
  dashboard: <application-name>
  category: <api|worker|scheduler>
```

A service without a `monitoring:` section is omitted from the `ecs_services` map. ALB wiring is
only added when the YAML has `public_path`.

## Fargate sizing

CPU: multiply vCPU by 1024. Memory: multiply GB by 1024, then snap to the smallest valid Fargate
value for that CPU that is greater than or equal to the computed MiB (the maximum when it is
exceeded). An invalid pair makes `RegisterTaskDefinition` fail.

| CPU (units) | Valid memory values (MiB) |
|-------------|---------------------------|
| 256 | 512, 1024, 2048 |
| 512 | 1024, 2048, 3072, 4096 |
| 1024 | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2048 | 4096 to 16384 in 1024 increments |
| 4096 | 8192 to 30720 in 1024 increments |
| 8192 | 16384 to 61440 in 4096 increments |
| 16384 | 32768 to 122880 in 8192 increments |

| YAML | Raw MiB | CPU units | Snapped memory |
|------|---------|-----------|----------------|
| `cpu: 2, memory_gb: 2.3` | 2355 | 2048 | 4096 (minimum for 2048) |
| `cpu: 1, memory_gb: 2` | 2048 | 1024 | 2048 (exact) |
| `cpu: 0.5, memory_gb: 3` | 3072 | 512 | 3072 (exact) |
| `cpu: 1, memory_gb: 5.5` | 5632 | 1024 | 6144 (next valid value) |

## Root variables

| Variable | Default | Role |
|----------|---------|------|
| `project` | required | Prefix of every resource name |
| `aws_account_id` | required | Account id, used by KMS and IAM policies |
| `environment` | required | `development`, `staging` or `production`; part of every name and tag |
| `aws_region` | `us-east-1` | Region of the main provider |
| `postgres_databases` | `{}` | Map of RDS instances: `instance_class`, `allocated_storage`, `max_allocated_storage`, optional `db_name` |
| `github_org`, `github_repositories` | empty | GitHub OIDC trust, one ECR repository and CI/CD role per repository |
| `s3_buckets` | `[]` | Names of the encrypted buckets to create |
| `acm_domain_name`, `acm_subdomain_prefix`, `route53_zone_id` | empty | Set domain and zone to enable the certificate and the ALB |
| `app_image` | `public.ecr.aws/docker/library/busybox:latest` | Image of the template service |
| `app_cpu`, `app_memory`, `app_desired_count` | `512`, `1024`, `1` | Sizing of the template service, written by `/sync` |

Outputs expose the KMS key, VPC id, cluster name and ARN, log group, task roles, Postgres
endpoints and credential secret ARNs, buckets, certificate, ALB DNS name and listener, bastion
instance id, app secret ARN and ECR repository URLs.
