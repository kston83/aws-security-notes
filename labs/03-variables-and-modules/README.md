# Lab 03: Variables and modules

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4c, 4d, 4e, 4g, 5a–5d · **SCS-C03:** 6.2.1 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Terraform modules](../../teaching/terraform/05-modules.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md)

## Goal

Build a reusable `secure-bucket` module (bucket, public access block, versioning, default encryption, optional TLS-only policy) and call it three times from one `for_each`. Afterward you can type and validate inputs so an insecure value never reaches a plan, say which source of a variable value wins, and explain what a module hides from its caller.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) and [Lab 02](../02-remote-state/README.md) first.
- Read [Terraform configuration](../../teaching/terraform/04-configuration.md) (objectives 4c–4e, 4g) and [Terraform modules](../../teaching/terraform/05-modules.md).

| File | Holds |
|---|---|
| `variables.tf`, `terraform.tfvars` | Root inputs and the values this lab sets for them |
| `main.tf`, `outputs.tf` | `locals`, the `module` call, root outputs |
| `modules/secure-bucket/` | The **child module**: its own `variables.tf`, `main.tf`, `outputs.tf` |

## Steps

### 1. Read the module's inputs

A module's variables are its whole interface. `modules/secure-bucket/variables.tf` types every input, and uses `validation` blocks as guardrails:

```hcl
variable "classification" {
  type = string

  validation {
    condition     = contains(["public", "internal", "restricted"], var.classification)
    error_message = "classification must be one of: public, internal, restricted."
  }
}

variable "encryption" {
  type = object({
    algorithm  = optional(string, "AES256")
    bucket_key = optional(bool, false)
  })
  default = {}
}
```

`optional(TYPE, DEFAULT)` lets a caller leave an object attribute out. The root variable `buckets` in `variables.tf` is a `map(object({...}))` built the same way: only `classification` is required.

### 2. Initialize, and see why modules need it

```bash
terraform validate
```

```
Error: Module not installed

  on main.tf line 20:
  20: module "bucket" {

This module is not yet installed. Run "terraform init" to install all modules
required by this configuration.
```

```bash
terraform init          # [changes state] writes .terraform/ and .terraform.lock.hcl
```

```
Initializing modules...
- bucket in modules/secure-bucket
...
- Installing hashicorp/aws v6.72.0...
```

`init` records every `module` block in `.terraform/modules/modules.json`. A local module is referenced in place, not copied.

### 3. Evaluate expressions in the console

`terraform console` evaluates any expression against your variables, locals, and state. Pipe an expression in, or run it bare for an interactive prompt (`exit` to leave).

```bash
echo 'var.buckets["logs"]' | terraform console
```

```
{
  "classification" = "internal"
  "encryption" = {
    "algorithm" = "AES256"
    "bucket_key" = false
  }
  "enforce_tls" = true
  "versioning" = true
}
```

`terraform.tfvars` set only `classification` for `logs`. The `optional()` defaults filled in the rest. Try the functions and `for` expressions that `main.tf` and `outputs.tf` use:

| Expression | Result |
|---|---|
| `local.name_prefix` (built with `format("lab03-%s", var.environment)`) | `"lab03-dev"` |
| `lookup(local.retention_days, "public", 30)` | `30` (no `public` key, so the fallback) |
| `[for k, v in var.buckets : k if v.enforce_tls]` | `["logs", "reports"]` |
| `{ for k, v in var.buckets : k => upper(v.classification) }` | a map: `logs = "INTERNAL"`, `reports = "RESTRICTED"`, `scratch = "PUBLIC"` |
| `toset(["prod", "dev", "prod"])` | `toset(["dev", "prod"])` |
| `local.common_tags` (built with `merge`) | `Environment = "dev"`, `Lab = ...`, `Owner = "unassigned"` |

### 4. Set one variable four ways

`environment` defaults to `sandbox` and `terraform.tfvars` sets it to `dev`. `owner` is set nowhere, so it has its default.

```bash
echo 'var.owner' | TF_VAR_owner=secops terraform console              # "secops": an environment variable beats a default
echo 'var.environment' | TF_VAR_environment=test terraform console    # "dev": terraform.tfvars beats TF_VAR_
echo 'environment = "test"' > lab.auto.tfvars
echo 'var.environment' | terraform console                            # "test": *.auto.tfvars beats terraform.tfvars
echo 'var.environment' | terraform console -var environment=prod      # "prod": -var beats everything
rm lab.auto.tfvars
```

