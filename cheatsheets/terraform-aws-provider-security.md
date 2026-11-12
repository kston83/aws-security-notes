# Terraform AWS provider security cheatsheet

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2a–2c, 4h · **SCS-C03:** 4.1.2, 4.2.3, 6.2.1 · **Teaching note:** [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md), [Terraform fundamentals](../teaching/terraform/02-terraform-fundamentals.md) · **Runbook:** [Pipeline compromise](../runbooks/terraform-pipeline-compromise.md), [State exposure](../runbooks/terraform-state-exposure.md) · **Lab:** [04 IAM least privilege](../labs/04-iam-least-privilege/README.md), [05 KMS and secrets](../labs/05-kms-and-secrets/README.md) · **Control mapping:** [IaC with Terraform](../control-mappings/services/iac-terraform.md) · AWS provider v6 (`~> 6.0`), Terraform 1.12 or later.

## Authentication precedence

The provider uses the first source that yields credentials, then applies `assume_role` on top. The S3 backend resolves its own credentials the same way: [state and backends cheatsheet](terraform-state-and-backends.md).

| Order | Source | Use |
|---|---|---|
| 1 | `provider` block: `access_key`, `secret_key`, `token`, `profile`, `assume_role`, `assume_role_with_web_identity` | `assume_role` only. Never static keys. |
| 2 | Environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_ROLE_ARN` with `AWS_WEB_IDENTITY_TOKEN_FILE` | CI with short-lived OIDC credentials |
| 3 | Shared credentials file (`~/.aws/credentials`) | Avoid: long-lived keys on disk |
| 4 | Shared config file (`~/.aws/config`) | Workstations: IAM Identity Center profile, `aws sso login --profile PROFILE_NAME` |
| 5 | Container credentials (ECS task role, EKS Pod Identity) | Self-hosted runners in containers |
| 6 | Instance profile through IMDS | Self-hosted runners on EC2 |

## Provider arguments

| Argument | Security use |
|---|---|
| `region` | Default Region. In v6 most resources also take their own `region` argument. |
| `assume_role { }` | `role_arn` (required), `session_name` (shows in CloudTrail; set it to the run ID), `external_id`, `duration`, `policy` and `policy_arns` (session policy: narrows, never widens), `source_identity`, `tags`, `transitive_tag_keys`. Repeat the block to chain roles, in order. |
| `assume_role_with_web_identity { }` | `role_arn`, `web_identity_token` or `web_identity_token_file`, `session_name`, `duration`, `policy`, `policy_arns`. One block only. |
| `allowed_account_ids` / `forbidden_account_ids` | Refuse to run in any other account / in these accounts. Mutually exclusive. A safety catch, not an access control. |
| `default_tags { tags = { } }` | Tags on every taggable resource: owner, repository, data classification |
| `ignore_tags { keys, key_prefixes }` | Stop other systems' tags showing as drift. Also hides tampering with those keys. |
| `tag_policy_compliance` | `error`, `warning`, or `disabled` (default): check Organizations tag policy required keys at plan time **(verify)** |
| `profile`, `shared_config_files`, `shared_credentials_files` | Prefer `AWS_PROFILE` in the environment over a profile in code |
| `alias` | Second configuration: another account or Region |
| `use_fips_endpoint`, `sts_region` | FIPS endpoints for all services; Region of the STS endpoint |
| `retry_mode`, `max_retries` | `standard` or `adaptive`; default 25 retries **(verify)** |
| `custom_ca_bundle`, `http_proxy`, `https_proxy`, `no_proxy` | TLS inspection and egress proxies |
| `insecure` | Skips TLS verification. Never `true`. |
| `access_key`, `secret_key`, `token` | Never in a real configuration: they land in version control and plan files |
| `endpoints { }`, `s3_use_path_style`, `skip_*` | Emulators only: see the last section |

```hcl
provider "aws" {
  region              = "eu-west-1"
  allowed_account_ids = ["111122223333"]

  assume_role {
    role_arn     = "arn:aws:iam::111122223333:role/terraform-apply"
    session_name = "terraform-PIPELINE_RUN_ID"
    duration     = "30m"
  }

  default_tags {
    tags = { ManagedBy = "terraform", Repository = "ORG_NAME/REPO_NAME" }
  }
}

