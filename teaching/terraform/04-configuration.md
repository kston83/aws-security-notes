# Terraform 4: Configuration

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4a–4h (largest domain) · **SCS-C03:** 6.2.1 · **Related:** [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [AWS provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md), [modules](05-modules.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [state exposure runbook](../../runbooks/terraform-state-exposure.md), [IaC control mappings](../../control-mappings/services/iac-terraform.md)

## Why this matters

Configuration is where security intent becomes code. A typed variable with a validation rule is a guardrail that fails before any API call. A reference instead of a hard-coded ARN is what keeps a key policy pointing at the right role. And every secret that passes through a configuration lands in the state file unless you use the features built to prevent it. This is also the domain with the most exam objectives.

## Mental model

**A configuration is a graph of values, not a script.** Terraform reads every `.tf` file in the directory as one **module** (the directory you run Terraform in is the **root module**), works out which block refers to which, and orders the work from those references. File order and block order mean nothing.

```
  inputs                   computation                    objects                      results
  variable "x" ──────────► locals, expressions, ────────► resource  (create, update,   ────► output "y"
  (tfvars, -var,           functions, for, count,         delete; recorded in state)        (CLI, state,
   TF_VAR_x, default)      for_each, dynamic        ┌───► data      (read only)              parent module)
                                                    │     ephemeral (read or generate; never stored)
        validation ▲             references ────────┘          ▲ preconditions, postconditions
                                                                 check blocks (warn only)
```

Three ideas carry most of the domain:

- **References create dependencies.** If block A mentions block B, Terraform handles B first. You rarely need to say so yourself.
- **Values have types, and some are unknown until apply.** The plan shows `(known after apply)` for attributes the provider computes, such as an ARN.
- **State stores what the configuration saw.** Any value assigned to a resource argument or an output is written to state in plain text unless it is ephemeral or write-only.

Terms used throughout: **HCL** is the HashiCorp Configuration Language. A **block** has a type, labels, and a body (`resource "aws_kms_key" "state" { … }`). An **argument** assigns a value inside a block. An **attribute** is a value a block exposes, including ones the provider computes. A **meta-argument** (`count`, `for_each`, `depends_on`, `provider`, `lifecycle`) is defined by Terraform itself and works on any resource.

## Objective 4a: Resource and data blocks

| | `resource` | `data` |
|---|---|---|
| **Purpose** | Manages an object: Terraform creates, updates, and deletes it | Reads an object or computes a value; never changes infrastructure |
| **Address** | `aws_s3_bucket.logs` | `data.aws_caller_identity.current` |
| **In state** | Yes, with every attribute | Yes, the last result read |
| **On destroy** | The real object is deleted | Nothing happens |
| **When read** | Refreshed during plan | During plan if its arguments are known; deferred to apply if they depend on something not yet created |

```hcl
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "state" {
  description             = "Terraform state key for ${data.aws_caller_identity.current.account_id}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
```

A **managed resource** is one declared in a `resource` block. Use a data source for things another team or configuration owns (a shared VPC, an organization ID, the current account and Region). Some data sources call no API at all: `aws_iam_policy_document` only renders JSON from HCL, which gets you syntax checking and references inside policies.

A resource type's first word is the provider's **local name** (`aws_`), which is how Terraform picks the provider. Providers are covered in [fundamentals](02-terraform-fundamentals.md).

## Objective 4b: References

A reference is a **named value**, and its prefix says what kind. A managed resource has no prefix (`aws_s3_bucket.logs.arn`). The others do: `data.` for a data source, `ephemeral.` for an ephemeral resource (see [4h](#objective-4h-sensitive-data-and-vault)), `var.` for an input variable, `local.` (singular, though declared in a `locals` block) for a local value, and `module.NAME.OUTPUT` for a child module's output. One instance of a resource that uses `count` or `for_each` is `aws_s3_bucket.logs[0]` or `aws_s3_bucket.logs["audit"]`. Inside such a block, `count.index`, `each.key`, and `each.value` give the current iteration. `self` is valid only in postconditions, provisioners, and connection blocks. The full table is in the [HCL cheatsheet](../../cheatsheets/terraform-hcl.md#references).

Inside a string, interpolate with `"${aws_s3_bucket.logs.arn}/*"`. A string that contains only a reference should be written without quotes and `${}`.

Cross-resource references are the point of the language. They keep values consistent and they define order: `bucket = aws_s3_bucket.logs.id` in a public access block resource both supplies the name and tells Terraform to create the bucket first.

## Objective 4c: Variables and outputs

**Input variables** parameterize a module. **Outputs** return values from it. **Locals** name an intermediate expression so it is written once.

```hcl
variable "environment" {
  type        = string
  description = "Deployment stage. Controls naming and deletion protection."
  default     = "dev"
}

output "state_key_arn" {
  value = aws_kms_key.state.arn
}
```

Variable arguments: `type`, `default`, `description`, `validation`, `sensitive`, `nullable`, and `ephemeral`. A variable with no `default` is required; with no value supplied, Terraform prompts for it interactively, or fails when run with `-input=false`.

**Precedence, highest first.** A higher rank overrides every rank below it:

| Rank | Source |
|---|---|
| 1 | `-var` and `-var-file` on the command line, in the order given (the last one wins) |
| 2 | `*.auto.tfvars` and `*.auto.tfvars.json`, in lexical order of file name |
| 3 | `terraform.tfvars.json` |
| 4 | `terraform.tfvars` |
| 5 | Environment variables named `TF_VAR_name` |
| 6 | The `default` in the variable block |

Only `terraform.tfvars`, `terraform.tfvars.json`, and `*.auto.tfvars*` load automatically. Any other file name needs `-var-file`. In HCP Terraform, workspace variables and variable sets override the tfvars files in the configuration; see [HCP Terraform](08-hcp-terraform.md#variables-and-variable-sets).

A value for a variable that is not declared is treated differently by source: an environment variable is ignored, a tfvars entry gives a warning, and `-var` gives an error.

**Outputs** do three jobs: print values after apply (`terraform output`), expose a child module's values to its caller, and publish values for other configurations to read from state. Output arguments: `value`, `description`, `sensitive`, `ephemeral` (child modules only), `depends_on`, and `precondition`.

**`sensitive = true`** on a variable or output redacts the value in plan and apply output as `(sensitive value)`. Sensitivity propagates: an expression built from a sensitive value is sensitive, and an output that includes one, in any module, must itself be marked `sensitive` or the plan fails. What it does not do is in [4h](#objective-4h-sensitive-data-and-vault).

## Objective 4d: Complex types

| Kind | Types | Notes |
|---|---|---|
| **Primitive** | `string`, `number`, `bool` | Terraform converts between them where it is unambiguous (`"true"` to `true`) |
| **Collection** (all elements the same type) | `list(T)`, `set(T)`, `map(T)` | A list is ordered and indexed from 0. A set is unordered with unique values and has no index. A map has string keys. |
| **Structural** (each element has its own type) | `object({ name = T, … })`, `tuple([T, …])` | An object is what you use for a record with named fields |
| **Special** | `any`, `null` | `any` is a placeholder for a type to be inferred, not a type that accepts mixed values. `null` means absent: the argument is treated as unset. |

```hcl
variable "buckets" {
  description = "Buckets to create, keyed by purpose."
  type = map(object({
    versioning    = optional(bool, true)   # optional attribute with a default
    expire_days   = optional(number)       # optional, null when omitted
    allowed_roles = list(string)
  }))
}
```

- **`optional(TYPE, DEFAULT)`** makes an object attribute optional. Without it, every attribute is required.
- Convert with `toset()`, `tolist()`, `tomap()`. `for_each` needs a map or a set of strings, so `toset(var.names)` is common.
- A set cannot be indexed (`var.s[0]` fails). Convert to a list or iterate.

Full constructor and conversion list: [HCL cheatsheet](../../cheatsheets/terraform-hcl.md).

## Objective 4e: Expressions and functions

**Repetition meta-arguments.** Both turn one block into many instances.

| | `count` | `for_each` |
|---|---|---|
| **Takes** | A whole number | A map or a set of strings |
| **Instance address** | `aws_iam_user.ops[0]` | `aws_iam_user.ops["alice"]` |
| **Iteration value** | `count.index` | `each.key`, `each.value` |
| **Removing a middle item** | Every later index shifts, so Terraform destroys and recreates those instances | Only that key's instance is destroyed |
| **Best for** | Zero-or-one switches: `count = var.enabled ? 1 : 0` | Anything with a natural name |

A block cannot use both. The number of instances and the `for_each` keys must be known at plan time, and a sensitive value cannot be used as the `for_each` argument.

**Expressions.** A **conditional** picks one of two values: `var.environment == "prod" ? 30 : 7`. A **`for` expression** transforms a collection: `[for r in var.roles : "arn:aws:iam::111122223333:role/${r}"]` gives a list, `{ for k, b in var.buckets : k => b.expire_days if b.expire_days != null }` gives a map, and the optional `if` filters. A **splat** collects one attribute from every `count` instance (`aws_iam_user.ops[*].arn`). It does not work directly on a `for_each` resource, which is a map of instances: use `values(aws_s3_bucket.this)[*].arn`.

A **`dynamic` block** generates repeated *nested* blocks, such as `ingress` rules inside one security group, where `for_each` on the resource cannot reach. It takes a `for_each` and a `content` block, and the iterator is named after the block (`ingress.key`, `ingress.value`). Use it sparingly: it hides what the resource looks like from a reviewer. Examples of every form are in the [HCL cheatsheet](../../cheatsheets/terraform-hcl.md#expressions).

**Functions** are built in. You cannot define your own in HCL, though providers can ship functions, called as `provider::NAME::FUNCTION()` (Terraform 1.8 and later). Try any expression in `terraform console`. Know the families (string, collection, encoding, filesystem, network, type conversion) and a few by heart: `merge`, `lookup`, `contains`, `length`, `join`, `jsonencode`, `file`, `templatefile`, `cidrsubnet`, `try` (first argument that evaluates without error), and `can` (true if the expression evaluates). The list with signatures is in the [HCL cheatsheet](../../cheatsheets/terraform-hcl.md).

## Objective 4f: Dependencies and lifecycle

**Implicit dependency:** created by a reference. Terraform builds a dependency graph from them, creates in dependency order, destroys in reverse, and runs unrelated branches in parallel (10 operations at a time by default **(verify)**; change with `-parallelism`).

**Explicit dependency:** `depends_on`, for the case where one object needs another but uses none of its attributes. The classic AWS case is IAM: a Lambda function sets `role = aws_iam_role.scanner.arn` (implicit dependency on the role) but must not run until the role's permissions exist, so it adds `depends_on = [aws_iam_role_policy_attachment.scanner_logs]`.

`depends_on` takes a list of resource or module addresses, not arbitrary expressions. It makes plans more conservative, since more values show as `(known after apply)`, so prefer a reference where one exists.

The **`lifecycle`** block changes how Terraform treats a resource:

| Argument | Effect | Security use |
|---|---|---|
| `create_before_destroy = true` | On replacement, create the new object before destroying the old one (the default is destroy first) | Replace a certificate or security group without an outage |
| `prevent_destroy = true` | Any plan that would destroy the resource fails with an error | Guard a log archive bucket or a KMS key. It does not help if the block itself is removed from the configuration. |
| `ignore_changes = [tags]` | Do not plan updates for the listed attributes; `all` ignores every attribute | Tolerate values another system manages. It also hides drift, so keep the list short. |
| `replace_triggered_by = [aws_kms_key.state.arn]` | Replace this resource when the referenced resource or attribute changes | Force re-creation when a dependency is rotated |
| `precondition`, `postcondition` | Custom conditions, covered next | Guardrails |

## Objective 4g: Custom conditions

Four mechanisms, from earliest to latest in a run. The first three stop the run. The last only warns.

| Mechanism | Declared in | Runs | On failure | Added in |
|---|---|---|---|---|
| **Variable validation** | `validation` block in a `variable` | Before the plan is built | Error | 0.13 |
| **Precondition** | `lifecycle` of a resource, data source, or ephemeral resource; or an `output` | Before that object is created, read, or evaluated | Error; the object is not touched | 1.2 |
| **Postcondition** | `lifecycle` of a resource, data source, or ephemeral resource | After the object is planned, applied, or read | Error; dependents do not proceed, but nothing already done is undone | 1.2 |
| **`check` block** | Top level of a module | Last step of every plan and apply | **Warning only**; the run continues | 1.5 |

```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

data "aws_kms_key" "state" {
  key_id = var.state_key_alias

  lifecycle {
    postcondition {
      condition     = self.key_state == "Enabled"
      error_message = "The state KMS key must be enabled."
    }
  }
}

check "ebs_encryption_default" {
  data "aws_ebs_encryption_by_default" "current" {}   # scoped: visible only inside this check

  assert {
    condition     = data.aws_ebs_encryption_by_default.current.enabled
    error_message = "EBS encryption by default is off in this Region."
  }
}
```

- Each needs a `condition` that evaluates to `true` or `false` and an `error_message`. Wrap an expression that might error in `can()`, for example `can(regex("^arn:aws:kms:", var.kms_key_arn))`.
- A **precondition** states an assumption ("the AMI must be encrypted"). A **postcondition** states a guarantee and can use `self`.
- A variable validation can refer to other variables and data sources since Terraform 1.9. Before that it could refer only to the variable itself.
- A `check` block must have at least one `assert` and may contain a nested (scoped) data source. If that data source fails to read, that is also a warning, so a check is safe for "is the endpoint healthy" tests that must not block a deploy. HCP Terraform can run checks continuously as health assessments.
- These are *in-configuration* guardrails. Policy as code that authors cannot edit (Sentinel, OPA) and `terraform test` are separate layers: see [HCP Terraform](08-hcp-terraform.md) and [securing Terraform on AWS](09-securing-terraform-on-aws.md).

## Objective 4h: Sensitive data and Vault

**The core fact: `sensitive` hides, it does not protect.** Terraform stores sensitive values in the state file and in saved plan files in plain text. `terraform output NAME`, `terraform output -json`, `terraform output -raw NAME`, and `terraform show -json` print them. Anyone who can read state can read every secret that passed through a resource argument. Providers also mark some attributes sensitive themselves (a database password, for example) with the same limits.

Three layers, weakest to strongest:

| Mechanism | Hidden in CLI output | Kept out of state and plan | Requires |
|---|---|---|---|
| `sensitive = true` (variable, output) | Yes | **No** | Any current version |
| `ephemeral = true` (variable, child module output) | Add `sensitive` as well to redact it | Yes | 1.10 |
| `ephemeral` resource block | Never shown; it is not in the plan | Yes | 1.10, and a provider that offers the ephemeral resource |
| Write-only argument on a managed resource | Never shown; it is not in the plan | Yes | 1.11, and a provider that offers the argument |

**Ephemeral values** exist only during one Terraform operation. An **ephemeral resource** is read or generated fresh on every plan and apply and never recorded. Terraform allows ephemeral values only where they cannot leak into state: `locals`, ephemeral variables, ephemeral child module outputs, other `ephemeral` blocks, `provider` blocks, provisioner and connection blocks, and write-only arguments. Anywhere else is a plan-time error. Root module outputs cannot be ephemeral.

**Write-only arguments** accept a value, hand it to the provider, and discard it. By convention they end in `_wo` and pair with a `_wo_version` argument. Because Terraform keeps nothing to compare, it cannot see that the value changed: increment the version number to make the provider send it again.

```hcl
ephemeral "random_password" "db" {
  length = 32
}

resource "aws_secretsmanager_secret" "db" {
  name       = "prod/db/master"
  kms_key_id = aws_kms_key.state.arn
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id                = aws_secretsmanager_secret.db.id
  secret_string_wo         = ephemeral.random_password.db.result   # never written to state or plan
  secret_string_wo_version = 1                                     # bump to rotate
}
```

To use the secret later in the same or another configuration, read it with `ephemeral "aws_secretsmanager_secret_version"`. Compare the older pattern: a `random_password` *resource* with `secret_string`, or a `data "aws_secretsmanager_secret_version"`, each put the secret in state.

**Practices.** Never hard-code secrets in `.tf` files or commit `*.tfvars` files that hold them: version control keeps them forever. Supply secrets at run time through `TF_VAR_name`, HCP Terraform sensitive variables, or a secrets manager. Prefer ephemeral resources and write-only arguments wherever the provider has them, since nothing else keeps a value out of state. Treat state and saved plans as secret anyway, because they hold whatever slipped through (see [state management](06-state-management.md)). Mark outputs and variables `sensitive` as well, to keep values out of CI logs and terminals, and do not unwrap them with `nonsensitive()` unless the value truly is not secret.

**Vault.** HashiCorp Vault is a secrets manager that issues **dynamic secrets**: short-lived credentials generated on request and revoked when their lease ends. With Terraform it is used two ways: the Vault provider *configures* Vault (mounts, policies, roles), and it *reads* secrets for other providers to use, for example short-lived AWS credentials from Vault's AWS secrets engine in place of long-lived access keys.

- The Vault provider documentation warns that secrets read or written through its resources and data sources are persisted in state and plan files. Reading through the provider's ephemeral resources avoids that (the provider has one for KV version 2 secrets, among others **(verify)**).
- Authenticate the provider through the environment (`VAULT_ADDR`, `VAULT_TOKEN`) or a platform auth method, not arguments in configuration.
- The provider requests a short-lived child token for each run (20 minutes by default **(verify)**), so credentials it issues expire soon after the run.
- Dynamic secrets limit the damage if state leaks: what is in state has already expired.

On AWS the same roles are played by Secrets Manager and short-lived role credentials; see [data protection](../05-data-protection.md#secrets). If a secret did reach state or version control, follow the [state exposure runbook](../../runbooks/terraform-state-exposure.md). Hands-on: [lab 05](../../labs/05-kms-and-secrets/README.md).

## Worked examples

**1. One set of hardened buckets from a map, with a TLS-only policy on each.**
`for_each = var.buckets` (the type in [4d](#objective-4d-complex-types)) keys every bucket by purpose, so removing `"audit"` later touches only that bucket. An `aws_iam_policy_document` data source then sets `for_each = aws_s3_bucket.this`, chaining from one resource to the next, and denies `s3:*` on `[each.value.arn, "${each.value.arn}/*"]` when `aws:SecureTransport` is `false`. An `aws_s3_bucket_policy` with the same `for_each` attaches `data.aws_iam_policy_document.tls_only[each.key].json` to each bucket. Every reference is resolved per key, so no ARN is typed by hand.

**2. Production must use a customer managed KMS key; other stages may fall back to the default.**
A variable `kms_key_arn` with `default = null`, and a precondition on the encryption resource: `condition = var.environment != "prod" || var.kms_key_arn != null`. The plan fails with your error message before any bucket is changed. A `check` block would be wrong here because it only warns.

**3. A CI pipeline passes a database password to Terraform, and the security team finds it in the state bucket.**
`sensitive = true` was set, which only redacted the logs. Fix: declare the variable `ephemeral = true` and `sensitive = true`, assign it to the resource's write-only argument (`password_wo` on `aws_db_instance`) with a version number, then rotate the exposed password. Better still, generate it with an ephemeral resource so no pipeline handles it.

**4. Removing one name from a list of IAM users plans to destroy and recreate three others.**
The resource used `count = length(var.users)`, and every index after the removed one shifted. Switch to `for_each = toset(var.users)` so each instance is addressed by name. Moving existing instances to the new addresses without recreating them takes `moved` blocks; see [state management](06-state-management.md#refactoring-without-destroying).

## Pitfalls and exam traps

- `sensitive` does not encrypt anything and does not keep a value out of state. Only ephemeral values and write-only arguments do that.
- `-var` and `-var-file` beat everything. Environment variables (`TF_VAR_`) beat only the default. `terraform.tfvars` loses to `*.auto.tfvars`.
- A file named `prod.tfvars` is not loaded unless you pass `-var-file=prod.tfvars`.
- Declared with plural `locals`, referenced with singular `local.name`. Data sources are prefixed `data.`; managed resources have no prefix.
- `count` and `for_each` cannot be combined on one block, and `for_each` rejects a list: wrap it in `toset()`.
- A `check` block never fails a run. Preconditions, postconditions, and variable validation do.
- A failed postcondition does not roll back the resource that was just created.
- `prevent_destroy` blocks `terraform destroy` too, and it is no defense against deleting the resource block along with it.
- `ignore_changes` hides drift on the listed attributes, including drift an attacker caused.
- `depends_on` is a last resort. If you can reference an attribute, do that.
- A write-only value does not update when you change it. Change the `_wo_version`.
- Ephemeral resources and write-only arguments are newer than much third-party study material. The 004 exam tests Terraform 1.12, which has both.

## Self-check

1. What is the difference between a `resource` block and a `data` block when you run `terraform destroy`?
2. A variable is set in `terraform.tfvars`, in `prod.auto.tfvars`, as `TF_VAR_region`, and with `-var`. Which value wins, and which is weakest?
3. An output is marked `sensitive = true`. Name two places the value can still be read in plain text.
4. Why is `for_each` usually safer than `count` for a list of named IAM users?
5. When do you need `depends_on`? Give an AWS example.
6. Which custom condition would you use to (a) reject an invalid input before planning, (b) block an apply if a looked-up KMS key is disabled, (c) report a failed health probe without stopping the run?
7. How do you rotate a value passed through a write-only argument?
8. Why do dynamic secrets from Vault reduce the impact of a leaked state file?

<details>
<summary>Answers</summary>

1. The resource's real object is deleted. A data source is only read, so nothing in the infrastructure changes; its entry simply leaves state.
2. `-var` wins. The environment variable is weakest of the four (only the variable's `default` is lower). Between the files, `prod.auto.tfvars` overrides `terraform.tfvars`.
3. The state file and any saved plan file. Also `terraform output NAME`, `terraform output -json`, `terraform output -raw NAME`, and `terraform show -json`.
4. `for_each` addresses each instance by key, so removing one user affects only that instance. With `count`, later indexes shift and Terraform plans to destroy and recreate them.
5. When one object needs another to exist but references none of its attributes. Example: a Lambda function or instance that needs an IAM role policy attachment in place before it starts, while only referencing the role.
6. (a) Variable validation. (b) A postcondition on the `aws_kms_key` data source (or a precondition on the resource that uses the key). (c) A `check` block.
7. Change the value and increment the paired `_wo_version` argument. Terraform stores nothing to compare, so the version change is what triggers the update.
8. They are short-lived and revoked when their lease ends, so credentials found in an old state file have usually expired. Combined with ephemeral resources, they need not reach state at all.

</details>

## Further reading

- [Terraform language: resources](https://developer.hashicorp.com/terraform/language/resources) and [data sources](https://developer.hashicorp.com/terraform/language/data-sources)
- [Input variables](https://developer.hashicorp.com/terraform/language/values/variables) (precedence) and [type constraints](https://developer.hashicorp.com/terraform/language/expressions/type-constraints)
- [Functions](https://developer.hashicorp.com/terraform/language/functions)
- [Validate your configuration](https://developer.hashicorp.com/terraform/language/validate) and the [`check` block reference](https://developer.hashicorp.com/terraform/language/block/check)
- [Manage sensitive data](https://developer.hashicorp.com/terraform/language/manage-sensitive-data), the [`ephemeral` block reference](https://developer.hashicorp.com/terraform/language/block/ephemeral), and [write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)
- [Vault provider documentation](https://registry.terraform.io/providers/hashicorp/vault/latest/docs)
- [Terraform Associate (004) exam review](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004)
