# Terraform AWS provider security cheatsheet

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2a–2c, 4h · **SCS-C03:** 4.1.2, 4.2.3, 6.2.1 · **Teaching note:** [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md), [Terraform fundamentals](../teaching/terraform/02-terraform-fundamentals.md) · **Runbook:** [Pipeline compromise](../runbooks/terraform-pipeline-compromise.md), [State exposure](../runbooks/terraform-state-exposure.md) · **Lab:** [04 IAM least privilege](../labs/04-iam-least-privilege/README.md), [05 KMS and secrets](../labs/05-kms-and-secrets/README.md) · **Control mapping:** [IaC with Terraform](../control-mappings/services/iac-terraform.md) · AWS provider v6 (`~> 6.0`), Terraform 1.12 or later.

## Authentication precedence

The provider uses the first source that yields credentials:

| Order | Source | Use |
|---|---|---|
| 1 | Arguments in the `provider` block (`access_key`, `secret_key`, `token`, `profile`, `assume_role`, `assume_role_with_web_identity`) | `assume_role` only. Never static keys: they land in version control and plan files. |
| 2 | Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_ROLE_ARN` with `AWS_WEB_IDENTITY_TOKEN_FILE`) | CI with short-lived credentials from OIDC |
| 3 | Shared credentials file (`~/.aws/credentials`) | Avoid: long-lived keys on disk |
| 4 | Shared configuration file (`~/.aws/config`) | Workstations: IAM Identity Center profile, `aws sso login --profile PROFILE_NAME` |
| 5 | Container credentials (ECS task role, EKS Pod Identity) | Self-hosted runners in containers |
| 6 | Instance profile through IMDS | Self-hosted runners on EC2 |

`assume_role` is applied **on top of** whichever source supplied the base credentials. The S3 backend resolves credentials on its own, by the same order; see the [state and backends cheatsheet](terraform-state-and-backends.md).

## Provider arguments that matter

| Argument | Security use |
|---|---|
| `region` | Default Region. In v6 most resources also accept their own `region` argument, so one provider configuration can span Regions. |
| `assume_role { }` | Assume a deployment role. Repeat the block to chain roles. |
| `assume_role.role_arn` | Role to assume. Required. |
| `assume_role.session_name` | Shows in CloudTrail as the session; set it to the pipeline or run ID |
| `assume_role.external_id` | Confused-deputy guard when a third party assumes the role |
| `assume_role.duration` | Session length, such as `30m`. Keep it close to the run length. |
| `assume_role.policy`, `assume_role.policy_arns` | Session policy: narrows the role's permissions for this run. Cannot widen them. |
| `assume_role.source_identity` | Identity that persists across role chaining and appears in CloudTrail |
| `assume_role.tags`, `assume_role.transitive_tag_keys` | Session tags for attribute-based access control |
| `assume_role_with_web_identity { }` | OIDC federation: `role_arn`, `web_identity_token_file` or `web_identity_token`, `session_name`, `duration`, `policy`, `policy_arns`. One block only. |
| `allowed_account_ids` | Refuse to run unless the credentials belong to one of these accounts. Stops "applied prod to the wrong account". |
| `forbidden_account_ids` | Refuse to run in these accounts. Conflicts with `allowed_account_ids`. |
| `default_tags { tags = { } }` | Tags on every taggable resource: owner, repository, data classification. Supports tag-based policies and cost allocation. |
| `ignore_tags { keys, key_prefixes }` | Ignore tags written by other systems so they do not show as drift. Also hides tag tampering on those keys. |
| `tag_policy_compliance` | `error`, `warning`, or `disabled` (default): check required tag keys from Organizations tag policies at plan time **(verify)** |
| `profile` | Named profile. Keeps configuration free of keys, but ties it to workstation setup; prefer the `AWS_PROFILE` environment variable. |
| `shared_config_files`, `shared_credentials_files` | Non-default locations for the files above |
| `alias` | Second configuration of the same provider: another account or Region |
| `use_fips_endpoint` | FIPS endpoints for all services |
| `sts_region` | Region of the STS endpoint used to assume roles |
| `retry_mode`, `max_retries` | `standard` or `adaptive`; retry count, default 25 **(verify)**. Availability of the run, not confidentiality. |
| `custom_ca_bundle`, `http_proxy`, `https_proxy`, `no_proxy` | Corporate TLS inspection and egress proxies |
| `insecure` | Skips TLS verification. Never `true`. |
| `endpoints { }`, `s3_use_path_style`, `skip_credentials_validation`, `skip_metadata_api_check`, `skip_requesting_account_id`, `skip_region_validation` | Emulators only; see the last section |
| `access_key`, `secret_key`, `token` | Never in a real configuration |

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
    tags = {
      ManagedBy  = "terraform"
      Repository = "ORG_NAME/REPO_NAME"
    }
  }
}

provider "aws" {
  alias               = "audit"
  region              = "eu-west-1"
  allowed_account_ids = ["444455556666"]

  assume_role {
    role_arn = "arn:aws:iam::444455556666:role/terraform-apply"
  }
}
```

