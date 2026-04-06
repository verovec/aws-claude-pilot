# /sync -- YAML-to-Terraform Reconciler

Usage: `/sync [--dry-run]`

Reads YAML service descriptors for **all components** across **all environments** and reconciles ECS service modules, secrets maps, env maps, and variables in Terraform. Components are processed in registry order. For each component, environments are processed in order.

## Setup

Read `agent/INFRA-AGENT.md` first. It contains the Component Registry, module interface, YAML schema, unit conversions, scope boundaries, additional secret module detection, and examples.

## Procedure

Run the full procedure below **for each component** in the Component Registry, and within each component **for each environment** that has a deploy directory.

### 1. Read inputs

For the current component and environment:

- Read all `*.yaml` files from `<component.yaml_source>/<environment>/`
- Read `terraform/main.tf` (identify the component's section per its scope boundary)
- Read `terraform/variables.tf`
- Read `terraform/environments/<env>.tfvars`

### 2. Variable reconciliation

For the current component, collect all secret groups and env vars from **every** YAML file. Steps 2a-2d reconcile the four parts of the component's locals block: secret modules, secrets map, and env map. YAML files are the source of truth -- the union of all YAML files for the component determines what must exist in Terraform.

**2a. Additional secret module detection**

Collect every secret group name from all YAML files that is not `rds` and not `app`. This is the authoritative set of additional secrets for the component. Follow the **Additional Secret Module Detection** procedure in `agent/INFRA-AGENT.md` to:

- **Add** any missing Terraform module, locals ARN, and secrets map entries for new additional secrets. Warn for each new module:
  > New secret module added: `<module_name>`. After `terraform apply`, use `/secrets` to set values before deploying.
- **Remove** any additional-secret module blocks, locals ARN definitions, and secrets map entries in Terraform that are no longer referenced by any YAML file. Do not just warn -- delete the stale blocks.

**2b. App secret module block**

The app-secret module creates a Secrets Manager secret with placeholder values. For each component, verify that a corresponding `module` block for the app secret exists in `main.tf`. If a new component appears but no matching module block exists, add the module block, then warn:

> New secret module added. After `terraform apply`, use `/secrets` to set values before deploying.

**2c. Locals secrets map**

Build the expected `local.<prefix>_secrets` map by reading **every** YAML file for the component and collecting **every** `ENV_VAR: json_key` mapping from **every** secret group (rds, app, and additional). This is the full union -- a key declared in any single YAML file must appear in the shared secrets map.

For each secret group in YAML, determine the corresponding locals ARN variable:
- `rds` group -> `local.<prefix>_rds_secret_arn`
- `app` group -> `local.<prefix>_app_secret_arn`
- Additional secret -> `local.<prefix>_<group_name>_secret_arn`

The ECS secret reference format is `arn:json_key:version_stage:version_id`. By default, use empty version stage and version ID (fetches AWSCURRENT):

```
<ENV_VAR> = "${local.<prefix>_<arn_local>}:<json_key>::"
```

**Replace** the entire `local.<prefix>_secrets` map in `main.tf` with the full union built from YAML. This is a complete overwrite -- the YAML secrets sections are the single source of truth. Any entry that was in Terraform but is no longer declared in any YAML file is removed. Any entry in YAML that was missing from Terraform is added.

**2d. Locals env map**

Build the expected `local.<prefix>_env` map by reading **every** YAML file for the component and collecting **every** key from the `env` section. Take the union of all keys across all YAML files.

**Rebuild** the `local.<prefix>_env` map in `main.tf` from the YAML env union plus the component's Known Terraform-Expression Env Vars:

1. Start with the full union of all YAML `env` keys across all YAML files for the component.
2. For each key in the union: if the key already exists in the current TF env map, **preserve the existing TF value** (it may use a Terraform expression like `var.environment`). If the key is new (not in TF), add it with the YAML value as a quoted string. If the key appears in multiple YAML files with different values within the same environment, warn and use the most common value.
3. For each key listed in the component's Known Terraform-Expression Env Vars (see `agent/INFRA-AGENT.md`), **always preserve** it in the map with its current TF value, even if it does not appear in YAML.
4. **Remove** any key from the TF env map that is not in the YAML env union AND not in the Known Terraform-Expression Env Vars list. Do not just warn -- delete the stale entry.

### 3. For each YAML file, generate Terraform

Follow the rules in `agent/INFRA-AGENT.md`:
- Use the component's Terraform prefix for module names and variable suffixes (see the component's Name Mapping table)
- Convert CPU/memory using the Unit Conversion table
- Use the ECS Service Module Interface as the template
- If YAML has `entrypoint`, set `command` on the module
- If YAML has `public_path`, add ALB integration parameters. Map YAML `public_path` to Terraform `alb_path_pattern` by appending `*` wildcard (e.g. `public_path: /api` becomes `alb_path_pattern = "/api*"`). Use the component's `alb_listener_priority` from the registry. Do NOT set `alb_host` -- path-based routing uses path_pattern only.
- Set health check from YAML `health_check` field
- Use the component's `locals_env` and `locals_secrets` for `environment_variables` and `secrets`
- Read `scaling.min_instances` from the YAML and set `desired_count = var.<prefix>_<suffix>_desired_count` on each ECS service module block
- Generate corresponding `variables.tf` entries (image, cpu, memory, desired_count) for any new services

