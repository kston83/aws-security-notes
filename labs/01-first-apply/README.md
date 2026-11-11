# Lab 01: First apply

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 3a–3g · **SCS-C03:** 6.2.1 · **Time:** 30 minutes · **Related:** [Core workflow](../../teaching/terraform/03-core-workflow.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [Terraform CLI cheatsheet](../../cheatsheets/terraform-cli.md), [S3 security cheatsheet](../../cheatsheets/s3-security.md), [KMS cheatsheet](../../cheatsheets/kms.md)

## Goal

Run the whole core workflow once, by hand, on a resource worth securing: an S3 bucket with public access blocked, versioning on, and default encryption under a KMS key that the lab creates with rotation enabled. Afterward you can format, initialize, validate, plan, apply, change, and destroy a configuration, and read a plan well enough to tell a harmless in-place update from a replacement that deletes data.

## Before you start

- floci is running and the AWS CLI points at it (`AWS_ENDPOINT_URL` exported). See [labs/README.md](../README.md#start-the-emulator).
- Read [Core workflow](../../teaching/terraform/03-core-workflow.md) first. Keep the [Terraform CLI cheatsheet](../../cheatsheets/terraform-cli.md) open.
- Run every command from this folder, in a Bash-style shell. The KMS key ID differs on every run.
- `providers.tf` holds the version constraints and the lab-only provider settings. `main.tf` holds two variables, the key and its alias, the bucket, and its three hardening resources. `outputs.tf` exposes the bucket name and key ID. Read all three before you run anything.

## Steps

### 1. Check formatting (3g)

```bash
terraform fmt -check     # prints nothing; exit code 0 means every file is already in canonical style
```

`fmt` needs no providers and no network, so it works before `init`. Without `-check` it rewrites files in place.

### 2. Initialize the working directory (3b)

```bash
terraform init           # [changes state] downloads the provider, writes the lock file
```

```
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.72.0...
- Installed hashicorp/aws v6.72.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. ...
Terraform has been successfully initialized!
```

`ls -a` shows what `init` created:

| Item | What it is | Commit it? |
|---|---|---|
| `.terraform/` | Local cache: the provider binary under `.terraform/providers/`, and later module copies and backend settings | No. `init` rebuilds it. |
| `.terraform.lock.hcl` | **Dependency lock file**: the exact provider version chosen (`6.72.0` here) and its checksums, so every later `init` picks the same build | Yes in real work. This repo ignores it so each reader gets a current provider. |

### 3. Validate (3c)

```bash
terraform validate       # Success! The configuration is valid.
```

`validate` checks syntax, references, and argument names and types against the provider schema. It makes no API calls, so it cannot tell you a bucket name is taken or a permission is missing.

### 4. Plan, save the plan, and read it (3d)

```bash
terraform plan -out=lab01.tfplan
```

```
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create
...
  # aws_s3_bucket.this will be created
  + resource "aws_s3_bucket" "this" {
      + arn                         = (known after apply)
      + bucket                      = "lab01-first-apply"
...
  # aws_s3_bucket_server_side_encryption_configuration.this will be created
...
          + apply_server_side_encryption_by_default {
              + kms_master_key_id = (known after apply)
              + sse_algorithm     = "aws:kms"
            }
...
Plan: 6 to add, 0 to change, 0 to destroy.
...
Saved the plan to: lab01.tfplan
```

| In the plan | Meaning |
|---|---|
| `+` | Create |
| `~` | Update in place (step 7) |
| `-/+` | Destroy, then create a replacement (step 8) |
| `-` | Destroy (step 9) |
| `(known after apply)` | **Computed value**: AWS decides it during the apply. `kms_master_key_id` is computed because the key does not exist yet, which is also how Terraform knows to create the key first. |
| `Plan: 6 to add, 0 to change, 0 to destroy.` | The line to read first, every time |

`-out` writes a **saved plan**: a binary file holding the exact actions and the variable values used. Read it again with `terraform show lab01.tfplan`. A saved plan can contain secrets, so treat it like state.

### 5. Apply the saved plan (3e)

```bash
terraform apply lab01.tfplan     # [changes state] no prompt: the saved plan is the approval
```

```
aws_kms_key.bucket: Creating...
aws_s3_bucket.this: Creating...
aws_s3_bucket.this: Creation complete after 0s [id=lab01-first-apply]
...
aws_kms_key.bucket: Creation complete after 8s [id=b6437afd-158c-4538-a057-061ece66b102]
aws_s3_bucket_server_side_encryption_configuration.this: Creating...
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "lab01-first-apply"
kms_key_id = "b6437afd-158c-4538-a057-061ece66b102"
```

The key and the bucket start together because neither refers to the other. The encryption configuration waits for the key.

### 6. Inspect what Terraform recorded

```bash
terraform state list
terraform state show aws_s3_bucket_public_access_block.this     # one resource, every attribute
terraform plan
```

```
aws_kms_alias.bucket
aws_kms_key.bucket
aws_s3_bucket.this
aws_s3_bucket_public_access_block.this
aws_s3_bucket_server_side_encryption_configuration.this
aws_s3_bucket_versioning.this
...
No changes. Your infrastructure matches the configuration.
```

`apply` wrote `terraform.tfstate` in this folder. `terraform show` prints all of it in readable form. A second `plan` that reports no changes is what a converged configuration looks like. [Lab 02](../02-remote-state/README.md) moves the state file somewhere safer.

### 7. A change that updates in place

`main.tf` puts `var.data_classification` (default `internal`) in the bucket's `Classification` tag. Override it for one run:

```bash
terraform plan -var data_classification=confidential -out=lab01.tfplan
terraform apply lab01.tfplan     # [changes state]
```

```
  # aws_s3_bucket.this will be updated in-place
  ~ resource "aws_s3_bucket" "this" {
        id                          = "lab01-first-apply"
      ~ tags                        = {
          ~ "Classification" = "internal" -> "confidential"
...
Plan: 0 to add, 1 to change, 0 to destroy.
...
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

`~` means the bucket stays and one API call changes the tag. Now run a plain `terraform plan`: it offers `"confidential" -> "internal"`. A `-var` value lasts for one command, and the configuration is the source of truth. Do not apply that plan.

### 8. A change that forces replacement

A bucket cannot be renamed. Plan it, and do not apply:

```bash
terraform plan -var data_classification=confidential -var bucket_name=lab01-first-apply-renamed
```

```
-/+ destroy and then create replacement
...
  # aws_s3_bucket.this must be replaced
-/+ resource "aws_s3_bucket" "this" {
      ~ bucket                      = "lab01-first-apply" -> "lab01-first-apply-renamed" # forces replacement
...
  # aws_s3_bucket_public_access_block.this must be replaced
-/+ resource "aws_s3_bucket_public_access_block" "this" {
      ~ bucket                  = "lab01-first-apply" -> (known after apply) # forces replacement
...
Plan: 4 to add, 0 to change, 4 to destroy.
```

`# forces replacement` marks the argument responsible. The replacement spreads: the three hardening resources refer to the bucket's `id`, so they are replaced too. Applied for real, this deletes the bucket (the apply fails at that point if the bucket still holds objects), and between destroy and create there is no bucket at all. A non-zero `to destroy` count is the cue to stop and read.

### 9. Preview the destroy (3f)

```bash
terraform plan -destroy          # Plan: 0 to add, 0 to change, 6 to destroy.
```

Every resource is listed with `-` and `will be destroyed`. Nothing is removed yet. The real destroy is in [Clean up](#clean-up), after the exercises.

## Verify

These read the emulator directly, so they hold whatever Terraform's state says.

```bash
aws s3api get-public-access-block --bucket lab01-first-apply
aws s3api get-bucket-encryption --bucket lab01-first-apply
aws s3api get-bucket-versioning --bucket lab01-first-apply
aws kms get-key-rotation-status --key-id "$(terraform output -raw kms_key_id)"
```

```
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
...
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms",
                    "KMSMasterKeyID": "arn:aws:kms:us-east-1:000000000000:key/b6437afd-158c-4538-a057-061ece66b102"
                },
                "BucketKeyEnabled": true
...
{
    "Status": "Enabled"
}
{
    "KeyRotationEnabled": true
}
```

`get-key-rotation-status` takes a key ID or key ARN, not an alias, which is why the command reads the ID from the Terraform output.

## Break it

### 1. Misformatted code, caught by `fmt -check`

```bash
printf 'locals {\nscratch   =    "badly formatted"\n}\n' > scratch.tf
terraform fmt -check -diff ; echo "exit code: $?"
terraform validate
rm scratch.tf
```

```
scratch.tf
...
-scratch   =    "badly formatted"
+  scratch = "badly formatted"
 }
exit code: 3
Success! The configuration is valid.
```

Exit code 3 is what a CI job fails on. `validate` still passes: style and validity are separate checks.

### 2. Errors caught by `validate`

```bash
printf 'resource "aws_s3_bucket" "unclosed" {\n' > broken.tf
terraform validate
printf 'output "oops" {\n  value = aws_s3_bucket.missing.arn\n}\n' > broken.tf
terraform validate
rm broken.tf
```

```
Error: Unclosed configuration block

  on broken.tf line 1, in resource "aws_s3_bucket" "unclosed":
...
Error: Reference to undeclared resource

  on broken.tf line 2, in output "oops":
   2:   value = aws_s3_bucket.missing.arn

A managed resource "aws_s3_bucket" "missing" has not been declared in the
root module.
```

The first is a syntax error, the second a reference error in well-formed code. Both are found without an API call.

### 3. A saved plan that has gone stale

```bash
terraform plan -out=stale.tfplan
terraform apply -auto-approve -var data_classification=restricted     # [changes state]
terraform apply stale.tfplan
rm stale.tfplan
```

```
Error: Saved plan is stale

The given plan file can no longer be applied because the state was changed by
another operation after the plan was created.
```

A saved plan is tied to the state it was computed from. Any apply in between invalidates it, which stops a pipeline from applying a plan that was reviewed against yesterday's infrastructure. Fix: plan again.

### 4. A missing `endpoints` entry

Remove the `kms` line from the `endpoints` block, then plan with `AWS_ENDPOINT_URL` hidden from Terraform:

```bash
sed -i.bak '/kms = var.floci_endpoint/d' providers.tf
env -u AWS_ENDPOINT_URL terraform plan
terraform plan                           # with the variable visible again: no error
mv providers.tf.bak providers.tf
```

```
Terraform planned the following actions, but then encountered a problem:
...
Error: reading KMS Key (b6437afd-158c-4538-a057-061ece66b102): ... operation error KMS: DescribeKey, https response error StatusCode: 400, RequestID: ..., api error UnrecognizedClientException: The security token included in the request is invalid.
```

In the first plan the S3 calls still went to floci, but the KMS call went to real AWS, which rejected the fake credentials. (This needs internet access. Offline you get a connection error instead.) Each service has its own endpoint, and the fake keys are the safety net when one is missed.

The second plan succeeds because the AWS provider also honors `AWS_ENDPOINT_URL` and uses it for any service with no `endpoints` entry. The explicit entries keep the lab pointed at floci in a shell where that variable is not set.

### 5. Deleting `.terraform/`

```bash
rm -rf .terraform
terraform plan
terraform init
```

```
Error: Required plugins are not installed

The installed provider plugins are not consistent with the packages selected
in the dependency lock file:
  - registry.terraform.io/hashicorp/aws: there is no package for registry.terraform.io/hashicorp/aws 6.72.0 cached in .terraform/providers
...
- Reusing version 6.72.0 of hashicorp/aws from the dependency lock file
```

Nothing is lost: `.terraform/` is a cache, and state lives outside it. `init` reinstalls the version pinned in the lock file (`Reusing version`), not whatever is newest. Every fresh clone and every CI runner starts in this situation.

## Clean up

```bash
terraform destroy                # [changes state] type yes at the prompt
rm -f lab01.tfplan
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab01-`)].Name'     # []
```

```
Plan: 0 to add, 0 to change, 6 to destroy.
...
Destroy complete! Resources: 6 destroyed.
```

`destroy` leaves `terraform.tfstate` (now with `"resources": []`) and `terraform.tfstate.backup` (the state before the destroy, with every attribute) behind. Delete them, `.terraform/`, and `.terraform.lock.hcl` to reset the folder.

## What differs on real AWS

| On the emulator | On real AWS |
|---|---|
| Fake keys, `skip_*` flags, `s3_use_path_style`, `endpoints` in `providers.tf` | Remove all of them. Credentials come from the environment, an assumed role, or OIDC. See [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md). |
| The apply needs no permissions | The caller needs the S3 and KMS actions the provider calls, including the read actions used during refresh. A missing one fails mid-apply and leaves a partial state. |
| `lab01-first-apply` is always free | Bucket names are globally unique in the default namespace. The apply fails with `BucketAlreadyExists` if anyone owns the name, and neither `validate` nor `plan` can warn you. |
| After `destroy`, `aws kms describe-key` shows the key as `PendingDeletion` with a date 7 days out. It vanishes when floci stops. | The same: `destroy` only schedules deletion after `deletion_window_in_days` (7 is the minimum). The key is billed until then and can be recovered with `cancel-key-deletion`. See [KMS key scheduled deletion](../../runbooks/kms-key-scheduled-deletion.md). |
| The key gets a default policy and nothing enforces it | The key policy decides who can use the key. Every principal that reads or writes the bucket also needs permission to use the key. |
| Destroying the bucket is instant | The bucket must be empty, including old object versions and delete markers. `force_destroy = true` makes Terraform empty it first, which is rarely what you want on a bucket that matters. |
