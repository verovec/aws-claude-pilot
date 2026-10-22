# Commands

Both commands live in `.claude/commands/` and run in Claude Code (or Cursor with Claude).
`/sync` manages secret structure, `/secrets` manages secret values; neither replaces
`terraform apply`.

| Command | Description |
|---------|-------------|
| `/sync [--dry-run]` | Reconcile YAML service descriptors to Terraform for all components and environments. Manages ECS modules, secrets maps, env maps, variables, and tfvars. |
| `/secrets <env>` | Interactive secret management: list, create, edit (temp file with `KEY=VALUE`), diff, push, version label, ECS reload. Environments: `dev`, `staging`, `prod`. |
| `/sync-alerts <application>` | Reconcile `alerts.yaml` to Terraform CloudWatch alarms, SNS topics, and notification Lambdas (planned). |

## /sync

`/sync` treats YAML as the single source of truth. It reads `agent/INFRA-AGENT.md` first, then
runs the procedure for each component in registry order and, within each component, for each
environment that has a deploy directory.

1. Reads the YAML service descriptors of `<component.yaml_source>/<environment>/`, plus
   `terraform/main.tf`, `variables.tf` and `environments/<env>.tfvars`.
2. Reconciles the variables of the component from the union of every YAML file:
   - detects additional secret data-source modules (any group other than `rds` and `app`), adds
     the missing `app-secret` module blocks, locals ARN and map entries, and deletes the stale ones;
   - verifies the component's app secret module block exists;
   - ensures one `<prefix>_<group>_secret_version` variable (default `AWSCURRENT`), one
     `version_ref` local and one tfvars assignment per secret group, the YAML value transcribed
     verbatim, with a warning for staging labels and for files that disagree (majority wins);
   - fully replaces the component's secrets map from the YAML `secrets` sections;
   - rebuilds the component's env map from the YAML `env` blocks, preserving existing Terraform
     values and the known Terraform-expression variables, deleting the stale keys.
3. Generates or updates one ECS service module block per YAML file: CPU and memory converted and
   snapped, `desired_count` from `scaling.min_instances`, `command` from `entrypoint`, health
   check from `health_check`, ALB parameters when `public_path` is set.
4. Updates `variables.tf` and `environments/<env>.tfvars` (image, cpu, memory, desired_count).
5. Updates the `ecs_services` map of the component's monitoring module from each YAML
   `monitoring` section; other monitoring inputs are left alone.
6. Diffs against `main.tf`: new YAML adds a block, changed YAML updates it, removed YAML comments
   the block out with a note.
7. With `--dry-run`, shows the diff and stops; otherwise writes the changes.
8. Ends with a per-environment table (YAML file, module, cpu, memory, desired_count, tfvars,
   status) and the change counts, or `Everything is already in sync. No changes to write.`

Then `terraform apply`.

## /secrets

`/secrets <env>` replaces separate list, get and put commands. With `prod` it warns and waits
for confirmation.

1. Authenticates with the AWS SSO profile `<project>-<env>` in `us-east-1` (or the project's
   region): `aws sts get-caller-identity`, then `aws sso login` if needed. `dev`, `staging` and
   `prod` map to the path segments `development`, `staging` and `production`.
2. Lists the secrets under `<project>/<env_segment>/` as a numbered, alphabetical menu, with
   `0. Create new secret`.
3. The user picks a number. Creating asks for the path relative to the prefix and runs
   `create-secret` with `{}`; editing fetches the current value and remembers its `VersionId`,
   the outgoing version.
4. Converts the JSON to `KEY=VALUE` lines and runs `.claude/scripts/edit-secrets.sh`, which
   writes a temp file, opens it in `code --wait` (or `vim`), blocks until it is closed, prints the
   content and deletes the file.
5. Diffs against the baseline, values masked: added, removed, changed and unchanged keys. Nothing
   changed means stop.
6. Pushes the new version with `put-secret-value` and keeps the new `VersionId`. Added or removed
   keys trigger the reminder to update the YAML `keys:` and run `/sync`.
7. Labels the outgoing version `v-YYYYMMDD-HHMMSS` (UTC) with `update-secret-version-stage`, so
   it stays visible in the console and is never garbage-collected. Skipped for new secrets.
8. Pins the new `VersionId` into every `deploy/<env>/*.yaml` that references the secret group:
   the group is derived from the path (`rds/<key>-credentials` is `rds`,
   `<service-prefix>/<service-prefix>-credentials` is `app`, `<service-prefix>-<suffix>/...` is
   `<suffix>`, otherwise the leading segment, or the user is asked). A stale `version:` is
   reported and overwritten; sibling groups in the same file are refreshed to their current
   `AWSCURRENT` id so no group is left stale.
9. Prints the summary: secret, new version, previous version and label, number of YAML files
   updated, then `run /sync && terraform apply -var-file=environments/<env>.tfvars`.

Rules of the command: no explanations, one-liners, every value masked, AWS CLI commands never
printed, file tools rather than shell commands for YAML edits because values may contain
characters that break shell escaping.

## Separation of concerns

| Concern | Owner | Tool |
|---------|-------|------|
| Secret structure (module blocks, ARN references in Terraform) | Terraform via `/sync` | `terraform apply` |
| Secret lifecycle (creation with placeholders) | Terraform via the `app-secret` module | `terraform apply` |
| Secret values (editing actual credentials) | Developer via `/secrets` | `aws secretsmanager put-secret-value` |

## Updating a value

ECS tasks fetch secret values at launch, using the `VersionId` baked into the task definition.
The happy path for a value-only update:

1. `/secrets <env>`: edit, push, get a new `VersionId`, written into every YAML referencing the
   secret group.
2. `/sync`: transcribes the YAML version into `environments/<env>.tfvars`.
3. `terraform apply`: the changed tfvars render a new task definition through `version_ref`; ECS
   performs a rolling deployment.

Rollback is `git revert` plus `terraform apply`. There is no
`aws ecs update-service --force-new-deployment` in the happy path.

## Changing the structure

Adding or removing a secret key, not just changing its value:

1. Update the YAML descriptors in `deploy/<env>/` under `secrets[].<group>.keys`.
2. `/sync`: reconciles secret modules, secrets map, env map, version variables and `version_ref`
   locals.
3. `terraform apply`: creates any new secret module with placeholders.
4. `/secrets`: set the actual values; the new `VersionId` is pinned back into the YAML.
5. `/sync` and `terraform apply` again to roll the new version out to ECS.
