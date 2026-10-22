<p align="center">
  <img src="docs/assets/logo.svg" width="120" height="120" alt="aws-claude-pilot logo">
</p>

<h1 align="center">aws-claude-pilot</h1>

<p align="center">
  <strong>Describe an ECS service in a few lines of YAML; let Claude keep the Terraform in step.</strong><br>
  Terraform modules for ECS Fargate on AWS, one YAML descriptor per service, and two Claude Code
  commands: <code>/sync</code> reconciles the YAML to Terraform, <code>/secrets</code> edits and pins
  the values in Secrets Manager.
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> &middot;
  <a href="#how-it-works">How it works</a> &middot;
  <a href="#commands">Commands</a> &middot;
  <a href="#tech-stack">Tech stack</a> &middot;
  <a href="#documentation">Documentation</a>
</p>

<p align="center">
  <img alt="Terraform on AWS" src="https://img.shields.io/badge/Terraform-AWS-7B42BC?logo=terraform&amp;logoColor=white">
  <img alt="AWS provider 6.27 or later" src="https://img.shields.io/badge/AWS_provider-%3E%3D_6.27-FF9900?logo=amazonwebservices&amp;logoColor=white">
  <img alt="ECS Fargate" src="https://img.shields.io/badge/ECS-Fargate-FF9900?logo=amazonecs&amp;logoColor=white">
  <img alt="Postgres 17" src="https://img.shields.io/badge/Postgres-17-4169E1?logo=postgresql&amp;logoColor=white">
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-%2Fsync-D97757?logo=claude&amp;logoColor=white">
</p>

---

Running a handful of services on ECS Fargate means a lot of Terraform that all looks the same: a
task definition, a service, a target group, four variables, a dozen secret references with the
right ARN and version, a line in the dashboard. Editing that by hand for every new worker or every
rotated secret is slow and easy to get wrong.

**aws-claude-pilot** moves the description to YAML. One file per service in `deploy/<env>/` says
what the service is: image, port, public path, environment, which secret keys it reads, CPU and
memory, scaling, health check, monitoring category. The `/sync` Claude Code command reads every
descriptor of every component and environment and reconciles the Terraform under `terraform/`:
ECS service modules, secrets and env maps, variables, tfvars and the monitoring map, within a
strict scope boundary that never touches the platform modules. `/secrets <env>` manages the secret
values themselves in AWS Secrets Manager and writes the new `VersionId` back into the YAML, so a
rotation rolls out through `terraform apply` and rollback is a `git revert`.

The platform comes as Terraform modules: VPC, ECS Fargate cluster, RDS PostgreSQL, S3, KMS, ALB,
ACM, IAM with GitHub OIDC, CloudWatch monitoring and an SSM bastion. `agent/INFRA-AGENT.md` is
Claude's knowledge base for the infrastructure, with a Component Registry for multi-service
projects. There is no application code here, only infrastructure definitions and Claude commands.

## Quick start

**Prerequisites:** Terraform, the AWS CLI with an SSO profile named `<project>-<env>`, an S3
bucket and a DynamoDB table for the remote state, and Claude Code (or Cursor with Claude) for the
slash commands.

```bash
git clone git@github.com:verovec/aws-claude-pilot.git && cd aws-claude-pilot
$EDITOR terraform/environments/dev.tfvars     # project, aws_account_id, environment, aws_region, postgres_databases
cd terraform
terraform init \
  -backend-config="bucket=myapp-tf-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=myapp-tf-locks"
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
cd .. && $EDITOR deploy/dev/app.yaml          # one YAML per ECS service
# In Claude Code: /sync, review the diff, terraform apply; then /secrets dev to set the secret values
```

`/sync` shows the Terraform diff before writing; `terraform apply -var-file=environments/dev.tfvars`
then creates the services. `/secrets dev` lists the secrets under the project prefix, opens the one
you pick in your editor as `KEY=VALUE` lines, pushes the new version and pins it in the YAML. The
step-by-step walkthrough, with the tfvars and YAML examples, is in
[`docs/development.md`](docs/development.md).