provider "aws" {
  alias               = "audit"
  region              = "eu-west-1"
  allowed_account_ids = ["444455556666"]
  assume_role { role_arn = "arn:aws:iam::444455556666:role/terraform-apply" }
}
```

## OIDC trust policies

Condition on **both** `aud` and `sub`. With `aud` alone, any repository or organization on that platform can assume the role. Background: [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md#oidc-federation-from-ci).

### GitHub Actions

Provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. The workflow needs `permissions: id-token: write`.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:ORG_NAME/REPO_NAME:environment:production"
      }
    }
  }]
}
```

| Run | `sub` claim ([GitHub docs](https://docs.github.com/en/actions/reference/security/oidc)) |
|---|---|
| Job that references an environment | `repo:ORG_NAME/REPO_NAME:environment:ENVIRONMENT_NAME` |
| Pull request, no environment | `repo:ORG_NAME/REPO_NAME:pull_request` |
| Branch, no environment, not a pull request | `repo:ORG_NAME/REPO_NAME:ref:refs/heads/BRANCH_NAME` |
| Tag, no environment, not a pull request | `repo:ORG_NAME/REPO_NAME:ref:refs/tags/TAG_NAME` |
| Repository created, renamed, or transferred after 2026-07-15, or opted in **(verify)** | Immutable IDs added: `repo:ORG_NAME@OWNER_ID/REPO_NAME@REPO_ID:ref:refs/heads/BRANCH_NAME` |

- Apply role: trust the `environment:` form and protect that environment with required reviewers. Plan role: trust `pull_request`, read-only, no secrets: it covers every pull request in the repository.
- No `StringLike` on `repo:ORG_NAME/*`. Keep any wildcard inside one repository.
- A name-only `sub` can be claimed by whoever re-registers a deleted organization or repository name. Prefer the immutable form, or also condition on the `repository_id` claim **(verify)** the condition keys AWS supports.

### HCP Terraform dynamic credentials

Provider URL `https://app.terraform.io` (no trailing slash), audience `aws.workload.identity`. Same trust policy shape as above, with:

```json
"StringEquals": {
  "app.terraform.io:aud": "aws.workload.identity",
  "app.terraform.io:sub": "organization:ORG_NAME:project:PROJECT_NAME:workspace:WORKSPACE_NAME:run_phase:apply"
}
```

| Workspace environment variable | Value |
|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true`. Required. |
| `TFC_AWS_RUN_ROLE_ARN` | Role for both phases; optional when the two below are set |
| `TFC_AWS_PLAN_ROLE_ARN`, `TFC_AWS_APPLY_ROLE_ARN` | Per-phase roles; trust policy `sub` ends `run_phase:plan` or `run_phase:apply` |
| `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` | Override the audience |

One role for both phases needs `StringLike` with `run_phase:*`. Never wildcard the organization. Background: [HCP Terraform](../teaching/terraform/08-hcp-terraform.md).

## Plan role and apply role

| | Plan role | Apply role |
|---|---|---|
| Assumed by | Any pull request run | Protected branch or environment, after approval |
| AWS permissions | Read-only, with an explicit deny on reading secret values and decrypting data it does not need | Create, update, delete for the managed services, capped by a permissions boundary |
| State | Read state; write and delete the `.tflock` object | Read and write state and lock |
| IAM | None | Create roles only with the boundary attached (`iam:PermissionsBoundary` condition); scoped `iam:PassRole` |
| If compromised | Attacker reads **the state**, which holds secrets | Attacker changes infrastructure |

A plan runs data sources and `external` programs from the pull request's code, so a plan role is not harmless. Boundaries: [IAM policy evaluation cheatsheet](iam-policy-evaluation.md).

## Least-privilege state access

Apply role, S3 backend with `use_lockfile = true` and SSE-KMS. Permission list per the [S3 backend docs](https://developer.hashicorp.com/terraform/language/backend/s3):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "ListStatePrefix", "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::STATE_BUCKET",
      "Condition": { "StringLike": { "s3:prefix": ["PROJECT/ENV/*"] } } },
    { "Sid": "ReadWriteState", "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::STATE_BUCKET/PROJECT/ENV/terraform.tfstate" },
    { "Sid": "LockFile", "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::STATE_BUCKET/PROJECT/ENV/terraform.tfstate.tflock" },
    { "Sid": "StateKey", "Effect": "Allow", "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:eu-west-1:111122223333:key/KEY_ID" }
  ]
}
```

Plan role: the same minus `s3:PutObject` in `ReadWriteState`. No role gets `s3:DeleteObject` on the state object, `s3:DeleteObjectVersion`, `s3:PutBucketVersioning`, or `s3:PutBucketPolicy`. CLI workspaces also need `s3:DeleteObject` under the workspace prefix to delete a workspace. Bucket policy: [state and backends cheatsheet](terraform-state-and-backends.md#hardened-state-bucket).

## Secure resource patterns

| Resource | Resources and arguments | Notes |
|---|---|---|
| S3 bucket | `aws_s3_bucket_public_access_block` (all four `true`), `aws_s3_bucket_ownership_controls` (`BucketOwnerEnforced`), `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration` (`aws:kms`, `bucket_key_enabled`), `aws_s3_bucket_policy` from `aws_iam_policy_document` denying `aws:SecureTransport = false` | Give the policy `depends_on` the public access block. Detail: [S3 cheatsheet](s3-security.md). Worked: [lab 01](../labs/01-first-apply/README.md), [lab 03](../labs/03-variables-and-modules/README.md). |
| KMS key | `enable_key_rotation = true`, `rotation_period_in_days`, `deletion_window_in_days = 30`, an explicit `policy` separating administrators from users, `lifecycle { prevent_destroy = true }` | [KMS cheatsheet](kms.md) |
| IAM role | `permissions_boundary`, `max_session_duration`; policies from `aws_iam_policy_document` or `jsonencode`, attached with `aws_iam_role_policy_attachment` | The role's `inline_policy` and `managed_policy_arns` arguments are deprecated **(verify)** |
| Security group | One `aws_vpc_security_group_ingress_rule` or `_egress_rule` per source, using `referenced_security_group_id` or `prefix_list_id` where possible | Do not mix with inline `ingress`/`egress` blocks or `aws_security_group_rule` on one group: they overwrite each other |
| RDS | `manage_master_user_password = true` with `master_user_secret_kms_key_id`; `storage_encrypted`, `kms_key_id`, `publicly_accessible = false`, `iam_database_authentication_enabled`, `deletion_protection`, `backup_retention_period`, `skip_final_snapshot = false` | The password never reaches Terraform; the secret ARN is `master_user_secret[0].secret_arn`. Conflicts with `password` and `password_wo`. |

### Ephemeral values and write-only arguments

Ephemeral resources need Terraform 1.10, write-only arguments 1.11 **(verify)**. Neither value is stored in state or plan files.

```hcl
ephemeral "random_password" "db" {                    # hashicorp/random; generated each run, never stored
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id                = aws_secretsmanager_secret.db.id
  secret_string_wo         = ephemeral.random_password.db.result
  secret_string_wo_version = 1                         # increase to send a new value
}

ephemeral "aws_secretsmanager_secret_version" "db" {   # read it back without storing it
  secret_id = aws_secretsmanager_secret_version.db.secret_id
}

resource "aws_db_instance" "legacy" {
  # ... engine, instance_class, storage ...
  password_wo         = ephemeral.aws_secretsmanager_secret_version.db.secret_string
  password_wo_version = aws_secretsmanager_secret_version.db.secret_string_wo_version
}
```

A `data "aws_secretsmanager_secret_version"` block, or the plain `password` and `secret_string` arguments, copy the secret into state. Language rules: [HCL cheatsheet](terraform-hcl.md#sensitive-ephemeral-write-only). Worked: [lab 05](../labs/05-kms-and-secrets/README.md).

## Commonly flagged misconfigurations

| Finding | Fix in Terraform |
|---|---|
| Static credentials in the provider block or `.tfvars` | Remove `access_key` and `secret_key`; use OIDC or `assume_role` |
| S3 bucket can be made public | `aws_s3_bucket_public_access_block` with all four `true`; `aws_s3_account_public_access_block` for the account |
| S3 bucket without versioning or with default encryption only | `aws_s3_bucket_versioning`; `aws_s3_bucket_server_side_encryption_configuration` with `aws:kms` |
| S3 allows plain HTTP | Bucket policy denying `aws:SecureTransport = false` |
| Security group open to `0.0.0.0/0` on 22 or 3389 | `referenced_security_group_id` or a narrow `cidr_ipv4`; Session Manager instead of an open port |
| Default security group allows traffic | `aws_default_security_group` with no rules |
| EC2 allows IMDSv1 | `metadata_options { http_tokens = "required" }` on `aws_instance` and `aws_launch_template` |
| EBS volume unencrypted | `encrypted = true` with `kms_key_id`; account-wide `aws_ebs_encryption_by_default` |
| RDS public, unencrypted, or deletable | `publicly_accessible = false`, `storage_encrypted = true`, `deletion_protection = true` |
| Database password in configuration or state | `manage_master_user_password = true`, or `password_wo` |
| KMS key without rotation | `enable_key_rotation = true` |
| IAM policy with `Action "*"` on `Resource "*"` | Scoped `aws_iam_policy_document`; `permissions_boundary` on roles |
| Role trust policy with a wildcard principal or no conditions | Named principals; `sts:ExternalId`, `aws:SourceArn`, or OIDC `sub` conditions |
| CloudTrail single-Region, unvalidated, or unencrypted | `is_multi_region_trail = true`, `enable_log_file_validation = true`, `kms_key_id` |
| CloudWatch log group kept forever, unencrypted | `retention_in_days`, `kms_key_id` |
| VPC without flow logs | `aws_flow_log` |
| Load balancer listener on HTTP or an old TLS policy | `protocol = "HTTPS"` with a current `ssl_policy`; HTTP listener with a `redirect` action |
| SNS topic or SQS queue unencrypted | `kms_master_key_id` |
| ECR tags mutable, images unscanned | `image_tag_mutability = "IMMUTABLE"`; `image_scanning_configuration { scan_on_push = true }` |
| Lambda secrets in environment variables | Read from Secrets Manager at run time; `kms_key_arn` on the function |
| Critical resource deletable by a bad plan | `lifecycle { prevent_destroy = true }` plus the service's own deletion protection. Deleting the resource block removes the guard with it. |
| Module pulled from a moving reference | Registry `version`, or Git `?ref=COMMIT_SHA`; commit `.terraform.lock.hcl` |

Scanner rule IDs, AWS Config rule names, and Security Hub control IDs change; they are mapped in [control-mappings/services/iac-terraform.md](../control-mappings/services/iac-terraform.md).

## Local emulator (floci): lab only

The labs use the provider block shown in [labs/README.md](../labs/README.md#the-lab-provider-block). **None of these settings belong in a configuration that targets real AWS.**

| Setting | Why it is unsafe outside a lab |
|---|---|
| `access_key`, `secret_key` | Static credentials in source, copied into plan files |
| `skip_credentials_validation` | The provider no longer checks with STS that the credentials work |
| `skip_requesting_account_id` | No account ID lookup, so `allowed_account_ids` cannot protect you and some ARNs are built with an empty account |
| `skip_metadata_api_check` | Disables the instance metadata credential source |
| `s3_use_path_style` | Only needed where buckets have no DNS names |
| `endpoints` | Redirects signed requests and payloads to whatever host is named. A service with no entry goes to real AWS (or to `AWS_ENDPOINT_URL` if set). |

floci does not enforce IAM by default, so a lab that applies cleanly proves nothing about permissions.
