# Terraform 7: Maintaining Infrastructure

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 7a–7c · **Related:** [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [state management](06-state-management.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [drift runbook](../../runbooks/terraform-unexpected-drift.md), [state exposure runbook](../../runbooks/terraform-state-exposure.md), [lab 06](../../labs/06-drift-and-import/README.md)

## Why this matters

Most environments were not born in Terraform. Buckets, roles, and security groups created by hand have no review history, no plan, and no drift detection. Import brings them under management without rebuilding them. Once resources are managed, the day-two work is reading state to answer "what does Terraform think exists?" and reading logs to answer "why did that fail?" Both of those outputs can contain secrets, so how you inspect matters as much as what you inspect.

## Mental model

**Import binds an existing object to a resource address. It does not write your configuration for you, and it does not change the object.**

```
   Existing bucket in AWS            Configuration                    State
   (created by hand)                 resource "aws_s3_bucket" "logs"  aws_s3_bucket.logs -> bucket ID
            │                                  ▲                               ▲
            └───────── import ─────────────────┴───── binds address to ID ─────┘

   After import: terraform plan must show no changes. If it shows changes, the
   configuration does not yet describe the real object, and apply would alter it.
```

Three questions, three tool sets:

| Question | Tools |
|---|---|
| How do I bring this under management? | `import` block, `terraform import`, `-generate-config-out` |
| What does Terraform believe exists? | `state list`, `state show`, `show`, `output`, `console` |
| What is Terraform actually doing? | `TF_LOG` and related environment variables |

## Objective 7a: Importing existing infrastructure

There are two ways to import. Both need the resource's **import ID**, whose format depends on the resource type and is documented at the bottom of each resource's page in the provider documentation: a bucket name for `aws_s3_bucket`, an instance ID for `aws_instance`, and so on.

| | `import` block | `terraform import` command |
|---|---|---|
| Form | Declarative, in a `.tf` file | Imperative, one command per resource |
| Review | Shows in `terraform plan` as "will be imported" before anything is written | Writes state immediately. No plan. |
| Many resources | `for_each` on the block | Run the command repeatedly |
| Generates configuration | Yes, with `-generate-config-out` | No. The `resource` block must already exist. |
| Works in pipelines and HCP Terraform runs | Yes, it is part of a normal plan and apply | Needs CLI access to state |
| Available since | Terraform 1.5 **(verify)** | All versions |

HashiCorp recommends the block. Know both for the exam.

### The import block

```hcl
import {
  to = aws_s3_bucket.logs
  id = "EXISTING_BUCKET_NAME"
}

resource "aws_s3_bucket" "logs" {
  bucket = "EXISTING_BUCKET_NAME"
}
```

- `to` is the address to bind, and it must match a `resource` block (or one that will be generated).
- `id` is the import ID. It can be an expression, but its value must be known at plan time.
- `identity` is an alternative to `id` for resource types that publish a structured identity, for example account, Region, and bucket name. Use one or the other. It is newer than the 1.12 exam target **(verify)**.
- `provider` selects an aliased provider configuration, for a resource in another Region or account.
- `for_each` imports many similar resources with one block.

Run `terraform plan`. The summary reads `Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.` Run `terraform apply` to write the binding into state. After that the `import` block has done its job. You can delete it, or leave it as a record; it does nothing on later runs.

### The command

```bash
terraform import aws_s3_bucket.logs EXISTING_BUCKET_NAME   # changes state: binds the bucket to this address
```

Syntax is `terraform import ADDRESS ID`. Write the `resource` block first, then run the command, then run `terraform plan` and edit the block until the plan is empty.

### Generating configuration

Writing a resource block that exactly matches a hand-built resource is tedious. Terraform can draft it.

```bash
terraform plan -generate-config-out=generated.tf   # writes a new file; changes no state or infrastructure
```

1. Write only the `import` block. Do not write the `resource` block.
2. Run the plan with `-generate-config-out` and a path that **does not already exist**. Terraform errors if the file exists.
3. Review and edit the generated file. It is Terraform's best guess: it may set arguments that conflict with each other, hard-code values that should be references, and include defaults you do not need.
4. Run `terraform plan` until it shows only the import, then `terraform apply`.

The feature has been labeled experimental since it arrived, and the generated format may change **(verify)**.

### Import rules

- Import one real object to **one** address. Binding it to two addresses means two resources fight over it.
- Import never modifies the real object. The first apply afterward might, if configuration and reality differ.
- A provider configuration used for import cannot depend on a data source or another resource's output. It can use variables.
- Generated configuration and state for an imported resource contain whatever the API returns, including secrets. Review `generated.tf` before committing it.
- Import is how you take back a resource that was removed from state with `terraform state rm` or a `removed` block.

For a security team, import is the path from "we found an unmanaged, hand-built IAM role" to "that role is in code, reviewed, and watched for drift." Hands-on: [lab 06](../../labs/06-drift-and-import/README.md).

## Objective 7b: Inspecting state with the CLI

All of these are read-only. None changes infrastructure, and none changes state.

| Command | Shows | Notes |
|---|---|---|
| `terraform state list` | Every resource address in state | Accepts an address to filter, for example `terraform state list module.network`, and `-id=ID` to find by resource ID |
| `terraform state show ADDRESS` | All attributes of one resource | Sensitive attributes print as `(sensitive value)` |
| `terraform show` | The whole current state, human-readable | Sensitive values are masked |
| `terraform show PLAN_FILE` | A saved plan, human-readable | Review exactly what an apply will do |
| `terraform show -json` | State or a plan as JSON | Machine-readable, used by policy tools. **Sensitive values appear in plaintext.** |
| `terraform output` | All root module outputs | Sensitive outputs print as `<sensitive>` |
| `terraform output NAME` | One output | **Prints a sensitive value in plaintext** |
| `terraform output -raw NAME` | One string output with no quotes | For scripts. Also prints sensitive values. |
| `terraform output -json` | All outputs as JSON | **Includes sensitive values in plaintext** |
| `terraform console` | An interactive prompt for evaluating expressions against state and configuration | Test a function or inspect a value, for example `length(var.subnets)` or `aws_s3_bucket.logs.arn` |
| `terraform state pull` | Raw state JSON | Everything, unmasked |

Points worth knowing:

- `state list` gives addresses. `state show` gives one resource's detail. `show` gives everything. That distinction is a standard exam question.
- Masking is a display feature. Anyone who can run these commands against a backend can get the unmasked values with `-json`, `output NAME`, or `state pull`. Access to state is access to its secrets. See [state management](06-state-management.md).
- `terraform console` takes a state lock while it is open, so close it when you are done. It evaluates expressions; it does not change resources.
- Outputs only exist in state after an apply. `terraform output` on a fresh configuration shows nothing.
- In a pipeline, do not print `terraform show -json` or `terraform output -json` to the build log. Write them to a file that is handled as a secret, or not at all.

During an incident, `terraform state list` plus `terraform plan -refresh-only` is the quickest inventory of what is managed and what has changed. See the [drift runbook](../../runbooks/terraform-unexpected-drift.md). Full flag lists are in the [CLI cheatsheet](../../cheatsheets/terraform-cli.md).

## Objective 7c: Verbose logging

Normal output shows what Terraform decided. Logs show how: provider plugin start-up, the dependency graph walk, and each API request and response. Logging is controlled by environment variables, not flags.

| Variable | Effect |
|---|---|
| `TF_LOG` | Turns logging on at the given level for both Terraform core and providers. Logs go to stderr. |
| `TF_LOG_CORE` | Level for Terraform core only |
| `TF_LOG_PROVIDER` | Level for provider plugins only |
| `TF_LOG_PATH` | Append logs to this file. Has no effect unless one of the level variables is also set. |

Levels, most verbose first: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`. Setting `TF_LOG=JSON` gives `TRACE`-level output in JSON, a format HashiCorp does not treat as a stable interface.

```bash
export TF_LOG_PROVIDER=DEBUG
export TF_LOG_PATH=./terraform-debug.log
terraform plan
unset TF_LOG_PROVIDER TF_LOG_PATH
```

When to reach for it:

| Symptom | Setting |
|---|---|
| A provider returns an unhelpful error, such as a bare `AccessDenied` | `TF_LOG_PROVIDER=DEBUG` to see which API call failed and with what parameters |
| Terraform hangs, crashes, or builds an unexpected dependency order | `TF_LOG_CORE=TRACE` |
| Filing a bug report | `TF_LOG=TRACE` with `TF_LOG_PATH`, then **redact before sharing** |
| A run in HCP Terraform needs more detail | Set `TF_LOG` as a workspace environment variable. See [HCP Terraform](08-hcp-terraform.md). |

Splitting core from provider keeps the output manageable. Most real problems on AWS are provider-side: a permission, a throttle, an eventual-consistency retry.

**Logs can contain secrets.** At `DEBUG` and `TRACE` a provider may log request and response bodies. Depending on the provider and resource, that can include resource attributes such as passwords, tokens returned by an API, and request details that help an attacker. Providers redact some known fields; do not rely on it. Treat a debug log like the state file:

- Never turn on `TF_LOG` permanently in a pipeline. CI logs are widely readable and long-lived.
- Write to a file with `TF_LOG_PATH`, restrict the file, and delete it when you are done.
- Keep log files out of Git: add `*.log` to `.gitignore`.
- Read and redact a log before attaching it to a ticket, a vendor support case, or a public issue.
- If a debug log with credentials has been exposed, rotate them. The [state exposure runbook](../../runbooks/terraform-state-exposure.md) applies.

More on pipeline hygiene: [securing Terraform on AWS](09-securing-terraform-on-aws.md).

## Worked examples

**1. A security review finds a hand-built S3 bucket holding audit logs. It must be managed by Terraform without being recreated.**
Add an `import` block with `to = aws_s3_bucket.audit` and the bucket name as `id`. Run `terraform plan -generate-config-out=generated.tf`. Tidy the generated block, and add `import` blocks for the bucket's companion resources (versioning, encryption, public access block), which are separate resources in the AWS provider. Plan until it shows only imports. Apply.

**2. Twelve IAM roles created by a script need importing.**
One `import` block with `for_each` over a map of role names, and a matching `resource "aws_iam_role"` with the same `for_each`. One plan shows all twelve. That is reviewable in a pull request, which twelve `terraform import` commands are not.

**3. After an import, the plan shows `1 to change`.**
The configuration does not match the real resource. Read the diff: usually a missing argument or a different default. Fix the configuration, not the resource, until the plan is empty. Applying first would silently alter production.

**4. An apply fails with `AccessDenied` and no indication of which action was denied.**
Set `TF_LOG_PROVIDER=DEBUG` and `TF_LOG_PATH`, run again, and search the log for the failing API call. Add that action to the deployment role, scoped to the resource. Unset the variables and delete the log. CloudTrail will show the same denied call if you would rather not enable logging.

**5. A script needs the database endpoint from another configuration's outputs.**
`terraform output -raw db_endpoint`. If the output were a password, the same command would print it in plaintext, so the script must not echo it and the pipeline must not log it.

## Pitfalls and exam traps

- `terraform import` (the command) does not generate configuration. The resource block must exist first.
- `-generate-config-out` is a flag of `terraform plan`, works with `import` blocks, and needs a file path that does not exist yet.
- Import does not change the real resource. It only writes state.
- An empty plan after import is the success test.
- Importing the same object to two addresses is an error you will not see until both try to change it.
- Many AWS settings are separate resources. Importing `aws_s3_bucket` does not import its versioning or encryption configuration.
- `terraform state list` lists addresses. `terraform state show` needs one address. `terraform show` takes no address.
- `terraform show` reads state or a saved plan file. `terraform output` reads only root module outputs.
- `(sensitive value)` in CLI output does not mean the value is protected in state or in `-json` output.
- `TF_LOG_PATH` alone logs nothing. A level variable must be set.
- `TRACE` is the most verbose level. `ERROR` is the least.
- `TF_LOG` covers core and providers. `TF_LOG_CORE` and `TF_LOG_PROVIDER` narrow it.
- Logging is set with environment variables. There is no `-verbose` or `-debug` flag.

## Self-check

1. Give three advantages of an `import` block over the `terraform import` command.
2. What must exist in your configuration before `terraform import aws_instance.web INSTANCE_ID` will work?
3. Which command drafts resource blocks for imported resources, and what restriction applies to the output path?
4. After importing a security group, `terraform plan` shows one change. What does that mean and what do you do?
5. Which command lists every address in state, and which shows the attributes of one of them?
6. A teammate says a database password is safe because `terraform output` shows `<sensitive>`. Why are they wrong?
7. Which environment variables give `DEBUG` logs from the AWS provider only, written to a file?
8. Why should debug logging not be left on in a CI pipeline?

<details>
<summary>Answers</summary>

1. It is reviewed in a plan before state is written; it can generate configuration with `-generate-config-out`; it handles many resources with `for_each`; it lives in code and so runs in pipelines and HCP Terraform as part of a normal apply.
2. A `resource "aws_instance" "web"` block. The command binds an object to an existing address and writes no configuration.
3. `terraform plan -generate-config-out=PATH`. The path must not already exist.
4. The configuration differs from the real resource. Edit the configuration until the plan shows no changes. Do not apply the change unless you intend to alter the real resource.
5. `terraform state list` and `terraform state show ADDRESS`.
6. The mask is display-only. `terraform output NAME`, `terraform output -json`, `terraform show -json`, and `terraform state pull` print it in plaintext, and it is stored in plaintext in state.
7. `TF_LOG_PROVIDER=DEBUG` and `TF_LOG_PATH=FILE`.
8. Debug and trace logs can include request and response data with credentials and secret attributes, and CI logs are broadly readable and retained.

</details>

## Further reading

- [Import existing resources](https://developer.hashicorp.com/terraform/language/import)
- [import block reference](https://developer.hashicorp.com/terraform/language/block/import)
- [Generating configuration](https://developer.hashicorp.com/terraform/language/import/generating-configuration)
- [terraform import command](https://developer.hashicorp.com/terraform/cli/commands/import)
- [terraform state commands](https://developer.hashicorp.com/terraform/cli/commands/state)
- [terraform show](https://developer.hashicorp.com/terraform/cli/commands/show), [terraform output](https://developer.hashicorp.com/terraform/cli/commands/output), [terraform console](https://developer.hashicorp.com/terraform/cli/commands/console)
- [Debugging Terraform](https://developer.hashicorp.com/terraform/internals/debugging)
