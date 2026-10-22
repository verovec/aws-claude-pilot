# Development

## Prerequisites

- Terraform. No `required_version` is pinned; the `acm` module requires `hashicorp/aws >= 6.27.0`.
- The AWS CLI with an SSO profile named `<project>-<env>` (`/secrets` logs in with it).
- An S3 bucket and a DynamoDB table for the remote state, created before `terraform init`.
- Claude Code, or Cursor with Claude, for `/sync` and `/secrets`. `/secrets` opens the editor
  through `code --wait` when VS Code is on the PATH, `vim` otherwise.

## Bootstrap, step by step

### 1. Configure the project

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

The committed file also sets `s3_buckets = ["assets"]` and the template service sizing
(`app_image`, `app_cpu`, `app_memory`, `app_desired_count`).

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

### 3. Define the services

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

`deploy/dev/app.yaml` is the committed template descriptor for the `app` component.

### 4. Run /sync

In Claude Code or Cursor with Claude, run `/sync`. Claude reads all YAML files across all
components and environments, generates Terraform ECS module blocks, reconciles secrets maps and
env maps, updates `variables.tf` and `tfvars`, and shows you the diff. Then `terraform apply`.

### 5. Manage secrets

Run `/secrets dev`. It lists all secrets, lets you pick one to edit (or create a new one), opens
a temp file in your editor with `KEY=VALUE` pairs, diffs changes, pushes to AWS, labels the
outgoing version, pins the new version in the YAML and offers to reload affected ECS services.
The procedures are detailed in [commands.md](commands.md).

## Recipes

```sh
cd terraform
terraform init -backend-config="bucket=..." -backend-config="key=<env>/terraform.tfstate" \
               -backend-config="region=..." -backend-config="dynamodb_table=..."   # once per environment
terraform fmt -recursive                                    # format every .tf file
terraform validate                                          # the only static check; there is no test suite
terraform plan  -var-file=environments/<env>.tfvars         # review before every apply
terraform apply -var-file=environments/<env>.tfvars         # after /sync, and after every /secrets pin
terraform output                                            # cluster, endpoints, secret ARNs, ALB DNS name, ECR URLs
```

## Adding a new service

1. Create `deploy/dev/worker.yaml`.
2. Run `/sync`.
3. Review the generated Terraform diff.
4. `terraform apply`.

## Adding a new component

For projects with multiple backends, for example an API and a separate worker service with
different codebases:

1. Create a new deploy directory, for example `deploy-worker/dev/worker.yaml`.
2. Add the component to the Component Registry in `agent/INFRA-AGENT.md`: YAML source, prefix,
   locals names, ALB priority, name mapping, known Terraform-expression variables.
3. Create the locals block and the module skeleton in `terraform/main.tf` for the new component.
4. Run `/sync`.

## Optional: HTTPS

Uncomment the ACM and Route53 variables in your tfvars (`acm_domain_name`,
`acm_subdomain_prefix`, `route53_zone_id`) to enable the ALB with HTTPS. You need a Route53
hosted zone for DNS validation; the certificate is validated through the `aws.route53` provider
alias in `us-east-1`.

## Conventions

- Always read `agent/INFRA-AGENT.md` before any infrastructure work.
- Stay inside each component's ECS section of `terraform/main.tf`. Platform modules (`kms`,
  `vpc`, `ecs`, `iam`, `rds`, `s3`, `acm`, `alb`, `bastion`) and the root files (`providers.tf`,
  `backend.tf`, `outputs.tf`, `locals.tf`) are out of scope for `/sync`-style edits.
- The `<prefix>_secrets` map, the `<prefix>_env` map and the `<prefix>_<group>_version_ref`
  locals are regenerated from the union of the component's YAML files; manual edits there are
  overwritten on the next `/sync`. The ARN definition lines in the same block are manual.
- A YAML service with no `monitoring:` section is omitted from the `ecs_services` map; ALB
  wiring is only added when the YAML has `public_path`.
- `AWSCURRENT` is allowed as a version but floats; prefer the UUID pinned by `/secrets`.
- Verification is `terraform fmt`, `terraform validate` and `terraform plan`.
