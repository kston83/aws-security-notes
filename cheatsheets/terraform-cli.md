# Terraform CLI cheatsheet

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 3a–3g, 6b, 6d, 7a–7c · **SCS-C03:** 6.2.1 · **Teaching note:** [Core workflow](../teaching/terraform/03-core-workflow.md), [Maintaining infrastructure](../teaching/terraform/07-maintaining-infrastructure.md) · **Lab:** [01 First apply](../labs/01-first-apply/README.md), [06 Drift and import](../labs/06-drift-and-import/README.md) · Checked against Terraform 1.17 docs; the exam tests 1.12. Replace `UPPER_SNAKE` placeholders. Commands marked **[changes state]** modify state, infrastructure, or both.

## Core workflow

```bash
terraform init                      # install providers and modules, configure the backend
terraform fmt -check -recursive     # style
terraform validate                  # syntax and internal consistency; no API calls, no state
terraform plan -out=tfplan          # compare configuration, state, and real infrastructure
terraform show tfplan               # review exactly what will be applied
terraform apply tfplan              # [changes state] apply the saved plan; no prompt
terraform destroy                   # [changes state] alias for: terraform apply -destroy
```

Global options go **before** the subcommand: `terraform -chdir=DIR plan`, `terraform -help plan`, `terraform -version`.

## init

| Flag | Effect |
|---|---|
| `-upgrade` | Pick the newest provider and module versions the constraints allow, and rewrite `.terraform.lock.hcl`. Without it, the lock file's selections are kept. |
| `-reconfigure` | Use the new backend settings and **ignore** the existing ones. No state is migrated. |
| `-migrate-state` | Copy existing state to the newly configured backend. Prompts for confirmation. |
| `-force-copy` | Answer yes to migration prompts. Implies `-migrate-state`. |
| `-backend-config=FILE` or `-backend-config="KEY=VALUE"` | Supply the rest of a partial backend configuration. Repeatable. |
| `-backend=false` | Skip backend setup. Use for `validate` in CI. |
| `-lockfile=readonly` | Verify checksums against the lock file and fail instead of changing it. Conflicts with `-upgrade`. Use in CI. |
| `-get=false` | Skip module installation |
| `-plugin-dir=PATH` | Load providers only from this directory |
| `-from-module=SOURCE` | Copy a module into an empty directory first |
| `-input=false` | Fail instead of prompting |

```bash
terraform init -input=false -lockfile=readonly                    # CI
terraform init -backend-config=backend-ENV.hcl                    # partial backend configuration
terraform init -migrate-state                                     # [changes state] after editing the backend block
terraform init -upgrade                                           # after loosening a version constraint
terraform get -update                                             # modules only
```

`init` is safe to repeat. Run it again after changing the backend, a provider constraint, or a module `source` or `version`.

## validate and fmt

```bash
terraform init -backend=false && terraform validate               # no credentials needed
terraform validate -json
terraform fmt                       # rewrites files in the current directory
terraform fmt -recursive            # include subdirectories
terraform fmt -check                # change nothing; non-zero exit if any file needs formatting
terraform fmt -diff                 # show the changes
terraform fmt -check -diff -recursive                             # CI gate
```

`validate` does not check that values are accepted by the provider's API, and does not read state. `fmt` fixes layout only, not names or structure.

## plan

| Flag | Effect |
|---|---|
| `-out=FILE` | Save the plan. `apply FILE` then applies exactly that plan. The file holds sensitive values in clear text. |
| `-refresh-only` | Planning mode: update state and outputs to match reality; propose no infrastructure change |
| `-destroy` | Planning mode: plan to destroy everything in state |
| `-refresh=false` | Skip reading real infrastructure. Faster; misses drift. |
| `-replace=ADDRESS` | Force destroy and re-create of one resource instance. Repeatable. Replaces `taint`. |
| `-target=ADDRESS` | Limit the plan to one resource or module and its dependencies. For recovery, not routine use. |
| `-var 'NAME=VALUE'` | Set one root input variable. Repeatable. |
| `-var-file=FILE` | Set variables from a `.tfvars` file. Repeatable. |
| `-detailed-exitcode` | Exit `0` no changes, `1` error, `2` succeeded with changes present |
| `-generate-config-out=FILE` | Write HCL for resources named in `import` blocks that have no `resource` block yet. The file must not exist. Experimental **(verify)**. |
| `-lock=false` | Do not take the state lock. Dangerous if others can run. |
| `-lock-timeout=DURATION` | Wait for a lock, for example `60s`. Default `0s`. |
| `-parallelism=N` | Concurrent operations. Default 10. |
| `-input=false`, `-no-color`, `-json`, `-compact-warnings` | Automation and output control |

