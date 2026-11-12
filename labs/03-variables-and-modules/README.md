# Lab 03: Variables and modules

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4c, 4d, 4e, 4g, 5a–5d · **SCS-C03:** 6.2.1 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Terraform modules](../../teaching/terraform/05-modules.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md)

## Goal

Build a reusable `secure-bucket` module (bucket, public access block, versioning, default encryption, optional TLS-only policy) and call it three times from one `for_each`. Afterward you can type and validate inputs so an insecure value never reaches a plan, say which source of a variable value wins, and explain what a module hides from its caller.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) and [Lab 02](../02-remote-state/README.md) first. Read [Terraform configuration](../../teaching/terraform/04-configuration.md) (4c–4e, 4g) and [Terraform modules](../../teaching/terraform/05-modules.md).
- Root inputs are in `variables.tf` with values in `terraform.tfvars`; `main.tf` and `outputs.tf` hold `locals`, the `module` call, and root outputs. The **child module** in `modules/secure-bucket/` has its own `variables.tf`, `main.tf`, and `outputs.tf`.

## Steps

### 1. Read the module's inputs

A module's variables are its whole interface. `modules/secure-bucket/variables.tf` types every input and uses `validation` blocks as guardrails:

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

`optional(TYPE, DEFAULT)` lets a caller leave an attribute out. The root variable `buckets` is a `map(object({...}))` built the same way: only `classification` is required.

### 2. Initialize, and see why modules need it

```bash
terraform validate
```

```
Error: Module not installed
...
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

`terraform console` evaluates expressions against your variables, locals, and state. Pipe one in, or run it bare for a prompt (`exit` to leave).

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

`terraform.tfvars` set only `classification` for `logs`; `optional()` defaults filled in the rest. Try the expressions `main.tf` and `outputs.tf` use:

| Expression | Result |
|---|---|
| `local.name_prefix` (built with `format("lab03-%s", var.environment)`) | `"lab03-dev"` |
| `lookup(local.retention_days, "public", 30)` | `30` (no `public` key, so the fallback) |
| `[for k, v in var.buckets : k if v.enforce_tls]` | `["logs", "reports"]` |
| `{ for k, v in var.buckets : k => upper(v.classification) }` | a map: `logs = "INTERNAL"`, `reports = "RESTRICTED"`, `scratch = "PUBLIC"` |
| `toset(["prod", "dev", "prod"])` | `toset(["dev", "prod"])` |
| `local.common_tags` (built with `merge`) | `Environment = "dev"`, `Lab = ...`, `Owner = "unassigned"` |

### 4. Set one variable four ways

`environment` defaults to `sandbox`; `terraform.tfvars` sets it to `dev`. `owner` is set nowhere.

```bash
echo 'var.owner' | TF_VAR_owner=secops terraform console              # "secops": an environment variable beats a default
echo 'var.environment' | TF_VAR_environment=test terraform console    # "dev": terraform.tfvars beats TF_VAR_
echo 'environment = "test"' > lab.auto.tfvars
echo 'var.environment' | terraform console                            # "test": *.auto.tfvars beats terraform.tfvars
echo 'var.environment' | terraform console -var environment=prod      # "prod": -var beats everything
rm lab.auto.tfvars
```

Lowest to highest: default, `TF_VAR_name`, `terraform.tfvars`, `*.auto.tfvars` (file name order), then `-var` and `-var-file` in the order given. A `TF_VAR_` exported in a pipeline loses silently to a committed `.tfvars` file.

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

Inside, the module's `main.tf` has a conditional resource (`count = var.enforce_tls ? 1 : 0` on the bucket policy) and a `dynamic "statement"` block that adds a deny-unencrypted-uploads statement only for `restricted` buckets.

```bash
terraform apply         # [changes state] answer yes
```

```
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.
...
bucket_arns = {
  "logs" = "arn:aws:s3:::lab03-dev-logs"
...
restricted_buckets = tolist([
  "lab03-dev-reports",
])
tls_enforced = {
  "logs" = true
  "reports" = true
  "scratch" = false
}
```

Fourteen is 3 buckets × 4 resources, plus a policy for the two buckets with `enforce_tls` on. The root can print these only because the module declares `output` blocks and the root re-exports them (`mod.arn` in `outputs.tf`). `terraform state list` shows addresses such as `module.bucket["logs"].aws_s3_bucket.this` and `module.bucket["logs"].aws_s3_bucket_policy.this[0]`.

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

Every new `module` block needs `terraform get` or `terraform init`, even when the source is already on disk. `get` installs modules only; `init` also handles providers and the backend.

### 7. Know what `source` and `version` mean

| Source type | `source` looks like | Pinning a version |
|---|---|---|
| Local path | `./modules/secure-bucket` (must start `./` or `../`) | Not possible: it versions with the calling repository |
| Registry (public or private) | `NAMESPACE/NAME/PROVIDER`, or `HOSTNAME/NAMESPACE/NAME/PROVIDER` | `version = "~> 1.2"`. Only registry sources accept `version`. |
| Git | `git::https://example.com/ORG/REPO.git//modules/secure-bucket?ref=v1.2.0` | `?ref=` with a tag or commit hash. `//` separates the repository from a subdirectory. |

Pin anything you do not control. An unpinned registry module, or a Git `ref` naming a branch, lets someone else change what your next `init -upgrade` deploys. A commit hash is the strongest pin. This is the supply-chain half of SCS-C03 skill 6.2.1; see [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md).

## Verify

```bash
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab03-`)].Name' --output text
aws s3api get-bucket-encryption --bucket lab03-dev-reports --query 'ServerSideEncryptionConfiguration.Rules[0]'
```

```
lab03-dev-logs	lab03-dev-reports	lab03-dev-scratch
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