Lowest to highest: default, `TF_VAR_name`, `terraform.tfvars`, `*.auto.tfvars` (in file name order), then `-var` and `-var-file` in the order given. A `TF_VAR_` left exported in a pipeline loses silently to a committed `.tfvars` file, which is usually what you want and occasionally a surprise.

### 5. Read the module call, then apply

`main.tf` calls the module once per map entry:

```hcl
module "bucket" {
  source   = "./modules/secure-bucket"
  for_each = var.buckets

  name           = "${local.name_prefix}-${each.key}"
  classification = each.value.classification
  ...
  tags = merge(local.common_tags, {
    RetentionDays = tostring(lookup(local.retention_days, each.value.classification, 30))
  })
}
```

Inside the module, `main.tf` has a conditional resource (`count = var.enforce_tls ? 1 : 0` on the bucket policy) and a `dynamic "statement"` block that adds a deny-unencrypted-uploads statement only when `classification` is `restricted`.

```bash
terraform apply         # [changes state] answer yes
```

```
Plan: 14 to add, 0 to change, 0 to destroy.
...
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:

bucket_arns = {
  "logs" = "arn:aws:s3:::lab03-dev-logs"
  "reports" = "arn:aws:s3:::lab03-dev-reports"
  "scratch" = "arn:aws:s3:::lab03-dev-scratch"
}
restricted_buckets = tolist([
  "lab03-dev-reports",
])
tls_enforced = {
  "logs" = true
  "reports" = true
  "scratch" = false
}
```

Fourteen is 3 buckets × 4 resources, plus a policy for the two buckets with `enforce_tls` left on. The root can print these values only because the module declares `output` blocks and the root re-exports them (`mod.arn` in `outputs.tf`). `terraform state list` shows the addresses: `module.bucket["logs"].aws_s3_bucket.this`, `module.bucket["logs"].aws_s3_bucket_policy.this[0]`, and so on.

### 6. Add a second module call

Create `extra.tf`:

```hcl
module "archive" {
  source = "./modules/secure-bucket"

  name           = "${local.name_prefix}-archive"
  classification = "internal"
}
```

```bash
terraform plan          # Error: Module not installed ... on extra.tf line 1
terraform get           # [changes state] installs modules only; prints "- archive in modules/secure-bucket"
terraform plan          # Plan: 5 to add, 0 to change, 0 to destroy.
rm extra.tf
```

Every new `module` block needs `terraform get` or `terraform init`, even when the source is already on disk. `get` installs modules and nothing else. `init` also handles providers and the backend.

### 7. Know what `source` and `version` mean

| Source type | `source` looks like | Pinning a version |
|---|---|---|
| Local path | `./modules/secure-bucket` (must start `./` or `../`) | Not possible. The module is whatever is in the directory, so it versions with the calling repository. |
| Registry (public or private) | `NAMESPACE/NAME/PROVIDER`, or `HOSTNAME/NAMESPACE/NAME/PROVIDER` | `version = "~> 1.2"`. Only registry sources accept `version`. |
| Git | `git::https://example.com/ORG/REPO.git//modules/secure-bucket?ref=v1.2.0` | `?ref=` with a tag or commit hash. `//` separates the repository from a subdirectory. |

Pin anything you do not control. An unpinned registry module, or a git source with a branch as `ref`, lets someone else change what your next `init -upgrade` deploys. A commit hash is the strongest pin. This is the supply-chain half of SCS-C03 skill 6.2.1; see [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md).

## Verify

```bash
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab03-`)].Name' --output text
```

```
lab03-dev-logs	lab03-dev-reports	lab03-dev-scratch
```

```bash
aws s3api get-bucket-encryption --bucket lab03-dev-reports --query 'ServerSideEncryptionConfiguration.Rules[0]'
```

```
{
    "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
    },
    "BucketKeyEnabled": true
}
```

```bash
aws s3api get-bucket-versioning --bucket lab03-dev-scratch --query Status     # "Suspended"
aws s3api get-bucket-policy --bucket lab03-dev-reports --query Policy --output text
```

The policy has two statement IDs, `DenyInsecureTransport` and `DenyUnencryptedUploads`. The same command for `lab03-dev-logs` shows only the first (no `dynamic` statement), and for `lab03-dev-scratch` it fails with `NoSuchBucketPolicy` (`count` was 0).

```bash
aws s3api get-bucket-tagging --bucket lab03-dev-logs --query 'TagSet[?Key==`RetentionDays`||Key==`Classification`]' --output text
```

```
RetentionDays	90
Classification	internal
```

## Break it

**1. Fail a validation.** Two guardrails, one in the root and one in the module:

```bash
terraform plan -var environment=production
terraform plan -var 'buckets={logs={classification="secret"}}'
```

```
Error: Invalid value for variable
...
    │ var.environment is "production"