## OIDC trust policies

No stored AWS keys: the CI system presents a signed token, and the role's trust policy decides which runs may assume it. Always condition on **both** `aud` and `sub`. A trust policy with `aud` alone lets any repository or organization on that platform assume the role.

### GitHub Actions

Identity provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com` (the value `aws-actions/configure-aws-credentials` requests). The workflow needs `permissions: id-token: write`.

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

| Run | `sub` claim |
|---|---|
| Job that references an environment | `repo:ORG_NAME/REPO_NAME:environment:ENVIRONMENT_NAME` |
| Branch push, no environment | `repo:ORG_NAME/REPO_NAME:ref:refs/heads/BRANCH_NAME` |
| Tag push, no environment | `repo:ORG_NAME/REPO_NAME:ref:refs/tags/TAG_NAME` |
| Pull request, no environment | `repo:ORG_NAME/REPO_NAME:pull_request` |
| Repository created, renamed, or transferred after 2026-07-15, or opted in **(verify)** | Immutable form with numeric IDs: `repo:ORG_NAME@OWNER_ID/REPO_NAME@REPO_ID:ref:refs/heads/BRANCH_NAME` |

- Apply role: trust the `environment:` form and protect that environment with required reviewers. Plan role: trust `pull_request`.
- Avoid `StringLike` with `repo:ORG_NAME/*`. If a wildcard is needed, keep it inside one repository.
- `pull_request` covers every pull request in the repository, so the plan role must be read-only and must not read secrets.
- The older name-only `sub` can be claimed by whoever re-registers a deleted organization or repository name. Prefer the immutable form where available, or add a condition on the `repository_id` claim through a customized `sub` **(verify)**.

### HCP Terraform dynamic credentials

Identity provider URL `https://app.terraform.io` (no trailing slash), audience `aws.workload.identity`.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/app.terraform.io" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "app.terraform.io:aud": "aws.workload.identity",
        "app.terraform.io:sub": "organization:ORG_NAME:project:PROJECT_NAME:workspace:WORKSPACE_NAME:run_phase:apply"
      }
    }
  }]
}
```

| Workspace environment variable | Value |
|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true`. Required. |
| `TFC_AWS_RUN_ROLE_ARN` | Role for both phases; optional when the two below are set |
| `TFC_AWS_PLAN_ROLE_ARN` | Role for the plan phase; trust policy `sub` ends `run_phase:plan` |
| `TFC_AWS_APPLY_ROLE_ARN` | Role for the apply phase; trust policy `sub` ends `run_phase:apply` |
| `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` | Override the audience; default `aws.workload.identity` |

One role for both phases needs `StringLike` with `run_phase:*`. Never wildcard the organization segment. Background: [HCP Terraform](../teaching/terraform/08-hcp-terraform.md).

## Plan role and apply role

| | Plan role | Apply role |
|---|---|---|
| Assumed by | Any pull request run | Runs from the protected branch or environment, after approval |
| AWS permissions | Read-only (`ReadOnlyAccess` or narrower), with an explicit deny on reading secret values and decrypting data keys it does not need | Create, update, and delete for the services the configuration manages, capped by a permissions boundary |
| State | Read state; write and delete the lock object only | Read and write state and lock |
| IAM | None | May create roles only with the boundary attached (`iam:PermissionsBoundary` condition); scoped `iam:PassRole` |
| If compromised | Attacker reads configuration metadata and **the state**, which holds secrets | Attacker changes infrastructure |

A plan runs data sources and `external` programs from the pull request's code, so a plan role is not harmless. Response: [pipeline compromise runbook](../runbooks/terraform-pipeline-compromise.md). Policy evaluation and boundaries: [IAM policy evaluation cheatsheet](iam-policy-evaluation.md).

## Least-privilege state access

Apply role, S3 backend with `use_lockfile = true` and SSE-KMS:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListStatePrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::STATE_BUCKET",
      "Condition": { "StringLike": { "s3:prefix": ["PROJECT/ENV/*"] } }
    },
    {
      "Sid": "ReadWriteState",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::STATE_BUCKET/PROJECT/ENV/terraform.tfstate"
    },
    {
      "Sid": "LockFile",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::STATE_BUCKET/PROJECT/ENV/terraform.tfstate.tflock"
    },
    {
      "Sid": "StateKey",
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:eu-west-1:111122223333:key/KEY_ID"
    }
  ]
}
```

Plan role: the same, minus `s3:PutObject` in `ReadWriteState`. No role gets `s3:DeleteObject` on the state object, `s3:DeleteObjectVersion`, `s3:PutBucketVersioning`, or `s3:PutBucketPolicy`. CLI workspaces also need `s3:DeleteObject` under the workspace prefix to delete a workspace.

## Secure-by-default resource patterns

**S3 bucket** (detail in the [S3 security cheatsheet](s3-security.md))

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "BUCKET_NAME"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "data" {
  bucket     = aws_s3_bucket.data.id
  policy     = data.aws_iam_policy_document.tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.data]
}
```

**KMS key with rotation** (key policy detail in the [KMS cheatsheet](kms.md))

```hcl
resource "aws_kms_key" "data" {
  description             = "Data bucket key"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key.json   # separate administrators from users

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "data" {
  name          = "alias/data-bucket"
  target_key_id = aws_kms_key.data.key_id
}
```

**IAM role with a permissions boundary**

```hcl
resource "aws_iam_role" "app" {
  name                 = "app"
  assume_role_policy   = data.aws_iam_policy_document.app_trust.json
  permissions_boundary = "arn:aws:iam::111122223333:policy/workload-boundary"
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}
```

Write policies with `data "aws_iam_policy_document"` or `jsonencode`, not heredoc strings. Use the standalone attachment resources; the role's `inline_policy` and `managed_policy_arns` arguments are deprecated **(verify)**.

**Security group rules as separate resources**

```hcl
resource "aws_security_group" "app" {
  name   = "app"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
  description                  = "HTTPS from the load balancer"
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id = aws_security_group.app.id
  prefix_list_id    = var.s3_prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
```

One rule per resource, one CIDR or source per rule. Do not mix these with inline `ingress` and `egress` blocks or with `aws_security_group_rule` on the same group: they overwrite each other.

**RDS with a managed master password**

```hcl
resource "aws_db_instance" "app" {
  identifier                          = "app"
  engine                              = "postgres"
  instance_class                      = "db.t4g.medium"
  allocated_storage                   = 50
  username                            = "app_admin"
  manage_master_user_password         = true                 # RDS creates and rotates the secret in Secrets Manager
  master_user_secret_kms_key_id       = aws_kms_key.data.arn
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.data.arn
  publicly_accessible                 = false
  iam_database_authentication_enabled = true
  deletion_protection                 = true
  backup_retention_period             = 14
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "app-final"
  db_subnet_group_name                = var.db_subnet_group_name
  vpc_security_group_ids              = [aws_security_group.db.id]
}
```

The password never reaches Terraform. The secret's ARN is `aws_db_instance.app.master_user_secret[0].secret_arn`. `manage_master_user_password` conflicts with `password` and `password_wo`.

**Ephemeral values and write-only arguments** (Terraform 1.11 or later **(verify)**)

```hcl
ephemeral "random_password" "db" {          # hashicorp/random provider; generated each run, never stored
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name       = "app/db-password"
  kms_key_id = aws_kms_key.data.arn
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id                = aws_secretsmanager_secret.db.id
  secret_string_wo         = ephemeral.random_password.db.result
  secret_string_wo_version = 1              # increase to send a new value
}

ephemeral "aws_secretsmanager_secret_version" "db" {   # read it back without storing it
  secret_id = aws_secretsmanager_secret_version.db.secret_id
}

resource "aws_db_instance" "legacy" {
  identifier          = "legacy"
  engine              = "postgres"
  instance_class      = "db.t4g.medium"
  allocated_storage   = 50
  username            = "app_admin"
  password_wo         = ephemeral.aws_secretsmanager_secret_version.db.secret_string
  password_wo_version = aws_secretsmanager_secret_version.db.secret_string_wo_version
  storage_encrypted   = true
  skip_final_snapshot = true
}
```

A `data "aws_secretsmanager_secret_version"` block, or the plain `password` and `secret_string` arguments, copy the secret into state. Language rules: [HCL cheatsheet](terraform-hcl.md).

## Commonly flagged misconfigurations

| Finding | Fix in Terraform |
|---|---|
| Static credentials in the provider block or `.tfvars` | Remove `access_key` and `secret_key`; use OIDC or `assume_role` |
| S3 bucket can be made public | `aws_s3_bucket_public_access_block` with all four `true`; `aws_s3_account_public_access_block` for the account |
| S3 bucket without versioning or with default encryption only | `aws_s3_bucket_versioning`; `aws_s3_bucket_server_side_encryption_configuration` with `aws:kms` |
| S3 allows plain HTTP | Bucket policy denying `aws:SecureTransport = false` |
| Security group open to `0.0.0.0/0` on 22 or 3389 | `referenced_security_group_id` or a narrow `cidr_ipv4`; use Session Manager instead of an open port |
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
| Critical resource deletable by a bad plan | `lifecycle { prevent_destroy = true }` plus the service's own deletion protection |
| Module pulled from a moving reference | Registry `version`, or Git `?ref=COMMIT_SHA`; commit `.terraform.lock.hcl` |

Scanner rule IDs, AWS Config rule names, and Security Hub control IDs change; map them in [control-mappings/services/iac-terraform.md](../control-mappings/services/iac-terraform.md) rather than here.

## Local emulator (floci): lab only

The labs point the provider at [floci](../labs/README.md), a local AWS emulator. This is the provider block from `labs/_template/providers.tf`:

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # One entry per AWS service the lab uses. A service without an entry is
  # sent to real AWS and fails with the fake credentials.
  endpoints {
    s3  = var.floci_endpoint
    sts = var.floci_endpoint
  }
}
```

**Warning: none of these settings belong in a configuration that targets real AWS.**

| Setting | Why it is unsafe outside a lab |
|---|---|
| `access_key`, `secret_key` | Static credentials in source. Real ones would be committed and copied into plan files. |
| `skip_credentials_validation` | The provider no longer checks with STS that the credentials work |
| `skip_requesting_account_id` | No account ID lookup, so `allowed_account_ids` cannot protect you and some ARNs are built with an empty account |
| `skip_metadata_api_check` | Disables the instance metadata credential source |
| `s3_use_path_style` | Only needed where buckets have no DNS names |
| `endpoints` | Redirects API calls, with their signed requests and payloads, to whatever host is named |

The emulator does not enforce IAM by default, so a lab that applies cleanly proves nothing about permissions. Start real configurations from the patterns above.