```bash
terraform plan -var-file=prod.tfvars -out=tfplan
terraform plan -detailed-exitcode -lock-timeout=60s -input=false   # drift check in a scheduled job
terraform plan -refresh-only                                       # what changed outside Terraform?
terraform plan -replace=aws_instance.web
terraform plan -target=module.network
terraform plan -destroy -out=destroy.tfplan
terraform plan -generate-config-out=generated.tf                   # with import blocks present
```

### Plan symbols

| Symbol | Meaning |
|---|---|
| `+` | Create |
| `-` | Destroy |
| `~` | Update in place |
| `-/+` | Replace: destroy, then create (the default order) |
| `+/-` | Replace: create, then destroy (`create_before_destroy`) |
| `<=` | Read a data source during apply |
| `# forces replacement` | The argument on that line cannot be changed in place |
| `(known after apply)` | Value is computed by the provider at apply time |
| `(sensitive value)` | Redacted in output; still in the plan file and state |

Summary line: `Plan: 2 to add, 1 to change, 0 to destroy.` Imports, moves, and forgotten (`removed`) resources are reported there too.

## apply and destroy

```bash
terraform apply                              # [changes state] plan, prompt, apply
terraform apply tfplan                       # [changes state] saved plan; planning flags are not accepted here
terraform apply -auto-approve                # [changes state] no prompt
terraform apply -refresh-only                # [changes state] accept drift into state; replaces `terraform refresh`
terraform apply -replace=ADDRESS             # [changes state]
terraform apply -var 'NAME=VALUE' -var-file=FILE.tfvars   # [changes state]
terraform destroy -target=ADDRESS            # [changes state] one resource and everything depending on it
terraform apply -destroy -auto-approve       # [changes state]
```

A saved plan is rejected as **stale** if state changed after it was made. A failed apply is not rolled back: state records what was created, and the next plan continues from there.

## Inspect

```bash
terraform show                               # current state, human readable
terraform show -json > state.json            # machine readable; includes sensitive values
terraform show -json tfplan > plan.json      # plan for policy tools (OPA, Sentinel mocks, checkov)
terraform output                             # all root outputs; sensitive ones shown as <sensitive>
terraform output -raw OUTPUT_NAME            # one value, unquoted, sensitive or not
terraform output -json                       # all values in clear text
terraform console                            # evaluate expressions against state: var.x, cidrsubnet("10.0.0.0/16", 8, 2)
echo 'local.common_tags' | terraform console
terraform graph | dot -Tsvg > graph.svg      # needs Graphviz
terraform graph -type=plan
terraform version                            # also lists provider versions selected in this directory
terraform version -json
terraform modules                            # declared modules and their sources (added after 1.9) (verify)
```

## state

| Command | Use |
|---|---|
| `terraform state list` | Addresses of everything in state. Accepts an address prefix, or `-id=ID`. |
| `terraform state show ADDRESS` | Attributes of one resource instance |
| `terraform state mv SOURCE DEST` | **[changes state]** Rename or move an address. Prefer a `moved` block. |
| `terraform state rm ADDRESS` | **[changes state]** Stop managing; the real object is left alone. Prefer a `removed` block. |
| `terraform state pull` | Print the raw state JSON to stdout |
| `terraform state push FILE` | **[changes state]** Overwrite remote state. Refuses a different lineage or a lower serial unless `-force`. |
| `terraform state replace-provider FROM TO` | **[changes state]** Change the provider source address recorded for resources |
| `terraform state identities` | Resource identity data held in state, as JSON (added in 1.12) **(verify)** |

```bash
terraform state list module.network
terraform state show 'aws_s3_bucket.logs["audit"]'                 # quote addresses with brackets
terraform state mv -dry-run aws_s3_bucket.old aws_s3_bucket.new
terraform state pull > backup-$(date +%Y%m%d%H%M%S).tfstate        # do this before any state surgery
```

Every state-modifying subcommand writes a backup file; it cannot be turned off. Detail: [state and backends cheatsheet](terraform-state-and-backends.md).

## import, test, and locks

```bash
terraform import ADDRESS ID                          # [changes state] the resource block must already exist
terraform import 'aws_iam_role.app' app-role         # [changes state]
terraform test                                       # runs tests/*.tftest.hcl and *.tftest.hcl in the root; creates and destroys real resources unless mocked
terraform test -filter=tests/bucket.tftest.hcl -verbose
terraform test -junit-xml=results.xml
terraform force-unlock LOCK_ID                       # [changes state] only when the lock holder is certainly dead
```

The CLI `import` command writes state immediately and generates no configuration. An `import` block goes through plan and review; see the [HCL cheatsheet](terraform-hcl.md). Stuck locks: [state lock and corruption runbook](../runbooks/terraform-state-lock-and-corruption.md).

## providers

```bash
terraform providers                                  # which module requires which provider
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64   # add checksums for every platform the team and CI use
terraform providers mirror MIRROR_DIR                # download providers for an air-gapped mirror
terraform providers schema -json > schema.json       # every resource type and argument of the installed providers
```