The policy has two statement IDs, `DenyInsecureTransport` and `DenyUnencryptedUploads`. For `lab03-dev-logs` it has only the first (no `dynamic` statement); for `lab03-dev-scratch` the command fails with `NoSuchBucketPolicy` (`count` was 0).

```bash
aws s3api get-bucket-tagging --bucket lab03-dev-logs --query 'TagSet[?Key==`RetentionDays`||Key==`Classification`]' --output text
```

```
RetentionDays	90
Classification	internal
```

## Break it

**1. Fail a validation**, once in the root and once in the module:

```bash
terraform plan -var environment=production
terraform plan -var 'buckets={logs={classification="secret"}}'
```

```
Error: Invalid value for variable
...
    │ var.environment is "production"

environment must be one of: sandbox, dev, test, prod.
...
Error: Invalid value for variable

  on main.tf line 25, in module "bucket":
  25:   classification = each.value.classification
    ├────────────────
    │ var.classification is "secret"

classification must be one of: public, internal, restricted.

This was checked by the validation rule at
modules/secure-bucket/variables.tf:20,3-13.
```

The second error points at the caller's line and the module's rule. Validation fails the plan before any API call; nothing to put back.

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

A module call is an object made of the module's **outputs** and nothing else. Its resources, locals, and variables are out of the caller's scope, and the root's `local.name_prefix` is equally invisible inside the module. Values cross only through `variable` (in) and `output` (out).

**3. Version a local module.** Add `version = "1.0.0"` under `source` in `main.tf` and run `terraform init`:

```
Error: Invalid registry module source address
...
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
...
Unsuitable value for var.buckets set using -var="buckets=...": map of object
required.
...
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

The map key is the instance's identity: removing it destroys that instance and leaves the others alone. With `count` over a list, removing an element renumbers everything after it. On a bucket holding data this plan is your last warning. Do not apply; put `scratch` back and confirm `terraform plan` reports `No changes`.

## Clean up

```bash
terraform destroy       # [changes state] Destroy complete! Resources: 14 destroyed.
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab03-`)].Name' --output text    # prints nothing
```

Delete `extra.tf`, `scope.tf`, and `lab.auto.tfvars` if any are left over.

## What differs on real AWS

- **floci stores bucket policies but does not enforce them.** The lab proves the policy is attached, not that a plain-HTTP request or an unencrypted upload is denied. On AWS, test both with a real request.
- **Bucket names are global.** `lab03-dev-logs` is almost certainly taken. Real modules add an account ID or random suffix.
- **`aws:kms` with no key ID** uses the AWS managed key `aws/s3`. A restricted bucket normally names a customer managed key so the key policy, not just IAM, controls who can decrypt. See [Lab 05](../05-kms-and-secrets/README.md) and the [KMS cheatsheet](../../cheatsheets/kms.md).
- **Account-level public access block.** The module sets the bucket-level one; the account-level setting should be on regardless. See the [S3 security cheatsheet](../../cheatsheets/s3-security.md).
- **`force_destroy = true`** is a lab convenience. Leave it out of a module that holds real data, so `destroy` fails on a non-empty bucket.
- **Module source.** A shared module lives in its own repository or a private registry, called with a pinned `version` or `?ref=`, not a local path.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
