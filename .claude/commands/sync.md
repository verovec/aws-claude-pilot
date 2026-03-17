# /sync -- YAML-to-Terraform Reconciler

Usage: `/sync <env> [--dry-run]`

Reads YAML service descriptors from `deploy/<env>/` and reconciles ECS service modules in `terraform/main.tf`.

## Setup

Read `agent/INFRA-AGENT.md` first. It contains the module interface, YAML schema, unit conversions, scope boundaries, and examples.

## Procedure

### 1. Read inputs

- Read all `*.yaml` files from `deploy/<env>/`
- Read `terraform/main.tf` (identify the application section per the scope boundary in the infra agent)
- Read `terraform/variables.tf`
- Read `terraform/environments/<env>.tfvars`

### 2. For each YAML file, generate Terraform

Follow the rules in `agent/INFRA-AGENT.md`:
- Map YAML `service.name` to Terraform module name and variable suffix
- Convert CPU/memory using the Unit Conversion table
- Use the ECS Service Module Interface as the template
- If YAML has `public_path`, add ALB integration parameters
- Set health check from YAML `health_check` field
- Map YAML `env` to `environment_variables`
- Map YAML `secrets` groups to the appropriate `local.*_secrets` references
- Generate corresponding `variables.tf` entries (image, cpu, memory)

### 3. Update tfvars

For each new or modified service, ensure `environments/<env>.tfvars` has correct values:
- `<service>_image` -- container image URI
- `<service>_cpu` -- Fargate CPU units (YAML cpu * 1024)
- `<service>_memory` -- Fargate memory MiB (YAML memory_gb * 1024, rounded)

### 4. Update monitoring

After generating all ECS service modules, update `module "monitoring"` in `main.tf`. Build the `ecs_services` map from each YAML `monitoring` section:

```hcl
"<label>" = {
  service_name = module.<suffix>.service_name
  category     = "<monitoring.category from YAML>"
}
```

### 5. Diff

Compare generated modules against current `main.tf`:
- **New YAML** (no module) -- add module block
- **Changed YAML** (module exists, params differ) -- update module block
- **Removed YAML** (module exists, no YAML) -- comment out with a note

Respect the scope boundary: only touch service modules, variables, tfvars, and the `ecs_services` map in monitoring.

### 6. Apply or dry-run

If `--dry-run`, show the diff and stop. Otherwise, write changes.

### 7. Summary

Output:
- Modules added / modified / removed
- Variables added / modified
- Values set in tfvars
