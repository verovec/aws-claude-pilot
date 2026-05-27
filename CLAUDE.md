# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

AWS Claude Pilot is an AI-assisted infrastructure reconciler. YAML service descriptors in `deploy/<env>/` are the source of truth; Claude (via the `/sync` slash command) generates and updates Terraform under `terraform/` to match. There is no application code here — only infra definitions and Claude commands.

## Authoritative knowledge base

**Always read `agent/INFRA-AGENT.md` before doing any infra work.** It is the source of truth for:
- The **Component Registry** (every component a `/sync` run iterates over: YAML source dir, Terraform prefix, locals names, ALB priority, known TF-expression env vars)
- The **Scope Boundary** for `/sync` (which `main.tf` blocks may be touched vs. never touched)
- **Additional secret module detection** (any YAML `secrets:` group other than `rds` / `app` auto-maps to a `module "<prefix>_<group>"` of source `./modules/app-secret`, plus a locals ARN entry, plus secrets-map entries)
- **Fargate CPU/memory snapping table** — YAML `resources.cpu`/`memory_gb` must be converted and snapped to a valid Fargate pair; pick the smallest valid memory ≥ requested for the given CPU
- ECS service module interface, variable naming pattern (`<prefix>_<suffix>_image|cpu|memory|desired_count`), and monitoring `ecs_services` map shape

`/sync` itself lives in `.claude/commands/sync.md`; `/secrets` in `.claude/commands/secrets.md` (uses `.claude/scripts/edit-secrets.sh`). Read those when changing command behavior.

## Architectural split that matters

- **`/sync` = secret *structure* + secret *version pins*** (Terraform module blocks, ARN locals, secrets/env maps, per-group `<prefix>_<group>_secret_version` variables and tfvars assignments, `<prefix>_<group>_version_ref` locals). Always followed by `terraform apply`.
- **`/secrets <env>` = secret *values* + pin updates** in AWS Secrets Manager. Push the value, then `/secrets` writes the new `VersionId` into every YAML descriptor referencing that secret group's `version:` field. The new value reaches ECS only after `/sync` + `terraform apply` updates the task definition — there is no `aws ecs update-service --force-new-deployment` in the happy path.

The `modules/app-secret` Terraform module creates secrets with placeholder values and uses `ignore_changes` on `secret_string` — Terraform owns the resource lifecycle; `/secrets` owns the contents and pins the active `VersionId` in YAML.

YAML carries the pin under each secret group: `secrets[].<group>.version: <uuid|AWSCURRENT>` alongside the `keys:` sub-map. `AWSCURRENT` is allowed but floats — `/sync` warns about non-UUID values.

## Common workflow commands

```bash
# Terraform (run from terraform/)
terraform init -backend-config="bucket=..." -backend-config="key=<env>/terraform.tfstate" \
               -backend-config="region=..." -backend-config="dynamodb_table=..."
terraform plan  -var-file=environments/<env>.tfvars
terraform apply -var-file=environments/<env>.tfvars
terraform fmt -recursive
terraform validate
```

There is no build/test suite — verification is `terraform fmt`, `terraform validate`, and `terraform plan`.

## When editing `terraform/main.tf`

- Stay inside each component's ECS section. Platform modules (`kms`, `vpc`, `ecs`, `iam`, `rds`, `s3`, `acm`, `alb`, `bastion`) and root files (`providers.tf`, `backend.tf`, `outputs.tf`, `locals.tf`) are out of scope for `/sync`-style edits.
- The `<prefix>_secrets` map, `<prefix>_env` map, and `<prefix>_<group>_version_ref` locals are fully regenerated from the union of all YAML files in the component — manual edits there will be overwritten on the next `/sync`. ARN definition lines in the same locals block *are* manually maintained.
- A YAML service with no `monitoring:` section is omitted from the monitoring `ecs_services` map.
- ALB wiring (`enable_alb`, `alb_*`) is only added when the YAML has `public_path`.

## Adding a new component (multi-codebase projects)

1. New deploy dir (e.g. `deploy-worker/dev/*.yaml`)
2. New entry in the Component Registry section of `agent/INFRA-AGENT.md` (YAML source, prefix, locals names, ALB priority, name mapping, known TF-expression vars)
3. New locals block + module skeleton in `terraform/main.tf`
4. Run `/sync`
