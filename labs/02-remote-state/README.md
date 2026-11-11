# Lab 02: Remote state

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2d, 6a–6c · **SCS-C03:** 6.2.1 · **Time:** 45 minutes · **Related:** [State management](../../teaching/terraform/06-state-management.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [State and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [Terraform CLI cheatsheet](../../cheatsheets/terraform-cli.md), [State exposure runbook](../../runbooks/terraform-state-exposure.md), [State lock and corruption runbook](../../runbooks/terraform-state-lock-and-corruption.md)

## Goal

Build a hardened S3 bucket for Terraform state, point a second configuration at it with the `s3` backend and S3-native locking, and look at state the way an attacker or responder would: a JSON object in a bucket, with versions, a lock file, and a plaintext secret. Afterward you can configure a backend, migrate state in both directions, read a lock error, and recover from a deleted state version.

## Before you start

- floci is running and the AWS CLI points at it (`AWS_ENDPOINT_URL` exported). See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) first. Read [State management](../../teaching/terraform/06-state-management.md).
- The locking steps need two terminals, both with the `AWS_*` variables exported.

| Folder | Root configuration | State lives |
|---|---|---|
| `bootstrap/` | State bucket `lab02-tfstate` (versioned, SSE-KMS, public access blocked, TLS-only policy) and its KMS key | Locally at first: the bucket cannot hold state before it exists |
| `workload/` | A `random_password` stored in an SSM SecureString parameter. A bad pattern, on purpose. | In the bucket, key `workload/terraform.tfstate` |

## Steps

### 1. Create the state bucket with local state (6a)

```bash
cd bootstrap
terraform init
terraform apply                  # [changes state] type yes
head -6 terraform.tfstate
KEY_ARN=$(terraform output -raw kms_key_arn)
```

```
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
...
kms_key_arn = "arn:aws:kms:us-east-1:000000000000:key/2d464eb6-b534-4047-8b00-f13723e3effa"
state_bucket = "lab02-tfstate"
{
  "version": 4,
  "terraform_version": "1.17.1",
  "serial": 9,
  "lineage": "f6f656f0-5c29-2c9f-59c7-e684f08e690d",
  "outputs": {
```

With no `backend` block Terraform uses the **local backend**: plain JSON in `terraform.tfstate`. **`serial`** goes up on every write. **`lineage`** is a random ID fixed for the life of the state, so Terraform can refuse to overwrite one state with an unrelated one. Keep this shell open: steps 3 and 8 use `KEY_ARN`.

### 2. Read the backend block (6c)

`workload/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket       = "lab02-tfstate"
    key          = "workload/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    # ... the other skip_* flags, and endpoints = { s3 = "http://localhost:4566" }
  }
}
```

- `bucket`, `key`, `region` (required), `encrypt`, and `kms_key_id` (supplied in step 3) stay on real AWS.
- `use_lockfile` is **S3-native locking**: a `KEY.tflock` object written with a conditional put. Default `false`. It replaces the deprecated `dynamodb_table`.
- Everything below it is for floci only. Never put credentials in a backend block.

The backend does not read the `provider` block, so the lab-only settings are repeated. A backend block cannot use variables or references either: it is read before anything is evaluated.

### 3. Initialize with a partial backend configuration

```bash
cd ../workload
terraform init -backend-config="kms_key_id=$KEY_ARN"
```

```
Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
...
- Installed hashicorp/random v3.9.1 (signed by HashiCorp)
```

`-backend-config` fills in arguments the block leaves out (**partial configuration**). The merged settings are cached in `.terraform/terraform.tfstate`: not your state, but it holds every backend argument, `secret_key` included. One more reason `.terraform/` is never committed.

### 4. Apply

```bash
terraform apply                  # [changes state] type yes
```

```
      + value          = (sensitive value)
...
      + result      = (sensitive value)
...
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
...
db_password = <sensitive>
```

Nothing on screen shows the password, and there is no `terraform.tfstate` in this folder.

### 5. Find the state in the bucket (2d)

```bash
aws s3 ls s3://lab02-tfstate --recursive
aws s3api head-object --bucket lab02-tfstate --key workload/terraform.tfstate --query '[ServerSideEncryption,SSEKMSKeyId,VersionId]'
aws s3api list-object-versions --bucket lab02-tfstate --prefix workload/ --query '{Versions: Versions[].Key, DeleteMarkers: DeleteMarkers[].Key}'
```

```
2026-11-11 09:04:29       3325 workload/terraform.tfstate
[
    "aws:kms",
    "arn:aws:kms:us-east-1:000000000000:key/2d464eb6-b534-4047-8b00-f13723e3effa",
    "9642dfae-32d0-414e-9fda-1255c29e375d"
]
{
    "Versions": [
        "workload/terraform.tfstate",
        "workload/terraform.tfstate.tflock"
    ],
    "DeleteMarkers": [
        "workload/terraform.tfstate.tflock"
    ]
}
```

The state is one encrypted, versioned object. The `.tflock` entries are the apply's lock, created then deleted. In a versioned bucket each delete leaves a delete marker, so lock debris piles up: about 30 versions and markers by the end of a test run of this lab.

### 6. Watch the lock work (6b)

Terminal 1, in `workload/`. Leave it waiting at the prompt:

```bash
terraform apply -replace=random_password.db      # do not answer yet
```

Terminal 2, in `workload/`:

```bash
terraform plan
aws s3 cp s3://lab02-tfstate/workload/terraform.tfstate.tflock -
```

```
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error
StatusCode: 412, ... api error PreconditionFailed: At least
one of the pre-conditions you specified did not hold
Lock Info:
  ID:        8b8b9a94-3c18-78ff-3e30-4f2a01fca3e3
  Path:      lab02-tfstate/workload/terraform.tfstate
  Operation: OperationTypeApply
  Who:       you@your-host
  Version:   1.17.1
  Created:   2026-11-11 15:05:24.009166963 +0000 UTC
...
{"ID":"8b8b9a94-3c18-78ff-3e30-4f2a01fca3e3","Operation":"OperationTypeApply","Info":"","Who":"you@your-host","Version":"1.17.1","Created":"2026-11-11T15:05:24.009166963Z","Path":"lab02-tfstate/workload/terraform.tfstate"}
```

Terminal 1 took the lock before planning and holds it while it waits. Terminal 2 tried to create the same `.tflock` object "only if it does not exist", and S3 answered 412. `Who` and `Created` tell you whom to ask before touching a lock. Type `no` in terminal 1 (`Apply cancelled.`): the lock object is gone (`aws s3 ls s3://lab02-tfstate/workload/`) and `terraform plan` works again.

### 7. Find the secret in state

```bash
terraform output
terraform state pull | grep -n "$(terraform output -raw db_password)"
aws ssm get-parameter --name /lab02/db-password --query 'Parameter.[Type,Value]'
```

```
db_password = <sensitive>
parameter_name = "/lab02/db-password"
8:      "value": "j5XIYwBeD68pyr3J9Cs2EEwt",
48:            "value": "j5XIYwBeD68pyr3J9Cs2EEwt",
101:            "result": "j5XIYwBeD68pyr3J9Cs2EEwt",
[
    "SecureString",
    "S01TMwEAJGQ0ZDc5NjMzLWM3OWQtNDVkZi1hMWFhLTdlODJjZGE1NWM1NAAkNWE4MzE1OTgtMmRhYS00..."
]
```

`sensitive` only redacts terminal output. State holds the password three times in plaintext: the output, the parameter's `value`, and the `random_password` result. SSM returns ciphertext unless asked to decrypt, but anyone who can read the state object (`s3:GetObject` plus `kms:Decrypt` on the state key) skips SSM entirely. See the [State exposure runbook](../../runbooks/terraform-state-exposure.md); [Lab 05](../05-kms-and-secrets/README.md) keeps values out of state.

### 8. Migrate the bootstrap state into the bucket

```bash
cd ../bootstrap
cp backend.tf.example backend.tf
terraform init -migrate-state -backend-config="kms_key_id=$KEY_ARN"     # [changes state] type yes
aws s3 ls s3://lab02-tfstate --recursive
ls -la terraform.tfstate*
```

```
Do you want to copy existing state to the new backend?
...
Successfully configured the backend "s3"! ...
2026-11-11 09:04:43      12799 bootstrap/terraform.tfstate
2026-11-11 09:04:29       3325 workload/terraform.tfstate
-rw-r--r-- 1 you you     0 Nov 11 09:04 terraform.tfstate
-rw-r--r-- 1 you you 12799 Nov 11 09:04 terraform.tfstate.backup
```

`terraform plan` reports no changes: same resources, new home. The local `terraform.tfstate` is emptied, but `terraform.tfstate.backup` still holds a full copy; migration never cleans up behind it. In this run `terraform state pull` showed the migrated copy starting again at `"serial": 1` with a new lineage **(verify)**.

## Verify

```bash
aws s3api get-bucket-versioning --bucket lab02-tfstate --query Status
aws s3api get-bucket-encryption --bucket lab02-tfstate --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-public-access-block --bucket lab02-tfstate --query PublicAccessBlockConfiguration
aws s3api get-bucket-policy --bucket lab02-tfstate --query Policy --output text
```

```
"Enabled"
...
    "SSEAlgorithm": "aws:kms",
    "KMSMasterKeyID": "arn:aws:kms:us-east-1:000000000000:key/2d464eb6-b534-4047-8b00-f13723e3effa"
...
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
}
{"Statement":[{"Action":"s3:*","Condition":{"Bool":{"aws:SecureTransport":"false"}},"Effect":"Deny","Principal":"*","Resource":["arn:aws:s3:::lab02-tfstate/*","arn:aws:s3:::lab02-tfstate"],"Sid":"DenyInsecureTransport"}],"Version":"2012-10-17"}
```

## Break it

Run these from `workload/` (`cd ../workload`).

### 1. Change the backend without running `init`

```bash
sed -i.bak 's#workload/terraform.tfstate#workload/renamed.tfstate#' backend.tf
terraform plan
mv backend.tf.bak backend.tf
```

```
Error: Backend initialization required, please run "terraform init"

Reason: Backend configuration block has changed
...
"terraform init" with either the "-reconfigure" or "-migrate-state" flags to
use the current configuration.
```

Terraform compares the block with the copy cached in `.terraform/` and refuses to guess. `-migrate-state` copies state to the new location; `-reconfigure` ignores the old one, which on a real workload means planning against an empty state.

### 2. Force-unlock with the wrong ID, then the right one

Hold the lock again in terminal 1 (`terraform apply -replace=random_password.db`, do not answer). In terminal 2, with `LOCK_ID` from the error message:

```bash
terraform force-unlock -force 00000000-0000-0000-0000-000000000000
terraform force-unlock -force LOCK_ID            # [changes state] deletes the lock object
```

```
Failed to unlock state: lock ID '00000000-0000-0000-0000-000000000000' does not match the existing lock ID 'b184c61a-b407-6a91-4373-f0a41aed8ae7'
...
Terraform state has been successfully unlocked!
```

The ID check stops you removing a lock other than the one you looked at. It does not check that the holder is dead: terminal 1 is still running, now unprotected. Type `no` there and it reports `An error occurred while releasing this lock`. Force-unlock only once the process in `Who` is confirmed finished: [State lock and corruption runbook](../../runbooks/terraform-state-lock-and-corruption.md).

### 3. Delete the newest state version

Rotate the password so the state has two versions, keep a backup, then permanently delete the newest version:

```bash
terraform apply -replace=random_password.db -auto-approve      # [changes state]
terraform state pull > backup.tfstate
NEWEST=$(aws s3api list-object-versions --bucket lab02-tfstate --prefix workload/terraform.tfstate --query 'Versions[?Key==`workload/terraform.tfstate` && IsLatest].VersionId' --output text)
aws s3api delete-object --bucket lab02-tfstate --key workload/terraform.tfstate --version-id "$NEWEST"      # [changes state]
terraform state pull | grep '"serial"'
terraform plan
```

```
  "serial": 1,
...
  # aws_ssm_parameter.db_password will be updated in-place
...
      ~ value           = (sensitive value)
...
Plan: 0 to add, 1 to change, 0 to destroy.
```

Serial 1 remembers the old password, so the plan offers to write it back over the new one, with no warning that state is stale. Recover by pushing the backup:

```bash
terraform state push backup.tfstate              # [changes state]
terraform plan                                   # No changes.
rm backup.tfstate
```

`backup.tfstate` held the password in plaintext on your disk, and the pre-rotation password is still readable in the older state version.

### 4. Delete the state object

```bash
aws s3 rm s3://lab02-tfstate/workload/terraform.tfstate          # [changes state]
terraform state list
terraform plan
```

```
No state file was found!
...
Plan: 2 to add, 0 to change, 0 to destroy.
```

With no state Terraform believes nothing exists. In a versioned bucket the delete only added a marker; remove it and the state is back:

```bash
MARKER=$(aws s3api list-object-versions --bucket lab02-tfstate --prefix workload/terraform.tfstate --query 'DeleteMarkers[?Key==`workload/terraform.tfstate` && IsLatest].VersionId' --output text)
aws s3api delete-object --bucket lab02-tfstate --key workload/terraform.tfstate --version-id "$MARKER"      # [changes state]
terraform state list
terraform plan                                   # No changes.
```

```
aws_ssm_parameter.db_password
random_password.db
```

## Clean up

Destroy the workload, then migrate the bootstrap state back to local (the second direction of migration): a configuration cannot destroy the bucket that holds its own state.

```bash
terraform destroy                # [changes state] in workload/, type yes
cd ../bootstrap
rm backend.tf
terraform init -migrate-state    # [changes state] type yes: copies state from S3 back to terraform.tfstate
terraform destroy                # [changes state] type yes
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab02-`)].Name'     # []
```

```
Successfully unset the backend "s3". Terraform will now operate locally.
...
Destroy complete! Resources: 7 destroyed.
```

The bucket still held both state objects and every old version; it could be destroyed only because `bootstrap/main.tf` sets `force_destroy = true`. Delete `terraform.tfstate*`, `.terraform/`, and `.terraform.lock.hcl` in both folders to reset.

## What differs on real AWS

| On the emulator | On real AWS |
|---|---|
| Fake keys, `skip_*` flags, `use_path_style`, `endpoints` in the backend and provider blocks | Remove all of them. Backend credentials come from the environment or an assumed role (`assume_role` in the backend block). |
| The TLS-only bucket policy is stored but not enforced; the lab talks to floci over plain HTTP | The `aws:SecureTransport` deny is enforced. Real endpoints are HTTPS, so Terraform is unaffected. |
| Any caller can read the state object and decrypt with the key | Access needs `s3:ListBucket` on the bucket, `s3:GetObject` and `s3:PutObject` on the state key, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on the `.tflock` key, and `kms:Encrypt`, `kms:Decrypt`, and `kms:GenerateDataKey` on the key ([S3 backend docs](https://developer.hashicorp.com/terraform/language/backend/s3)). Scope these per state key: read access to state is read access to every secret in it. |
| `force_destroy = true` on the state bucket | Leave it `false`, add `lifecycle { prevent_destroy = true }`, and add a lifecycle rule expiring noncurrent versions and delete markers so lock debris and old secrets do not live forever. |
| Deleting an object version needs no special permission | Deny `s3:DeleteObjectVersion` to everyone but a break-glass role, or use Object Lock, so exercise 3 is not possible. |
| KMS ciphertext is emulator-specific; SSM returned a ciphertext blob for an undecrypted `get-parameter` | Same shape. CloudTrail records every `kms:Decrypt` on the state key: your audit trail for who read state. |
| One state bucket per lab | Usually one bucket per account or environment, in a dedicated account, with a `key` per configuration. See [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md). |
