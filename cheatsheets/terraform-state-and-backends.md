# Terraform state and backends cheatsheet

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2d, 6a–6d, 7b · **SCS-C03:** 6.2.1 · **Teaching note:** [State management](../teaching/terraform/06-state-management.md), [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md) · **Runbook:** [State exposure](../runbooks/terraform-state-exposure.md), [State lock and corruption](../runbooks/terraform-state-lock-and-corruption.md), [Unexpected drift](../runbooks/terraform-unexpected-drift.md) · **Lab:** [02 Remote state](../labs/02-remote-state/README.md), [06 Drift and import](../labs/06-drift-and-import/README.md) · **Control mapping:** [IaC with Terraform](../control-mappings/services/iac-terraform.md)

## What state stores

| Field | Notes |
|---|---|
| Resource addresses mapped to real object IDs | The reason state exists: configuration alone cannot say which bucket is `aws_s3_bucket.logs` |
| Every attribute of every managed resource and data source | **Includes secrets in clear text**: passwords, private keys, secret versions. `sensitive = true` does not change this. |
| Dependency order and provider addresses | Used to destroy in the right order after a block is deleted |
| Root module outputs | Readable by anyone who can read the state |
| `serial` | Increments on every write. A push with a lower serial is refused. |
| `lineage` | Unique ID set when the state is first created. A different lineage means a different state, not a newer one. |
| `terraform_version`, `version` | Version of Terraform that last wrote it, and the state format version |

Not in state: ephemeral resources, write-only arguments, ephemeral variables. Treat a state file as a secret and as a map of the environment.

## Local and remote

| | Local backend (default) | Remote backend (S3, HCP Terraform, and others) |
|---|---|---|
| Location | `terraform.tfstate` in the working directory | Shared store |
| Previous version | `terraform.tfstate.backup` (one generation) | Store's own versioning |
| Workspaces | `terraform.tfstate.d/WORKSPACE_NAME/` | Backend-specific path |
| Locking | Operating-system file lock; protects one machine only | Backend lock; protects the team |
| Encryption at rest | None | Backend feature (SSE-KMS on S3; always on in HCP Terraform) |
| Access control | File permissions | IAM, bucket policy, key policy |
| Use for | Learning, throwaway labs | Everything shared or real |

The backend stores state. It does not run Terraform, except HCP Terraform, which can do both.

## S3 backend

```hcl
terraform {
  backend "s3" {
    bucket              = "STATE_BUCKET"
    key                 = "PROJECT/ENV/terraform.tfstate"
    region              = "eu-west-1"
    encrypt             = true
    kms_key_id          = "arn:aws:kms:eu-west-1:111122223333:key/KEY_ID"
    use_lockfile        = true
    allowed_account_ids = ["111122223333"]

    assume_role = {
      role_arn     = "arn:aws:iam::111122223333:role/terraform-state"
      session_name = "terraform-state"
    }
  }
}
```

| Argument | Notes |
|---|---|
| `bucket`, `key`, `region` | Required. `key` is the object path of the state. |
| `use_lockfile` | `true` turns on S3-native locking: a `KEY.tflock` object written with a conditional put. Default `false`. Added in 1.10 **(verify)**. |
| `encrypt` | `true` requests server-side encryption for the state and lock objects |
| `kms_key_id` | KMS key ARN for SSE-KMS. Caller needs `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey`. |
| `assume_role` | Object: `role_arn` (required), `session_name`, `external_id`, `duration`, `policy`, `policy_arns`, `source_identity`, `tags`, `transitive_tag_keys` |
| `assume_role_with_web_identity` | Object: `role_arn`, `web_identity_token` or `web_identity_token_file`, `session_name`, `duration`, `policy`, `policy_arns` |
| `allowed_account_ids`, `forbidden_account_ids` | Fail early if the credentials belong to the wrong account. Mutually exclusive. |
| `workspace_key_prefix` | Prefix for non-default workspaces. Default `env:`, giving `env:/WORKSPACE_NAME/KEY`. |
| `profile`, `shared_config_files`, `shared_credentials_files` | Named profile and where to find it |
| `access_key`, `secret_key`, `token` | Supported; do not use. They end up in `.terraform/` and in plan files. |
| `acl`, `sse_customer_key` | Canned ACL; SSE-C key. Avoid both. |
| `use_path_style`, `endpoints`, `skip_*` flags | For emulators and S3-compatible stores only |
| `dynamodb_table` | **Deprecated.** DynamoDB lock table with a string partition key `LockID`. Scheduled for removal in a future minor version. |
| `dynamodb_endpoint` | **Deprecated.** Was replaced by `endpoints.dynamodb`. |

The backend authenticates **separately** from the `provider "aws"` block. State can live in one account while resources are created in another.

**Moving off DynamoDB locking:** set `use_lockfile = true` alongside `dynamodb_table`, run `terraform init -reconfigure` (Terraform then takes both locks), confirm the whole team and CI are on a version that supports it, then delete `dynamodb_table` and the table.

