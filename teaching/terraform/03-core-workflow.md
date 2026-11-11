# Terraform 3: Core Terraform Workflow

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 3a–3g · **SCS-C03:** 6.2.1 · **Related:** [fundamentals](02-terraform-fundamentals.md), [state management](06-state-management.md), [HCP Terraform](08-hcp-terraform.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [lab 01: first apply](../../labs/01-first-apply/README.md), [lab 07: tests and guardrails](../../labs/07-tests-and-guardrails/README.md), [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md)

## Why this matters

The workflow is where the controls sit. The plan is the one moment when a proposed change to IAM, network, or encryption settings is fully spelled out and nothing has happened yet. A team that reviews the plan, and applies exactly the plan it reviewed, has change control. A team that runs `terraform apply -auto-approve` from laptops has a fast way to make mistakes.

## Mental model

**Write, plan, apply. Everything else supports one of those three.**

```
   WRITE                       PLAN                          APPLY
   edit .tf files              terraform plan -out=tfplan    terraform apply tfplan
        │                           │                             │
   terraform fmt               refresh state, diff against   call provider APIs,
   terraform init              configuration, show actions   write new state
   terraform validate               │                             │
        │                      review (human + policy)            │
        └───────────────────────────┴──────────◀──────────────────┘
                                 repeat
                                                    terraform destroy = apply in destroy mode
```

| Command | Reads configuration | Contacts provider APIs | Reads state | Writes state | Changes infrastructure |
|---|---|---|---|---|---|
| `fmt` | Yes | No | No | No | No |
| `init` | Yes | No (registry and backend only) | Backend setup | Only when migrating | No |
| `validate` | Yes | No | No | No | No |
| `plan` | Yes | Yes (read-only) | Yes | No | No |
| `apply` | Yes | Yes | Yes | Yes | Yes |
| `destroy` | Yes | Yes | Yes | Yes | Yes |

## Objective 3a: The core workflow

1. **Write.** Author or change configuration, in version control, on a branch.
2. **Plan.** Preview what Terraform would do. Repeat write and plan until the plan is what you intend.
3. **Apply.** Execute the plan. Terraform changes real infrastructure and updates state.

How it scales:

| Setting | Write | Plan | Apply |
|---|---|---|---|
| **Individual** | Edit locally | `terraform plan` as a feedback loop | `terraform apply`, read the plan again, type `yes` |
| **Team** | Branch per change | Pipeline posts the plan on the pull request for review | After merge, pipeline applies; the final plan is checked again because the world may have moved |
| **HCP Terraform** | Same, with variables and state held centrally | **Speculative plan** runs automatically on the pull request | Run on merge, with an approval step and policy checks |

In a team, credentials for plan and apply live in the pipeline, not on laptops. The plan on the pull request is the change-review artifact: reviewers approve the *effect*, not only the code.

## Objective 3b: Init

`terraform init` prepares a working directory. It is the first command to run in a new or freshly cloned configuration.

What it does:

1. **Initializes the backend**: where state is stored.
2. **Installs child modules** referenced by `module` blocks into `.terraform/modules/`.
3. **Installs providers** into `.terraform/providers/` and writes the selections to `.terraform.lock.hcl`.

It is always safe to run again. It never deletes configuration or state.

Run it again when you:

- add or change a provider requirement or version constraint
- add a module or change a module's `source` or `version`
- change the backend configuration
- clone the repository or delete `.terraform/`

| Option | Effect |
|---|---|
| `-upgrade` | Ignore the lock file's selections and take the newest provider and module versions the constraints allow |
| `-lockfile=readonly` | Verify providers against the lock file and refuse to modify it. Cannot be combined with `-upgrade`. |
| `-backend-config=FILE_OR_KEY_VALUE` | Supply backend settings left out of the code (**partial configuration**) |
| `-migrate-state` | After a backend change, copy existing state to the new backend |
| `-reconfigure` | After a backend change, use the new backend and ignore existing state; nothing is migrated |
| `-backend=false` | Skip backend setup; enough for `validate` |
| `-input=false` | Never prompt; fail instead. For pipelines. |

If the backend block changes, plain `init` stops and makes you choose `-migrate-state` or `-reconfigure`.

Security notes: `init` is the step that downloads and trusts third-party code, so in a pipeline run it with `-lockfile=readonly` against a committed lock file (see [fundamentals](02-terraform-fundamentals.md)). The `.terraform/` directory can hold backend settings passed at init time; keep it out of version control and out of build artifacts.

## Objective 3c: Validate

`terraform validate` checks that the configuration is **syntactically valid and internally consistent**: argument names exist, required arguments are present, value types are right, references point at things that are declared.

- It makes **no** calls to provider APIs and does not read state. It needs no credentials.
- It **does** need an initialized directory, because the provider schemas come from the installed plugins. `terraform init -backend=false` is enough.
- `-json` gives machine-readable output for editors and pipelines.
- `plan` and `apply` validate implicitly. The standalone command exists for fast feedback and for checking modules in a pipeline.

| Caught by `validate` | Not caught by `validate` |
|---|---|
| Misspelled argument, unknown resource type | A bucket name that is already taken |
| A string where a list is required | An IAM policy that is valid JSON but too permissive |
| Reference to an undeclared variable or resource | Missing permissions for the deployment role |
| Missing required argument | An AMI ID that does not exist in the Region |

Valid is not the same as secure or deployable. Security scanning of the code and the plan is a separate step.

## Objective 3d: Plan

`terraform plan` produces an **execution plan**:

1. Reads the current state and **refreshes** it by querying the real resources (in memory; plain `plan` does not write state).
2. Compares that with the configuration.
3. Prints the actions needed to make reality match the configuration.

It changes nothing. A plan that is only displayed is a **speculative plan**. A plan written to a file with `-out` is a **saved plan** and can be applied exactly.

### Reading a plan

```
Terraform will perform the following actions:

  # aws_s3_bucket.logs must be replaced
-/+ resource "aws_s3_bucket" "logs" {
      ~ arn    = "arn:aws:s3:::audit-logs-111122223333" -> (known after apply)
      ~ bucket = "audit-logs-111122223333" -> "audit-logs-111122223333-use1" # forces replacement
      ~ id     = "audit-logs-111122223333" -> (known after apply)
        # (4 unchanged attributes hidden)
    }

  # aws_s3_bucket_public_access_block.logs will be destroyed
  # (because aws_s3_bucket_public_access_block.logs is not in configuration)
  - resource "aws_s3_bucket_public_access_block" "logs" {
      - block_public_acls = true -> null
      - bucket            = "audit-logs-111122223333" -> null
        # (4 more attributes trimmed from this example)
    }

Plan: 1 to add, 0 to change, 2 to destroy.
```

| Symbol | Meaning |
|---|---|
| `+` | Create |
| `-` | Destroy |
| `~` | Update in place |
| `-/+` | Replace: destroy, then create |
| `+/-` | Replace: create, then destroy (`create_before_destroy`) |
| `<=` | Read a data source during apply |

| Phrase | Meaning |
|---|---|
| `# forces replacement` | This argument cannot be changed in place; the resource will be destroyed and recreated |
| `(known after apply)` | The value comes from the API and does not exist yet |
| `(sensitive value)` | Hidden from output. Still present in state and in a saved plan. |
| `Plan: X to add, Y to change, Z to destroy` | The summary line. A replacement counts once in add and once in destroy. |

How to review one, as a security practitioner: read the summary line first, and stop on any destroy or replace you did not expect. In the example a rename destroys a log bucket, and someone has deleted the public access block from the code. Then read every change to IAM policies, trust policies, resource policies, security group rules, KMS key policies, and logging resources line by line.

### Modes and options

| Option | Effect |
|---|---|
| `-out=FILE` | Save the plan for `terraform apply FILE` |
| `-destroy` | Planning mode: plan to destroy everything in state |
| `-refresh-only` | Planning mode: show and accept changes made outside Terraform; proposes no infrastructure changes. Used for drift. |
| `-refresh=false` | Skip the refresh and trust state. Faster; misses drift. |
| `-replace=ADDRESS` | Force replacement of one resource instance. Replaces the old `terraform taint` command. |
| `-target=ADDRESS` | Limit the plan to one resource and its dependencies. For exceptional circumstances only, not routine use. |
| `-var 'NAME=VALUE'`, `-var-file=FILE` | Set input variables |
| `-detailed-exitcode` | Exit 0: no changes. Exit 1: error. Exit 2: changes present. Used for drift detection jobs. |
| `-lock-timeout=DURATION` | Wait for a state lock instead of failing immediately |
| `-input=false` | Never prompt for missing variables |

**A saved plan file is sensitive.** It contains the configuration, variable values, and planned attribute values, with secrets in clear text. Store it as a short-lived, access-controlled pipeline artifact. `terraform show FILE` prints it for humans; `terraform show -json FILE` produces JSON for policy tools, also with sensitive values in clear text.

## Objective 3e: Apply

`terraform apply` executes a plan.

| Mode | Command | Behavior |
|---|---|---|
| **Automatic plan** | `terraform apply` | Creates a new plan, shows it, and asks for approval. Only the literal answer `yes` proceeds. Accepts all the planning options (`-var`, `-replace`, `-target`, `-refresh-only`, `-destroy`). |
| **Saved plan** | `terraform apply FILE` | Executes exactly the saved plan with **no prompt**. Planning options are not accepted, because the decisions are already in the file. |

- **`-auto-approve`** skips the prompt in automatic plan mode. With it, nobody has seen the plan that runs.
- If state has changed since a plan was saved, Terraform rejects it as **stale** and you must plan again.
- Apply takes the **state lock** for its duration. See [state management](06-state-management.md).
- Operations run in dependency order, up to 10 at a time by default (`-parallelism=N`).
- **There is no rollback.** If an operation fails, Terraform stops, records in state everything that did succeed, and exits. Fix the cause and apply again; it picks up the remainder.
- After a successful apply, state is updated and root module **outputs** are printed.

The pipeline pattern that preserves review:

```bash
terraform init -input=false -lockfile=readonly
terraform fmt -check -recursive
terraform validate
terraform plan -input=false -out=tfplan
terraform show -json tfplan > tfplan.json    # sensitive: clear-text values. Feed to policy checks.
# ...human approval and policy checks happen here...
terraform apply -input=false tfplan          # changes infrastructure and state
```

What was reviewed is what runs. Plan and apply can also use different roles: a read-only role for plan on pull requests, a write role for apply on the protected branch. See [securing Terraform on AWS](09-securing-terraform-on-aws.md).

## Objective 3f: Destroy

`terraform destroy` deletes every resource managed by the configuration in the current workspace. It is an alias for `terraform apply -destroy`: it builds a destroy plan, shows it, and asks for `yes`.

- Preview without acting: `terraform plan -destroy`.
- Resources are destroyed in **reverse dependency order**.
- It destroys only what is in state. Resources created outside Terraform are untouched and may block deletion (a non-empty bucket, a VPC with a stray interface).
- `-target=ADDRESS` narrows it to one resource and whatever depends on it. Exceptional use only.
- `-auto-approve` skips the prompt.

Three other ways resources get destroyed, which matter more in practice:

| Action | Result |
|---|---|
| Delete a `resource` block and apply | That resource is destroyed. This is the normal way to remove one thing. |
| Change an argument that forces replacement | Destroyed and recreated |
| Lower `count` or remove a `for_each` key | The surplus instances are destroyed |

Guards against destroying the wrong thing:

```hcl
resource "aws_kms_key" "logs" {
  description         = "Encrypts the audit log bucket"
  enable_key_rotation = true

  lifecycle {
    prevent_destroy = true
  }
}
```

**`prevent_destroy`** makes any plan that would destroy the resource fail. It protects only while the block is still in the code: delete the whole block and the guard goes with it. Back it with AWS-side controls such as S3 Object Lock, KMS deletion waiting periods, deletion protection flags, and a deployment role that lacks delete permissions on critical resources. To stop managing a resource *without* destroying it, remove it from state instead: see [state management](06-state-management.md).

Destroy is routine for short-lived environments and almost never right for production.

## Objective 3g: Format

`terraform fmt` rewrites configuration files into the canonical style: two-space indentation, aligned `=` signs within a block, consistent spacing and blank lines.

| Option | Effect |
|---|---|
| (none) | Rewrite files in the current directory and list the ones changed |
| `-recursive` | Include subdirectories. Off by default, so modules in subfolders are skipped without it. |
| `-check` | Change nothing. Exit non-zero if any file needs formatting. For pipelines. |
| `-diff` | Show the changes |
| `-write=false` | Do not write files (implied by `-check`) |
| `-list=false` | Do not list the files |

- It is purely cosmetic. It does not validate, does not reorder blocks, and does not rename anything.
- It needs no `init`, no credentials, and no state.
- It covers `.tf` and `.tfvars` files, and test files (`.tftest.hcl`).
- The canonical style can change slightly between Terraform versions; run it again after upgrading.

`fmt` enforces a subset of the HashiCorp **style guide**. The rest is convention: lowercase names with underscores, no resource type repeated in the name, `main.tf` / `variables.tf` / `outputs.tf` / `providers.tf` / `terraform.tf` file layout, a description on every variable and output. The security value is indirect: consistent formatting keeps diffs small, so the real change in a pull request is easy to see.

## Worked examples

**1. A reviewer approved a pull request whose plan showed one security group rule added. The apply after merge also deleted a NAT gateway.**
The pipeline ran a fresh `terraform apply -auto-approve` after merge, and someone had changed the configuration or the infrastructure in between. Save the plan with `-out`, apply that file, and require re-approval if the plan must be regenerated.

**2. A plan for a "tag change" on an RDS instance shows `-/+` and `# forces replacement` on `identifier`.**
Someone also renamed the instance. Replacement means a new, empty database. Stop, revert the rename, and plan again. The summary line "1 to add, 1 to destroy" was the warning.

**3. A team wants a nightly job that reports drift without changing anything.**
`terraform plan -detailed-exitcode -input=false -lock-timeout=60s` with a read-only role. Exit code 2 means the real infrastructure and the code disagree; send the plan to the team. Investigation steps: [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md).

**4. An apply fails halfway with an access-denied error on the eleventh of twenty resources.**
The first ten exist and are in state. Nothing rolls back. Fix the permission (or the code) and run plan and apply again; Terraform plans only what remains.

**5. A pull request check must fail on unformatted or invalid code without needing AWS credentials.**
`terraform fmt -check -recursive`, then `terraform init -backend=false -input=false -lockfile=readonly` and `terraform validate`. None of the three contacts AWS.

## Pitfalls and exam traps

- `init` comes first. `validate`, `plan`, and `apply` fail in an uninitialized directory. `fmt` does not need it.
- `validate` does not contact the cloud and does not need credentials. `plan` does both.
- `plan` does not change infrastructure and plain `plan` does not write state.
- `terraform apply FILE` does not prompt. `-auto-approve` is irrelevant there.
- A saved plan cannot be combined with `-var`, `-target`, or other planning options.
- `terraform destroy` is `terraform apply -destroy`. Preview with `terraform plan -destroy`.
- `-refresh-only` updates state to match reality. It never changes infrastructure.
- `-replace` is the current way to force recreation. `terraform taint` is deprecated.
- `-target` is for recovery, not for everyday use. It leaves the rest of the configuration unreconciled.
- `-/+` destroys first. `+/-` creates first.
- `sensitive` hides values in plan output only. The saved plan file and state still hold them.
- `fmt` without `-recursive` ignores subdirectories. `fmt -check` changes nothing and signals through its exit code.
- `init -upgrade` changes the lock file. `init -reconfigure` abandons the old backend's state without copying it.
- A failed apply leaves a partial result. There is no automatic rollback.

## Self-check

1. Name the three steps of the core workflow and the command for the last two.
2. What three things does `terraform init` set up?
3. You changed the `backend` block. What must you decide when you next run `init`?
4. Does `terraform validate` need credentials? Does it need `init`? Why?
5. In plan output, what do `~`, `-/+`, and `(known after apply)` mean?
6. Why apply a saved plan file in a pipeline instead of running `terraform apply -auto-approve`?
7. An apply fails after creating half the resources. What is in state, and what do you do?
8. Which command and option fail a pipeline when files are not formatted, including those in module subfolders?

<details>
<summary>Answers</summary>

1. Write, plan, apply. `terraform plan` and `terraform apply`.
2. The backend, child modules, and provider plugins (recording provider selections in the dependency lock file).
3. Whether to copy existing state to the new backend (`-migrate-state`) or start with the new backend and ignore the existing state (`-reconfigure`).
4. No credentials: it makes no provider API calls and reads no state. It does need `init`, because it checks the configuration against provider schemas from the installed plugins. `terraform init -backend=false` is enough.
5. `~` is an in-place update. `-/+` is a replacement that destroys and then creates. `(known after apply)` is a value the API will supply once the resource exists.
6. The saved plan is exactly what reviewers and policy checks saw, and Terraform refuses it if state has changed since. `-auto-approve` builds a new plan that nobody has reviewed.
7. The resources that were created successfully are recorded in state. Nothing is rolled back. Fix the cause, then plan and apply again.
8. `terraform fmt -check -recursive`.

</details>

## Further reading

- [The core Terraform workflow](https://developer.hashicorp.com/terraform/intro/core-workflow)
- [`terraform init`](https://developer.hashicorp.com/terraform/cli/commands/init)
- [`terraform validate`](https://developer.hashicorp.com/terraform/cli/commands/validate)
- [`terraform plan`](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [`terraform apply`](https://developer.hashicorp.com/terraform/cli/commands/apply)
- [`terraform destroy`](https://developer.hashicorp.com/terraform/cli/commands/destroy)
- [`terraform fmt`](https://developer.hashicorp.com/terraform/cli/commands/fmt)
- [`terraform show`](https://developer.hashicorp.com/terraform/cli/commands/show)
- [Style guide](https://developer.hashicorp.com/terraform/language/style)
- [Running Terraform in automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform)
