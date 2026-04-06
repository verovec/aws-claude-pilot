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

If keys were added or removed, remind: "Structural change -- update YAML descriptors and run `/sync`."

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

## ECS Reload

Scan YAML deploy files to find services referencing this secret. For each YAML file in the component's deploy directories, read the file and check if the secret group name appears in its `secrets` section. Collect the `service.name` value from matching files.

Component YAML directories (use the short env name: dev/staging/prod):
- `deploy/<env_short>/*.yaml`

If matches found, display a clear menu:

```
N services use this secret. Reload to pick up changes?

  1. myapp-api
  2. myapp-worker
  ...

  a. Reload ALL
  s. Skip

Pick services (e.g. 1,3) or a/s:
```

For selected services, run `aws ecs update-service --cluster <project>-<env_segment> --service <name> --force-new-deployment`. Do NOT wait for stable.

## Final Output

After everything is done (push completed, version labeled, ECS reload handled or skipped), always print a final summary block:

```
Secret:   <full_path>
Version:  <version_id from put-secret-value response> (AWSCURRENT)
Previous: <outgoing_version_id> (v-<timestamp>)
```

For new secrets (created via option 0), print:

```
Secret:  <full_path>
Version: <version_id> (initial)
```

## Rules

- Never explain what you are about to do. Just do it.
- One-liners, not paragraphs. Mask all secret values.
- Do not print AWS CLI commands. Print only results.
- **Use file tools (read/write) for file operations, not shell commands.** Secret values may contain special characters that break shell escaping.