### 4. Update tfvars

For each new or modified service, ensure `environments/<env>.tfvars` has correct values:
- `<prefix>_<suffix>_image` -- container image URI
- `<prefix>_<suffix>_cpu` -- Fargate CPU units (YAML cpu * 1024)
- `<prefix>_<suffix>_memory` -- Fargate memory MiB (YAML memory_gb * 1024, snapped to valid Fargate value)
- `<prefix>_<suffix>_desired_count` -- from YAML `scaling.min_instances`

### 5. Update monitoring

After generating all ECS service modules for the component, update the component's monitoring module in `main.tf`. Build the `ecs_services` map from each YAML `monitoring` section:

```hcl
"<label>" = {
  service_name = module.<prefix>_<suffix>.service_name
  category     = "<monitoring.category from YAML>"
}
```

If a YAML file has no `monitoring` section, skip it. On subsequent syncs, only update the `ecs_services` map. Do not touch `rds_instances` or other static inputs.

### 6. Diff

Compare generated modules against current `main.tf`:
- **New YAML** (no module) -- add module block
- **Changed YAML** (module exists, params differ) -- update module block
- **Removed YAML** (module exists, no YAML) -- comment out with a note

Respect the scope boundary: only touch the component's service modules, variables, tfvars, the `ecs_services` map in its monitoring module, the `<prefix>_secrets` map (step 2c -- full replace from YAML), the `<prefix>_env` map (step 2d -- full rebuild), and additional secret modules managed by step 2a.

### 7. Apply or dry-run

If `--dry-run`, show the diff and stop. Otherwise, write changes.

### 8. Repeat

After processing all environments for the current component, move to the next component in the registry.

### 9. Summary

After processing **all components** and **all environments**, output a structured summary.

Per component and environment, a markdown table with one row per YAML file:

| YAML file | Module | cpu (YAML->TF) | memory (YAML->TF) | desired_count (YAML->TF) | tfvars | Status |
|-----------|--------|-----------------|--------------------|--------------------------|--------|--------|

Then one-line summaries:

> Monitoring module: all N entries present with correct categories.

> Secrets map: N entries (M added, K removed).

> Env map: N entries (M added, K removed, J known TF-expression vars preserved).

Then a compact change count:

**Summary:**
- Modules added: N
- Modules modified: N
- Modules removed: N
- Variables changed: N
- tfvars changed: N
- Secret module blocks added: N / removed: N
- Secrets map entries added: N / removed: N / updated: N
- Env map entries added: N / removed: N

If nothing changed: `Everything is already in sync. No changes to write.`