Commit `.terraform.lock.hcl`. It pins exact provider versions and checksums; it does not cover modules.

## workspace

```bash
terraform workspace list                             # * marks the current one
terraform workspace show
terraform workspace new WORKSPACE_NAME               # [changes state] creates an empty state and switches to it
terraform workspace select WORKSPACE_NAME
terraform workspace select -or-create WORKSPACE_NAME
terraform workspace delete WORKSPACE_NAME            # [changes state] refuses if the state still tracks resources, unless -force
```

The `default` workspace cannot be deleted. Reference the name with `terraform.workspace`. CLI workspaces share one backend and one set of credentials; they are not an isolation boundary.

## login

```bash
terraform login                                      # app.terraform.io; opens a browser and stores an API token
terraform login HOSTNAME
terraform logout
```

The token is saved in **plain text** in `credentials.tfrc.json` under `~/.terraform.d/` (`%APPDATA%\terraform.d\` on Windows). In CI, set `TF_TOKEN_app_terraform_io` instead.

## Environment variables

| Variable | Effect |
|---|---|
| `TF_LOG` | Log level to stderr: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `JSON` (trace level as JSON). Unset or `off` disables. Trace logs can contain secrets. |
| `TF_LOG_CORE`, `TF_LOG_PROVIDER` | Same levels, for Terraform core or provider plugins only |
| `TF_LOG_PATH` | Append logs to this file. Needs one of the `TF_LOG` variables set. |
| `TF_VAR_name` | Value for input variable `name`. Overridden by every other source; overrides only the `default`. |
| `TF_CLI_ARGS` | Extra arguments added to every command; flags typed on the command line win |
| `TF_CLI_ARGS_name` | Extra arguments for one subcommand: `TF_CLI_ARGS_plan="-refresh=false"` |
| `TF_INPUT` | `false` or `0` behaves as `-input=false` |
| `TF_IN_AUTOMATION` | Any non-empty value trims "next step" hints from output. Cosmetic only. |
| `TF_DATA_DIR` | Replace `.terraform` as the per-directory data location |
| `TF_WORKSPACE` | Select a workspace without `workspace select` |
| `TF_PLUGIN_CACHE_DIR` | Shared provider download cache. The directory must exist. |
| `TF_CLI_CONFIG_FILE` | Path to the CLI configuration file (`.terraformrc`, or `terraform.rc` on Windows) |
| `TF_TOKEN_hostname` | API token for a host; dots become underscores: `TF_TOKEN_app_terraform_io` |
| `TF_REGISTRY_CLIENT_TIMEOUT`, `TF_REGISTRY_DISCOVERY_RETRY` | Registry client timeout (default 10 seconds) and retry count |
| `TF_STATE_PERSIST_INTERVAL` | Seconds between state writes to a remote backend during apply (minimum 20) |

```bash
TF_LOG=DEBUG TF_LOG_PATH=./terraform.log terraform plan
export TF_VAR_environment=prod TF_IN_AUTOMATION=1 TF_INPUT=0
```

## Deprecated and removed

| Command | Status | Use instead |
|---|---|---|
| `terraform taint ADDRESS` | Deprecated since 0.15.2 | `terraform apply -replace=ADDRESS`. The replacement shows in the plan before anything is marked. |
| `terraform untaint ADDRESS` | Still present; only relevant to objects tainted by `taint` or by a failed create | Nothing to undo when you use `-replace`: drop the flag |
| `terraform refresh` | Deprecated. Writes state with no review. | `terraform apply -refresh-only`, or `plan -refresh-only` to look first |
| `terraform env` | Removed; old name for `workspace` **(verify)** | `terraform workspace` |
| `init -get-plugins=false` | Removed in 0.15 | `-plugin-dir`, or `provider_installation` in the CLI configuration |
| `terraform import` (CLI) | Supported, not deprecated | `import` block for anything reviewed or repeated |
| `terraform state mv`, `state rm` | Supported, not deprecated | `moved` and `removed` blocks |

## Files in a working directory

| Path | Commit it? | Holds |
|---|---|---|
| `*.tf`, `*.tf.json`, `*.tftest.hcl` | Yes | Configuration and tests |
| `.terraform.lock.hcl` | **Yes** | Provider versions and checksums |
| `.terraform/` | No | Provider binaries, module copies, backend settings (including values passed with `-backend-config`) |
| `terraform.tfstate`, `terraform.tfstate.backup`, `terraform.tfstate.d/` | **Never** | Local state, previous state, per-workspace local state |
| `*.tfvars` | Only if free of secrets | Variable values. `terraform.tfvars` and `*.auto.tfvars` load automatically. |
| `tfplan` and other saved plans | No | Full plan, including sensitive values |
| `crash.log` | No | Panic output |