environment must be one of: sandbox, dev, test, prod.

This was checked by the validation rule at variables.tf:6,3-13.
```

```
Error: Invalid value for variable

  on main.tf line 25, in module "bucket":
  25:   classification = each.value.classification
    ├────────────────
    │ var.classification is "secret"

classification must be one of: public, internal, restricted.

This was checked by the validation rule at
modules/secure-bucket/variables.tf:20,3-13.
```

The second error points at the caller's line and the module's rule. Validation fails the plan before any API call, so nothing changed. Nothing to put back.

**2. Reach inside a module.** Create `scope.tf`, run `terraform validate`, then delete the file:

```hcl
output "leak" {
  value = module.bucket["logs"].aws_s3_bucket.this.arn
}
```

```
Error: Unsupported attribute
...
    │ module.bucket["logs"] is a object

This object does not have an attribute named "aws_s3_bucket".
```

A module call is an object made of the module's **outputs** and nothing else. Resources, locals, and variables inside it are out of scope for the caller, and the root's `local.name_prefix` is equally invisible inside the module. Values cross the boundary only through `variable` (in) and `output` (out).

**3. Version a local module.** Add `version = "1.0.0"` under `source` in `main.tf` and run `terraform init`:

```
Error: Invalid registry module source address
...
Failed to parse module registry address: can't use local directory
"./modules/secure-bucket" as a module registry address.

Terraform assumed that you intended a module registry source address because
you also set the argument "version", which applies only to registry modules.
```

Remove the line.

**4. Pass the wrong type.**

```bash
terraform plan -var 'buckets={logs={classification="internal",versioning="sometimes"}}'
terraform plan -var 'buckets=["logs"]'
terraform plan -var 'buckets={logs={versioning=true}}'
```

```
Unsuitable value for var.buckets set using -var="buckets=...": a bool is
required.
```

```
Unsuitable value for var.buckets set using -var="buckets=...": map of object
required.
```

```
Unsuitable value for var.buckets set using -var="buckets=...": element
"logs": attribute "classification" is required.
```

Type constraints are checked before validation rules. Terraform converts where it safely can (`"true"` becomes a bool) and rejects the rest. An attribute without `optional()` is required.

**5. Remove a key from the `for_each` map.** Delete the `scratch` block from `terraform.tfvars` and run `terraform plan`:

```
  # module.bucket["scratch"].aws_s3_bucket.this will be destroyed
...
Plan: 0 to add, 0 to change, 4 to destroy.

Changes to Outputs:
  ~ bucket_arns        = {
      - scratch = "arn:aws:s3:::lab03-dev-scratch"
        # (2 unchanged attributes hidden)
    }
```

The map key is the instance's identity. Removing a key destroys that instance and leaves the others alone, which is why `for_each` over a map is safer than `count` over a list, where removing an element renumbers everything after it. On a real bucket holding data, this plan is the last warning you get. Do not apply; put the `scratch` block back and confirm `terraform plan` reports `No changes`.

## Clean up

```bash
terraform destroy       # [changes state] Destroy complete! Resources: 14 destroyed.
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab03-`)].Name' --output text    # prints nothing
```

Delete `extra.tf`, `scope.tf`, and `lab.auto.tfvars` if any are left over.

## What differs on real AWS

- **Bucket policies are stored but not enforced by floci.** The lab proves the policy document is attached, not that a plain-HTTP request or an unencrypted upload is denied. On AWS, test both with a real request.
- **Bucket names are global.** `lab03-dev-logs` is almost certainly taken. Real modules add an account ID or random suffix to the name.
- **`aws:kms` with no key ID** uses the AWS managed key `aws/s3`. A restricted bucket normally names a customer managed key so that the key policy, not just IAM, controls who can decrypt. See [Lab 05](../05-kms-and-secrets/README.md) and the [KMS cheatsheet](../../cheatsheets/kms.md).
- **Account-level public access block.** The module sets the bucket-level one. AWS also has an account-level setting that should be on regardless. See the [S3 security cheatsheet](../../cheatsheets/s3-security.md).
- **`force_destroy = true`** is a lab convenience. Leave it out of a module that holds real data, so `destroy` fails on a non-empty bucket.
- **Module source.** A shared module would live in its own repository or a private registry and be called with a pinned `version` or `?ref=`, not a local path.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