## How it works

```
  YAML          one descriptor per ECS service in deploy/<env>/: service, env, secrets, resources, scaling, monitoring
     |
  /sync         Claude reads every YAML of every component and environment, reconciles main.tf, variables.tf, tfvars
     |
  Terraform     plan and apply: the platform modules plus one ecs-service module per YAML, within the scope boundary
     |
  /secrets      list, edit and push secret values to Secrets Manager; label the previous version; pin the VersionId in YAML
     |
  Roll-out      /sync transcribes the pin into tfvars, terraform apply renders a new task definition, ECS redeploys
     |
  Monitoring    one CloudWatch dashboard per application, its ecs_services map built from each YAML monitoring section
```

`/sync` owns the secret structure (module blocks, ARN locals, secrets and env maps, version
variables); `/secrets` owns the secret values and the version pins. Value updates never need
`--force-new-deployment`: the pinned `VersionId` changes the task definition and ECS performs a
rolling deployment. Adding or removing a secret key is structural and goes through the YAML and
`/sync` again.

## Commands

| Command | Description |
|---------|-------------|
| `/sync [--dry-run]` | Reconcile YAML service descriptors to Terraform for all components and environments. Manages ECS modules, secrets maps, env maps, variables, and tfvars. |
| `/secrets <env>` | Interactive secret management: list, create, edit (temp file with `KEY=VALUE`), diff, push, version label, ECS reload. Environments: `dev`, `staging`, `prod`. |
| `/sync-alerts <application>` | Reconcile `alerts.yaml` to Terraform CloudWatch alarms, SNS topics, and notification Lambdas (planned, not in the repository yet). |

The procedures step by step are in [`docs/commands.md`](docs/commands.md).

## Tech stack

| Layer | Tech | Location |
|-------|------|----------|
| Root module | Terraform, S3 backend, AWS provider (a second provider aliased `route53` in `us-east-1`) | `terraform/main.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `outputs.tf` |
| Platform modules | VPC, ECS cluster, IAM (ECS roles, ECR, GitHub OIDC, CI/CD roles), KMS, RDS PostgreSQL 17, S3, ACM, ALB, bastion | `terraform/modules/` |
| Service modules | `ecs-service` (task definition, service, target group, listener rule), `app-secret`, `monitoring` | `terraform/modules/ecs-service`, `app-secret`, `monitoring` |
| Environments | one tfvars file per environment | `terraform/environments/dev.tfvars` |
| Service descriptors | YAML, one file per ECS service and environment | `deploy/dev/app.yaml` |
| Claude commands | `/sync`, `/secrets` and the editor helper script | `.claude/commands/`, `.claude/scripts/edit-secrets.sh` |
| Knowledge base | Component Registry, scope boundary, YAML schema, Fargate table | `agent/INFRA-AGENT.md`, `CLAUDE.md` |

Details in [Architecture](docs/architecture.md).

## Documentation

| Topic | Where |
|-------|-------|
| Layout, module inventory, scope boundary, secrets architecture, YAML schema, Fargate sizing, variables | [`docs/architecture.md`](docs/architecture.md) |
| `/sync` and `/secrets` procedures, separation of concerns, value and structural changes | [`docs/commands.md`](docs/commands.md) |
| Step-by-step bootstrap, Terraform recipes, adding a service or a component, HTTPS, conventions | [`docs/development.md`](docs/development.md) |
| Infrastructure knowledge base read by `/sync` | [`agent/INFRA-AGENT.md`](agent/INFRA-AGENT.md) |
| Everything else | [`docs/`](docs/README.md) |

## Contributing

Issues and pull requests are welcome. There is no build or test suite: verification is
`terraform fmt -recursive`, `terraform validate` and `terraform plan`. Read
[`agent/INFRA-AGENT.md`](agent/INFRA-AGENT.md) before any infrastructure change, and keep edits to
`terraform/main.tf` inside each component's ECS section; the maps `/sync` regenerates are
overwritten on the next run.

Author: [Clement Verove](https://github.com/verovec)