## Hardened state bucket

- [ ] Dedicated bucket in a dedicated account or at least a dedicated role; nothing else stored in it
- [ ] Block Public Access, all four settings: `aws_s3_bucket_public_access_block`
- [ ] ACLs disabled: `aws_s3_bucket_ownership_controls` with `BucketOwnerEnforced`
- [ ] Versioning on: `aws_s3_bucket_versioning`. This is the recovery mechanism.
- [ ] Default encryption SSE-KMS with a customer managed key and Bucket Keys: `aws_s3_bucket_server_side_encryption_configuration`, `aws_kms_key`
- [ ] Bucket policy: deny non-TLS, deny every principal except the Terraform roles: `aws_s3_bucket_policy`
- [ ] Key policy limits `kms:Decrypt` to the same roles. See the [KMS cheatsheet](kms.md).
- [ ] Lifecycle rule expiring noncurrent versions after a retention period, and aborting incomplete multipart uploads: `aws_s3_bucket_lifecycle_configuration`
- [ ] `lifecycle { prevent_destroy = true }` on the bucket and the key
- [ ] CloudTrail data events on the bucket; alert on reads by any principal outside the pipeline: `aws_cloudtrail` with an advanced event selector
- [ ] Server access logging to a separate bucket: `aws_s3_bucket_logging`
- [ ] Optional: replication to a second Region or account: `aws_s3_bucket_replication_configuration`
- [ ] The bucket that holds state is created by a separate bootstrap configuration, not by the configuration that uses it

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::STATE_BUCKET", "arn:aws:s3:::STATE_BUCKET/*"],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "DenyAllExceptTerraformRoles",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::STATE_BUCKET", "arn:aws:s3:::STATE_BUCKET/*"],
      "Condition": {
        "ArnNotLike": {
          "aws:PrincipalArn": [
            "arn:aws:iam::111122223333:role/terraform-plan",
            "arn:aws:iam::111122223333:role/terraform-apply",
            "arn:aws:iam::111122223333:role/state-bucket-admin"
          ]
        }
      }
    },
    {
      "Sid": "DenyStateWithoutTheKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::STATE_BUCKET/*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:eu-west-1:111122223333:key/KEY_ID"
        }
      }
    }
  ]
}
```

More statements (organization only, VPC endpoint only, deny SSE-C): [S3 security cheatsheet](s3-security.md). The matching identity policy and the plan-role and apply-role split: [AWS provider security cheatsheet](terraform-aws-provider-security.md).

## Partial backend configuration

Leave out what differs per environment and supply it at `init`. Backend blocks cannot use variables or locals.

```hcl
terraform {
  backend "s3" {}
}
```

```hcl
# backend-prod.hcl
bucket       = "STATE_BUCKET"
key          = "PROJECT/prod/terraform.tfstate"
region       = "eu-west-1"
encrypt      = true
use_lockfile = true
```

```bash
terraform init -backend-config=backend-prod.hcl
terraform init -backend-config="bucket=STATE_BUCKET" -backend-config="key=PROJECT/prod/terraform.tfstate"
```

Values given with `-backend-config` are written in clear text to `.terraform/terraform.tfstate` and into saved plan files. Pass credentials through the environment, never this way.

## Migration

```bash
terraform state pull > pre-migration.tfstate     # keep a copy first
terraform init -migrate-state                    # [changes state] after adding or editing the backend block: copies state to the new backend
terraform init -migrate-state -force-copy        # [changes state] same, no prompts
terraform init -reconfigure                      # use the new backend as is; copies nothing, old state stays where it was
terraform state list                             # confirm the new backend holds what you expect
```

Removing the `backend` block and running `terraform init -migrate-state` copies state back to local. After migrating away from local, delete the leftover `terraform.tfstate` and `.backup` files: they still hold every secret.

## Locking

| Fact | Detail |
|---|---|
| What takes a lock | Anything that could write state: `plan`, `apply`, `destroy`, `import`, `state mv`, `state rm`, `state push`, `force-unlock`. Read-only `state list`, `state show`, `output` do not. |
| S3-native lock | Object `KEY.tflock` next to the state. Needs `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on that object. |
| DynamoDB lock (deprecated) | Item keyed `BUCKET/KEY` in the lock table. Needs `dynamodb:DescribeTable`, `GetItem`, `PutItem`, `DeleteItem`. |
| Lock held | The command fails at once with the lock ID, holder, and time. `-lock-timeout=60s` retries instead. |
| `-lock=false` | Skips locking. Only for a read-only plan when you accept the risk. |
| Backend without locking support | Terraform proceeds with no protection. Check the backend's documentation. |

```bash
terraform plan -lock-timeout=120s
terraform force-unlock LOCK_ID                   # [changes state] removes someone else's lock
```

`force-unlock` does not stop the process that holds the lock. Confirm that run is dead first (crashed runner, cancelled job), or two writers will corrupt state. Procedure: [state lock and corruption runbook](../runbooks/terraform-state-lock-and-corruption.md).

## I need to …

| I need to … | Use | Not |
|---|---|---|
| Rename a resource, or move it into or out of a module | `moved` block, then plan shows "has moved" with no destroy | Editing the name alone: plans destroy and create |
| Rename once, by hand, in one state | `terraform state mv SOURCE DEST` **[changes state]** | |
| Stop managing a resource without destroying it | `removed` block with `lifecycle { destroy = false }` | Deleting the block alone: plans a destroy |
| Same, by hand | `terraform state rm ADDRESS` **[changes state]** | |
| Bring an existing resource under management | `import` block, plus `plan -generate-config-out=FILE` to draft the configuration | Writing the block alone: plans a duplicate create |
| Same, by hand | `terraform import ADDRESS ID` **[changes state]** | |
| Recreate a healthy-looking but broken resource | `terraform apply -replace=ADDRESS` **[changes state]** | `terraform taint` (deprecated) |
| See what changed outside Terraform | `terraform plan -refresh-only` | |
| Accept an out-of-band change as the new truth | `terraform apply -refresh-only` **[changes state]**, then update the configuration to match | `terraform refresh` (deprecated) |
| Revert an out-of-band change | Plain `terraform apply`: configuration wins | |
| Tolerate a field another system owns | `lifecycle { ignore_changes = [ATTR] }` | |
| Split one state into two | In the source: `removed` blocks with `destroy = false`. In the destination: `import` blocks. Apply the source first. | Editing state JSON by hand |
| Merge two states | Same pattern in the other direction | |
| Change a provider's source address | `terraform state replace-provider FROM TO` **[changes state]** | |
| Read another configuration's outputs | `terraform_remote_state`, or better, a data source | Copying values by hand |

Drift you did not expect is a security signal as well as a hygiene problem: [unexpected drift runbook](../runbooks/terraform-unexpected-drift.md).

## Reading another configuration

| | `terraform_remote_state` data source | Provider data source (`aws_vpc`, `aws_ssm_parameter`) | `tfe_outputs` |
|---|---|---|---|
| Reads | Root outputs of another state | The real object, or a value the producer published | Outputs of an HCP Terraform workspace |
| Access needed | **Read on the whole state object**, secrets included | Read on that one resource or parameter | Outputs only |
| Coupling | To the other team's backend layout | To a name, tag, or parameter path | To a workspace name |
| Prefer when | Same team, same trust level | Crossing a team or trust boundary | State lives in HCP Terraform |

```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "STATE_BUCKET"
    key    = "network/prod/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}
```

Only root module outputs are exposed. A child module's output must be re-exported by the root to be visible.

## Workspaces or separate backends

| | CLI workspaces | Separate directory and backend per environment |
|---|---|---|
| Configuration | One copy; differs only through `terraform.workspace` and variables | One root module per environment, sharing child modules |
| State | Same bucket, different key (`env:/NAME/KEY`) | Different key, bucket, or account |
| Credentials and permissions | **Shared**: whoever can apply to one can apply to all | Separate role per environment |
| Risk | Applying to the wrong workspace | More files to keep in step |
| Use for | Short-lived copies: feature branches, test stacks | Dev, stage, and prod; anything with a different blast radius |

HCP Terraform workspaces are a different thing: each has its own state, variables, credentials, and run history. See [HCP Terraform](../teaching/terraform/08-hcp-terraform.md).

## Recover state from S3 versions

```bash
# Find the last good version
aws s3api list-object-versions --bucket STATE_BUCKET --prefix STATE_KEY \
  --query 'Versions[].[VersionId,LastModified,IsLatest,Size]' --output table

# Download it and check it is what you think it is
aws s3api get-object --bucket STATE_BUCKET --key STATE_KEY --version-id VERSION_ID recovered.tfstate
terraform show recovered.tfstate | head -n 40
grep -E '"(serial|lineage)"' recovered.tfstate

# [changes state] Put it back through Terraform, which takes the lock and checks lineage and serial
terraform state push recovered.tfstate

# Compare the recovered state with reality before applying anything
terraform plan -refresh-only
```

- `state push` refuses a file whose `serial` is lower than the current one. Raise `serial` in the recovered file above the current value, or use `-force` once you are sure.
- State deleted outright: remove the delete marker instead. **[changes state]** `aws s3api delete-object --bucket STATE_BUCKET --key STATE_KEY --version-id DELETE_MARKER_VERSION_ID`
- With the deprecated DynamoDB lock table, a checksum item keyed `BUCKET/KEY-md5` must match the restored object, or `init` fails with a checksum error. Update or delete that item **(verify)**.
- Resources created after the recovered version are missing from it. The refresh-only plan will not find them; re-adopt them with `import` blocks.
- If the state may have been read by someone it should not have been, rotating every secret in it is part of recovery: [state exposure runbook](../runbooks/terraform-state-exposure.md).
