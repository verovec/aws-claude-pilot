# /secrets -- Manage secrets in AWS Secrets Manager

Usage: `/secrets <env>`

Arguments: `<env>` is `dev`, `staging`, or `prod`.

If `prod`, warn and wait for confirmation before proceeding.

## AWS Auth

Resolve the AWS profile from the project name and environment: `<project>-<env>`. Region is always `us-east-1` (or override from project config).

Run `aws sts get-caller-identity --profile <profile> --region <region>`. If it fails, run `aws sso login --profile <profile>`. Verify account matches.

Append `--profile <profile> --region <region>` to every AWS CLI call below.

## Env Mapping

`dev` -> `development`, `staging` -> `staging`, `prod` -> `production`. Use this as `<env_segment>` in paths below.

## List and Select

Run: `aws secretsmanager list-secrets --filters Key=name,Values=<project>/<env_segment>`

Parse the JSON response and build an **ordered list** of `(number, full_name)` pairs. Sort alphabetically by name. Assign numbers 1 through N. Store this mapping -- you MUST use it when the user picks a number.

Display a numbered menu as a plain text message (do NOT use AskQuestion -- the list can exceed its option limit). Strip the `<project>/<env_segment>/` prefix from each name to keep it short -- the prefix is already shown in the header. Right-align dates. Pad numbers to the same width. Add a blank line before the create option.

Format:

```
Secrets (<project>/<env_segment>/)

  1. rds/app-credentials                              2026-03-04
  2. app-app/app-app-credentials                      2026-03-26
  ...

  0. Create new secret
```

Then ask the user as a plain text question: `Pick a number (0-N):` and wait for their typed response.

**CRITICAL:** When the user picks a number, look up the **exact full secret name** from the ordered list built above. Do NOT re-derive or guess the name. Use the full name (including the `<project>/<env_segment>/` prefix) as `<full_path>` for all subsequent API calls.

**If creating new (0):** ask for the secret path relative to the environment prefix (e.g. `rds/app-credentials`, `redis-credentials`, `slack-webhooks`). The user provides the path after `<project>/<env_segment>/`. Derive the full path as `<project>/<env_segment>/<user_input>`. Confirm the full path with the user, then run `aws secretsmanager create-secret --name <full_path> --secret-string '{}'`. Use empty JSON `{}` as the baseline.

**If editing (1-N):** fetch the current value with `aws secretsmanager get-secret-value --secret-id <full_path>` (where `<full_path>` is the exact name from the numbered list). Parse `SecretString` as JSON. This is the baseline. Also save the `VersionId` from the response -- this is the **outgoing version ID** that will need a label after the push.

## Open Editor

Convert the baseline JSON to `KEY=VALUE` pairs. For new secrets, use no pairs.

Print:

```
<full_path> (<N> keys)
```

Run `.claude/scripts/edit-secrets.sh` via the Bash tool with a **600000 ms timeout** (10 minutes), passing each `KEY=VALUE` pair as a separate quoted argument. The script creates a temp file, opens it in the editor, and blocks until the user saves and closes it. It prints the final file contents to stdout and deletes the temp file on exit.

Use the stdout from that Bash call as the edited file content.

## Diff and Push

Parse each line of the script's stdout as `KEY=VALUE` (split on first `=`). Skip empty lines and lines starting with `#`.

Compare against the baseline JSON. Categorize keys as added (+), removed (-), changed (~), or unchanged (=). If nothing changed, print "No changes" and stop.

Display the diff (mask values, show only key names):

```
+ NEW_KEY
- OLD_KEY
~ CHANGED_KEY
= KEY_A, KEY_B (N unchanged)
```

Build the new JSON object from the file content and push immediately:

`aws secretsmanager put-secret-value --secret-id <full_path> --secret-string '<json>'`

Save the `VersionId` from the response -- this is the **new VersionId** that will be pinned into the YAML below.

If keys were added or removed, remind: "Structural change -- update YAML `keys:` and run `/sync`."

## Version Labeling

After a successful push, label the **outgoing version** (the one that was AWSCURRENT before the push, now AWSPREVIOUS) with a timestamped staging label so it stays visible in the AWS Console and is never garbage-collected.

Label format: `v-YYYYMMDD-HHMMSS` (UTC timestamp of when the push happened).

Run:

```
aws secretsmanager update-secret-version-stage \
  --secret-id <full_path> \
  --version-stage v-<timestamp> \
  --move-to-version-id <outgoing_version_id>
```

The `<outgoing_version_id>` is the VersionId saved during the "List and Select" step. Do not prompt the user -- label automatically. Print one line:

```
Labeled previous version: <outgoing_version_id> -> v-<timestamp>
```

Skip this step for new secrets (option 0) since there is no outgoing version.

## YAML Version Pin

The secret value has been pushed and the previous version is labeled. The next step is to pin the new `VersionId` into the YAML descriptors so that `/sync` + `terraform apply` rolls it out to ECS deterministically. There is no `aws ecs update-service --force-new-deployment` in this flow -- the redeploy is driven by the changed task definition.

**Derive the secret group name from `<full_path>`:**

The pilot's YAML uses short group keys (e.g. `rds`, `app`, `redis`), not full Secrets Manager paths. Map `<full_path>` to a group as follows:

| `<full_path>` shape | YAML group |
|-|-|
| `<project>/<env_segment>/rds/<key>-credentials` | `rds` |
| `<project>/<env_segment>/<service-prefix>/<service-prefix>-credentials` | `app` |
| `<project>/<env_segment>/<service-prefix>-<suffix>/<service-prefix>-<suffix>-credentials` | `<suffix>` (with hyphens preserved in YAML group key) |
| anything else | derive the group by stripping `<project>/<env_segment>/` and using the leading path segment |

If the shape is ambiguous, ask the user which YAML group name this secret corresponds to before proceeding.

**Scan and update YAML files:**

For each `deploy/<env_short>/*.yaml`:

1. Read the file. Locate the `secrets:` list entry whose key matches the derived group name. If absent, skip the file -- this service does not reference the pushed secret.

2. **Validate the existing `version:` field.** Compare it against the **outgoing `VersionId`** (saved during "List and Select"). If they differ, print:
   > YAML was stale (`<yaml_file>`: `<group>` had `<yaml_value>`, expected `<outgoing_version_id>`). Overwriting with new VersionId.

   "Stale" is normal when someone bypassed `/secrets` or when a previous `/secrets` run was aborted; it is not fatal.

3. **Write the new `VersionId`** from the `put-secret-value` response into the `version:` field for that group. The value must always be a UUID -- never `AWSCURRENT` or another staging label. Use the Write/Edit tools (not shell `sed`), so values are not shell-escaped.

4. **Reconcile `keys:`** -- if the push added or removed JSON keys at the Secrets Manager level, point this out but do **not** mutate the YAML `keys:` map yourself. Key changes are structural and belong in the developer's PR alongside the application code that uses them. Print:
   > Structural change in `<group>`: keys added=[...], removed=[...]. Update YAML `secrets[].<group>.keys:` to match, then run `/sync`.

5. **Refresh sibling-group versions in the same file.** For every other secret group in the same YAML file (i.e. groups not pushed in this run), look up the current `VersionId` in AWS:
   ```
   aws secretsmanager describe-secret --secret-id <sibling_full_path> --query VersionIdsToStages --output json
   ```
   Pick the VersionId whose stages array contains `AWSCURRENT`. If the YAML's `version:` value for that sibling group differs from the current AWSCURRENT, replace it and print:
   > Also pinned `<yaml_file>`: `<sibling_group>` (`<old_value>` -> `<current_version_id>`).

   This is what keeps the YAML self-consistent: a single `/secrets` run leaves no group in the same file pointing at a stale version.

6. Show a per-file diff of YAML changes.

If any YAML files were modified, print:

```
YAML pinned. Next: run /sync && terraform apply -var-file=environments/<env_short>.tfvars
```

If no YAML files reference this secret group, print:

```
No YAML files in deploy/<env_short>/ reference the `<group>` secret. Nothing to pin.
```

For new secrets (option 0), there is nothing to pin yet -- the secret has no consumers in YAML. Print:

```
New secret created. Add it to a YAML descriptor under `secrets:` with `version: <new_version_id>` and `keys: {...}`, then run /sync.
```

## Final Output

After push, version labeling, and YAML pinning, always print a final summary block:

```
Secret:   <full_path>
Version:  <version_id from put-secret-value response> (AWSCURRENT, pinned in YAML)
Previous: <outgoing_version_id> (v-<timestamp>)
YAML:     <N> file(s) updated -- run /sync && terraform apply
```

For new secrets (created via option 0), print:

```
Secret:  <full_path>
Version: <version_id> (initial)
YAML:    not yet referenced -- add a `secrets:` entry and run /sync
```

## Rules

- Never explain what you are about to do. Just do it.
- One-liners, not paragraphs. Mask all secret values.
- Do not print AWS CLI commands. Print only results.
- **Use file tools (read/write) for file operations, not shell commands.** Secret values may contain special characters that break shell escaping.
