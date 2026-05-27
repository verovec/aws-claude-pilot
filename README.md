# AWS Claude Pilot

AI-assisted AWS infrastructure management. Define ECS services in YAML, let Claude reconcile them to Terraform.

## What you get

- **Terraform modules**: VPC, ECS Fargate cluster, RDS PostgreSQL, S3, KMS, ALB, ACM, IAM (GitHub OIDC CI/CD), CloudWatch monitoring, SSM bastion
- **YAML service descriptors**: one file per ECS service, human-readable, no Terraform noise
- **`/sync` command**: Claude reads your YAML files across all components and environments, generates/updates Terraform ECS modules, variables, tfvars, secrets maps, and env maps automatically
- **`/secrets` command**: unified interactive flow to list, create, edit, diff, push, and version-label secrets in AWS Secrets Manager -- with optional ECS service reload
- **`/sync-alerts` command**: YAML-driven CloudWatch alerting with Slack and email notifications (planned)
- **Infrastructure agent**: `agent/INFRA-AGENT.md` -- Claude's knowledge base for your infra, with a Component Registry for multi-service projects

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
  dockerfile: Dockerfile

env:
  APP_ENVIRONMENT: production

secrets:
  - rds:
      version: AWSCURRENT       # pinned to a UUID by /secrets after first push
      keys:
        DB_HOST: host
        DB_PASSWORD: password
  - app:
      version: AWSCURRENT
      keys:
        SECRET_KEY: SECRET_KEY

resources:
  cpu: 1
  memory_gb: 2

scaling:
  min_instances: 1
  max_instances: 10

health_check: /health

monitoring:
  dashboard: myapp
  category: api
```

### 4. Run /sync

In Claude Code or Cursor with Claude, run:

```
/sync
```

Claude reads all YAML files across all components and environments, generates Terraform ECS module blocks, reconciles secrets maps and env maps, updates `variables.tf` and `tfvars`, and shows you the diff. Then `terraform apply`.

### 5. Manage secrets

```
/secrets dev
```

Lists all secrets, lets you pick one to edit (or create a new one), opens a temp file in your editor with KEY=VALUE pairs, diffs changes, pushes to AWS, labels the outgoing version, and offers to reload affected ECS services.

## Commands

| Command | Description |
|---------|-------------|
| `/sync [--dry-run]` | Reconcile YAML service descriptors to Terraform for all components and environments. Manages ECS modules, secrets maps, env maps, variables, and tfvars. |
| `/secrets <env>` | Interactive secret management: list, create, edit (temp file with KEY=VALUE), diff, push, version label, ECS reload. Environments: `dev`, `staging`, `prod`. |
| `/sync-alerts <application>` | Reconcile `alerts.yaml` to Terraform CloudWatch alarms, SNS topics, and notification Lambdas (planned). |

### /sync details

`/sync` treats YAML as the single source of truth. For each component and environment:

1. Reads YAML service descriptors
2. Detects additional secret data-source modules (adds missing, removes stale)
3. Fully replaces the component's secrets map from YAML
4. Rebuilds the component's env map from YAML `env:` block (preserving known Terraform-expression vars)
5. Generates/updates ECS service module blocks (CPU, memory, desired_count, health check, ALB, command)
6. Updates `variables.tf` and `tfvars`
7. Updates the monitoring module's `ecs_services` map

### /secrets details

`/secrets <env>` replaces the need for separate list/get/put commands. The flow:

1. Authenticates via AWS SSO profile
2. Lists secrets under the project prefix (numbered menu)
3. User picks a secret to edit or `[0]` to create new
4. Downloads to temp file as KEY=VALUE lines, opens in editor
5. On save: diffs (shows added/removed/changed keys, values masked)
6. Pushes new version to AWS
7. Labels the outgoing version with a timestamp (`v-YYYYMMDD-HHMMSS`) for rollback visibility
8. Scans YAML deploy files, offers ECS reload for affected services

Separation of concerns:
- `/sync` manages secret **structure** (ARNs, data-source modules in Terraform)
- `/secrets` manages secret **values** (actual credentials in Secrets Manager)

Value updates do not require `terraform apply` -- ECS tasks fetch secrets at launch. Structural changes (adding/removing secret keys) require updating YAML descriptors and running `/sync`.

## Project structure

```
.claude/
  commands/
    sync.md                     -- the /sync command
    secrets.md                  -- unified secrets management
    sync-alerts.md              -- alerting reconciler (planned)
  scripts/
    edit-secrets.sh             -- temp file editor for /secrets
agent/INFRA-AGENT.md            -- infra knowledge base (Component Registry, read by /sync)
deploy/
  dev/
    app.yaml                    -- template service descriptor
    alerts.yaml                 -- alert definitions (planned)
terraform/
  main.tf                      -- root module (platform + services)
  variables.tf                 -- root variables
  outputs.tf                   -- root outputs
  locals.tf                    -- project name, common tags
  providers.tf                 -- AWS provider config
  backend.tf                   -- S3 backend
  environments/
    dev.tfvars                 -- dev environment values
  modules/
    kms/                       -- encryption key
    vpc/                       -- networking + security groups
    ecs/                       -- Fargate cluster + log group
    iam/                       -- roles, ECR, GitHub OIDC
    rds/                       -- PostgreSQL + auto-credentials
    s3/                        -- encrypted buckets
    acm/                       -- SSL certificate (optional)
    alb/                       -- load balancer (optional)
    ecs-service/               -- Fargate service + ALB wiring
    app-secret/                -- Secrets Manager placeholders
    monitoring/                -- CloudWatch dashboard
    bastion/                   -- SSM-managed DB access
    slack-notifier/            -- Slack webhook Lambda (planned)
    log-alert-runner/          -- Logs Insights query Lambda (planned)
    alerting/                  -- CloudWatch alarms from YAML (planned)
```

## Adding a new service

1. Create `deploy/dev/worker.yaml`
2. Run `/sync`
3. Review the generated Terraform diff
4. `terraform apply`

## Adding a new component

For projects with multiple backends (e.g. an API and a separate worker service with different codebases):

1. Create a new deploy directory (e.g. `deploy-worker/dev/worker.yaml`)
2. Add the component to the Component Registry in `agent/INFRA-AGENT.md`
3. Create the locals block in `terraform/main.tf` for the new component
4. Run `/sync`

## Optional: HTTPS

Uncomment the ACM/Route53 variables in your tfvars to enable the ALB with HTTPS. You need a Route53 hosted zone for DNS validation.

## Credits

Authors: **Clement VEROVE**

Contacts: verove.clement@gmail.com
