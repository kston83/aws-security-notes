# Securing Terraform on AWS

> **Last reviewed:** 2026-11-11 · **SCS-C03:** 6.2.1 · **Terraform Associate (004):** 4h, 6b, 6c · **Related:** [Domain 6](../06-security-foundations-and-governance.md#task-62-deployment), [provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md), [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md), [IaC control mappings](../../control-mappings/services/iac-terraform.md)

This note is the bridge between the AWS security notes and the Terraform notes. It is not a Terraform Associate exam domain. It covers what SCS-C03 skill 6.2.1 calls "third-party IaC" and overlaps Terraform objectives 4h (sensitive data), 6b (locking), and 6c (remote state).

## Why this matters

A Terraform pipeline that deploys to production holds, in effect, administrator access to production. It is usually the most privileged principal in the account and the least watched. An attacker who cannot touch AWS directly can still get there through a pull request, a poisoned module, a leaked state file, or a CI token. The same pipeline is also the best control you have: every change reviewed, tested, and recorded before it exists. Which of the two it is depends on how it is built.

## Mental model

**Infrastructure is changed by whoever can change any input to `terraform apply`.** There are five inputs, and each is a trust boundary.

```
  (1) CODE                      (2) PIPELINE                         (5) CREDENTIALS
  Developer --PR--> Repository --merge--> CI runner --OIDC token--> AWS STS --> plan role  (read)
                    .tf files             terraform init                        apply role (write)
                    lock file             terraform plan                            |
                    pipeline definition   terraform apply                           v
                                            |        |                          AWS APIs --> resources
                         (4) SUPPLY CHAIN   |        |   (3) STATE
              Registry or mirror <----------+        +--------> S3 bucket + KMS key
              providers, modules                                 state, lock file
```

| # | Input | Whoever controls it can | Main defenses |
|---|---|---|---|
| 1 | Code | Add or alter any resource | Branch protection, review, policy checks |
| 2 | Pipeline | Run any command with the deployment credentials | Protected pipeline definition, isolated runners, approval gates |
| 3 | State | Read every stored secret; make Terraform destroy or ignore resources | Encryption, least-privilege access, versioning, locking |
| 4 | Providers and modules | Run code on the runner; insert resources | Version pinning, lock file checksums, private registry |
| 5 | Credentials | Skip Terraform and call AWS directly | Short-lived federation, scoped trust policy, boundaries, SCPs |

Two rules follow. First, **a provider is a program**: it runs on the runner with the runner's credentials, during `plan` as well as `apply`. Second, **nothing inside the pipeline can be the last line of defense**, because whoever controls the pipeline controls its checks. The backstop has to sit in AWS: service control policies (SCPs), permissions boundaries, and AWS Config.

## Threat model

| Path | Example | What limits the damage |
|---|---|---|
| Malicious or careless change merged | A security group opened to `0.0.0.0/0`; an IAM role with `*:*` | Review of the plan, policy as code, SCP backstop |
| Plan run on untrusted code | A pull request adds an `external` data source or a new provider that reads the runner's environment during `plan` | Plan role is read-only and cannot read secrets; no plans on forks; provider allow-list |
| Pipeline definition changed | A workflow edit prints credentials or skips the approval step | Required review on pipeline files; trust policy tied to a protected branch or environment |
| State read | A database password or private key read from the state bucket | Keep secrets out of state; KMS key policy; per-prefix access |
| State written | Resource removed from state so Terraform recreates it, or outputs altered | Versioning, locking, write access for the apply role only |
| Dependency replaced | A module tag moved to a different commit; a typo-squatted provider | Lock file, pin modules to a commit, private registry |
| Credentials stolen | A static access key in a CI variable or on a laptop | No static keys; OIDC with short sessions |
| Change outside Terraform | Console edit that the next apply silently reverts, or that nobody notices | Drift detection, CloudTrail attribution, Config |

Responding to these: [pipeline compromise](../../runbooks/terraform-pipeline-compromise.md), [state exposure](../../runbooks/terraform-state-exposure.md), [state lock and corruption](../../runbooks/terraform-state-lock-and-corruption.md), [unexpected drift](../../runbooks/terraform-unexpected-drift.md).

## Authenticating Terraform to AWS

**No static access keys.** Not in provider blocks, not in `.tfvars`, not in CI variables. The provider reads credentials from, in order: provider arguments, environment variables, shared credentials and config files, container credentials, instance profile. Give it temporary credentials through one of the later sources and leave the provider block free of secrets. Background on the Security Token Service (STS): [temporary credentials](../04-identity-and-access-management.md#temporary-credentials).

### OIDC federation from CI

**OpenID Connect (OIDC) federation** lets the CI system sign a short-lived token describing the job; AWS STS exchanges it for role credentials through `AssumeRoleWithWebIdentity`. Nothing long-lived is stored anywhere. You register the CI system as an IAM OIDC identity provider, then write a role trust policy that checks two claims:

- **`aud`** (audience): who the token was minted for.
- **`sub`** (subject): which repository, branch, environment, or workspace the job belongs to.

| CI system | Issuer | `aud` to require | `sub` format |
|---|---|---|---|
| GitHub Actions | `token.actions.githubusercontent.com` | `sts.amazonaws.com` (set by the AWS credentials action) | `repo:ORG_NAME/REPO_NAME:ref:refs/heads/BRANCH`, or `repo:ORG_NAME/REPO_NAME:environment:ENV_NAME` when the job uses an environment, or `repo:ORG_NAME/REPO_NAME:pull_request`. Newer repositories use a form that also carries owner and repository IDs **(verify)** |
| GitLab CI/CD | Your GitLab URL | The value you set in the job's `id_tokens` block | `project_path:GROUP/PROJECT:ref_type:branch:ref:BRANCH` **(verify)** |
| HCP Terraform dynamic provider credentials | `app.terraform.io` | `aws.workload.identity` | `organization:ORG_NAME:project:PROJECT_NAME:workspace:WORKSPACE_NAME:run_phase:RUN_PHASE`, where the phase is `plan` or `apply` |

Trust policy for a GitHub Actions apply role, usable only from the `production` environment of one repository:

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

A trust policy with no `sub` condition, or with `repo:ORG_NAME/*`, trusts every repository and every branch that the issuer serves for that organization. For HCP Terraform, always check at least the audience and the organization name; without the organization, any HCP Terraform customer could assume the role. HCP Terraform is switched on per workspace with `TFC_AWS_PROVIDER_AUTH=true` and `TFC_AWS_RUN_ROLE_ARN` (or `TFC_AWS_PLAN_ROLE_ARN` and `TFC_AWS_APPLY_ROLE_ARN` for separate roles). More in [HCP Terraform](08-hcp-terraform.md).

### Plan role and apply role

| Role | Trusted for | Permissions |
|---|---|---|
| **Plan** | Pull request jobs, any branch | Read-only on the services managed; read on the state object; read, write, and delete on the lock file only. No `secretsmanager:GetSecretValue`, no `kms:Decrypt` on data keys, no `iam:PassRole`. |
| **Apply** | The protected branch or deployment environment only | Write on the services managed; read and write on state |

The split matters because `plan` runs code from the pull request (provider plugins, data sources) before any human has reviewed it. A plan role that can read secrets hands them to anyone who can open a pull request.

### Fencing the deployment role

- **Least privilege** for what the configuration manages, not `AdministratorAccess`. Practice: [lab 04](../../labs/04-iam-least-privilege/README.md).
- **Permissions boundary** on the deployment role, and a condition that every role it creates carries the same boundary (`iam:PermissionsBoundary`). Otherwise a role that can create roles can create an administrator.
- **SCPs** deny what no pipeline should do: remove its own boundary, edit the OIDC provider or its own trust policy, stop CloudTrail or Config, leave approved Regions. Patterns: [SCP patterns](../../cheatsheets/org-policies-scp-rcp.md#scp-patterns).
- **Hub and spoke:** the pipeline federates into one role in a tooling account, then uses `assume_role` in the provider to reach a deployment role in each target account. The target role's trust policy names the hub role and can require an `external_id`.
- **`allowed_account_ids`** in the provider stops an apply against the wrong account when credentials are mixed up.

```hcl
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["444455556666"]

  assume_role {
    role_arn     = "arn:aws:iam::444455556666:role/terraform-apply"
    session_name = "tf-apply-PIPELINE_RUN_ID"
    external_id  = "EXTERNAL_ID"
    duration     = "30m"
  }
}
```

## Protecting state

**State is sensitive** for two reasons. It stores every attribute of every managed resource in plain text, including generated passwords, private keys, and anything marked `sensitive`. And Terraform trusts it: edit state and you change what the next apply creates, replaces, or destroys. Read access is a confidentiality problem; write access is an integrity problem. Mechanics of state and backends are in [state management](06-state-management.md).

Hardening an S3 backend:

| Control | Setting | Why |
|---|---|---|
| No public access | Block Public Access, all four settings, on bucket and account | State must never be readable anonymously |
| Encryption at rest | SSE-KMS with a customer managed key; `encrypt = true` and `kms_key_id` in the backend block | The key policy becomes a second access control, and each decrypt is logged |
| Encryption in transit | Bucket policy denying requests where `aws:SecureTransport` is `false` | Stops plain HTTP |
| Recovery | Versioning on; lifecycle rule that keeps noncurrent versions for a set period | Roll back a corrupt or tampered state |
| Locking | `use_lockfile = true`: Terraform writes `KEY.tflock` beside the state object. The older `dynamodb_table` locking is deprecated **(verify)** | Two applies at once corrupt state |
| Least privilege | Per role: `s3:ListBucket` on the bucket, `s3:GetObject` and `s3:PutObject` on its own state key, plus `s3:DeleteObject` on its own `.tflock` key; `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` on the key | A pipeline for one workload cannot read another's state |
| Deletion guard | Deny `s3:DeleteBucket`, `s3:PutBucketVersioning`, and `s3:DeleteObjectVersion` to everyone but a break-glass role | Versions are the backup |
| Audit trail | CloudTrail data events on the bucket; server access logging if you want a second source | Shows who read state, not only who changed it |

General S3 and KMS detail: [S3 baseline for a sensitive bucket](../../cheatsheets/s3-security.md#baseline-for-a-sensitive-bucket), [KMS key policy](../../cheatsheets/kms.md#key-policy). Practice: [lab 02](../../labs/02-remote-state/README.md).

**Split state by blast radius.** One state per environment and per account at least, each under its own key prefix with its own IAM scope. Keep the state bucket outside the workload account so that a compromise of the workload does not include its own blueprint. CLI workspaces are not a security boundary: every workspace shares one backend, and non-default workspaces live under `env:/WORKSPACE_NAME/` in the same bucket.

**Sharing outputs.** The `terraform_remote_state` data source needs read access to the whole state object, secrets included. To publish a few values to other teams, write them to SSM Parameter Store or use provider data sources.

**Saved plan files are sensitive too.** `terraform plan -out` writes sensitive values in clear text. Treat plan artifacts in CI like state: short retention, restricted access.

## Secrets

The goal, in order of preference: the secret never reaches Terraform; it reaches Terraform but is not stored; it is stored and the store is protected.

| Technique | How | Stored in state? |
|---|---|---|
| **Service-managed secret** | `manage_master_user_password = true` on `aws_db_instance` or `aws_rds_cluster`: RDS creates and rotates the password in Secrets Manager. State holds only the secret's ARN. | No |
| **Reference, not value** | Pass the secret's ARN or name to the consumer (ECS task definition `secrets`, a Lambda environment variable holding the ARN). The workload fetches the value at run time with its own role. | No |
| **Ephemeral resource** | `ephemeral "aws_secretsmanager_secret_version"` reads a value for the current run only. Needs Terraform 1.10 or later. | No, and not in the plan file |
| **Write-only argument** | Arguments ending in `_wo`, such as `password_wo` with `password_wo_version`. Terraform sends the value and forgets it; bump the version to send a new one. Needs Terraform 1.11 or later. | No |
| **Ephemeral variable** | `ephemeral = true` on an input variable | No |
| **Data source** | `data "aws_secretsmanager_secret_version"` | **Yes**, in plain text |
| **`sensitive = true`** | Redacts the value in CLI and UI output | **Yes**. It hides output; it does not protect storage. |

`terraform output -json` and `terraform output -raw` print sensitive values in full. A root module output cannot be ephemeral.

Never commit `terraform.tfstate`, `*.tfstate.backup`, `.terraform/`, `crash.log`, saved plan files, or any `.tfvars` file that holds secrets. Supply secret inputs through `TF_VAR_NAME` environment variables from the CI secret store, or better, through an ephemeral resource that reads them from Secrets Manager or Vault. Language detail is in [configuration, objective 4h](04-configuration.md). Practice: [lab 05](../../labs/05-kms-and-secrets/README.md).

## Supply chain

| Control | Detail |
|---|---|
| **Pin providers** | `required_providers` with an explicit `source` and a version constraint such as `~> 6.0`. Set `required_version` for Terraform itself. |
| **Commit the lock file** | `.terraform.lock.hcl` records the exact provider version and its checksums (`h1:` and `zh:`). `terraform init` fails if a downloaded package matches none of them. |
| **Verify in CI** | `terraform init -lockfile=readonly` checks against the recorded checksums and refuses to modify the file. Only a reviewed change that ran `terraform init -upgrade` should move a version. |
| **Pin modules harder** | The lock file covers **providers only**. A registry module with a version range resolves to the newest match on every `init`. Use an exact `version`, and for Git sources a full commit SHA in `?ref=`, because tags can be moved. |
| **Control the source** | A private registry (HCP Terraform or your own) or a provider network mirror, with the runner's egress limited to it. Record checksums for every platform you run with `terraform providers lock -platform=OS_ARCH`. |
| **Review upgrades** | Treat a provider or module bump as a code change: read the changelog and the module diff, and read the plan it produces. |

More on sourcing and versioning: [modules](05-modules.md).

## Guardrails before apply

Checks get stronger and slower from left to right. Run the cheap ones on every push.

| Stage | Tool | Catches |
|---|---|---|
| Syntax | `terraform fmt -check`, `terraform validate` | Malformed and internally inconsistent configuration. No credentials needed. |
| Module contracts | **Custom conditions**: variable `validation`, `precondition`, `postcondition`, `check` blocks | Bad inputs and broken assumptions, with your own error message |
| Module tests | `terraform test` with `.tftest.hcl` files (Terraform 1.6 or later). Runs with `command = plan` create nothing; the default `apply` creates real resources. | Regressions in shared modules |
| Static analysis | Scanners with built-in rule sets: Checkov, Trivy (`trivy config`), TFLint for provider-specific linting. tfsec's rules now live in Trivy, and its maintainers direct users there **(verify)**. | Known misconfigurations: public buckets, open security groups, missing encryption |
| Policy as code | Your own rules over the plan JSON (`terraform show -json PLAN_FILE`): Open Policy Agent (OPA) with Conftest; Sentinel or OPA policy sets in HCP Terraform, with advisory and mandatory enforcement levels **(verify)** | Organization rules: approved Regions, required tags, no IAM wildcards |
| Plan review | A human reads the plan attached to the pull request; approval by someone other than the author | Intent: is this the change that was asked for? |
| Apply | The pipeline applies the **saved plan file** that was reviewed | The gap between what was approved and what runs |

Scanning the plan is stronger than scanning source, because the plan has resolved variables, modules, and `count`. Practice: [lab 07](../../labs/07-tests-and-guardrails/README.md).

Where these sit among the control kinds from [Domain 6](../06-security-foundations-and-governance.md#mental-model):

| Kind | CloudFormation | Terraform |
|---|---|---|
| Proactive | CloudFormation hooks, Guard | Policy as code in the pipeline. Hooks do not see the AWS provider's direct API calls **(verify)**. |
| Preventive | SCPs, resource control policies (RCPs), declarative policies, permissions boundaries | The same. They act on the API call, whichever tool makes it. |
| Detective | Config rules, Security Hub | The same |

Pipeline checks are bypassed by anyone who can bypass the pipeline. If a requirement is "must never happen", it needs an SCP or RCP as well as a policy check.

## Drift and detection

**Drift** is a difference between real infrastructure and state. It is either an unauthorized change or an emergency fix nobody wrote back to code; you cannot tell which without looking.

- **Scheduled refresh-only plan.** Run `terraform plan -refresh-only -detailed-exitcode -lock=false` against each state on a schedule, using the plan role. Exit code `0` means no drift, `2` means drift, `1` means error. Alert on `2`. HCP Terraform has drift detection built in as health assessments **(verify)**.
- **CloudTrail attribution.** Every call Terraform makes is recorded under the apply role's session. In production, write calls from any other principal are the signal: alert on mutating events where `userIdentity.sessionContext.sessionIssuer.arn` is not the apply role. A distinct `session_name` per pipeline run ties each event to a run and a commit.
- **AWS Config as the independent check.** Terraform reports only on resources it manages and only when it runs. Config records every resource continuously, including ones created around Terraform, and evaluates rules regardless of how the resource was made. Practice: [lab 08](../../labs/08-detection-baseline/README.md).
- **`prevent_destroy`.** `lifecycle { prevent_destroy = true }` makes any plan that would destroy the resource fail. Limits: it disappears if the whole `resource` block is deleted, it does nothing about deletion through the console or API, and anyone who can edit the code can remove it. Pair it with service-side protection: RDS deletion protection, S3 versioning or Object Lock, KMS deletion waiting periods, and SCPs.

Reconcile drift through code: either revert the change by applying, or adopt it by editing the configuration. Practice: [lab 06](../../labs/06-drift-and-import/README.md). Procedure: [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md).

## AWS provider features that help

| Feature | Security use |
|---|---|
| `allowed_account_ids`, `forbidden_account_ids` | Refuse to run against the wrong account. The two cannot be combined. |
| `assume_role` with `session_name`, `external_id`, `source_identity`, `duration`, `policy` | Attributable, short, optionally down-scoped sessions. Several blocks chain roles in order. |
| `assume_role_with_web_identity` | Exchange an OIDC token directly, without a helper action |
| `default_tags` | Stamp every resource with owner, repository, and environment for inventory and for tag-based access control. Not applied to `aws_autoscaling_group` **(verify)**. |
| `ignore_tags` | Stop Terraform fighting tags that other systems add |
| Provider `alias` | One configuration, several accounts or Regions, each with its own role |

The full argument list with examples is in the [provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md).

## Worked examples

**1. A GitHub Actions pipeline deploys to production with an access key stored as a repository secret. Remove the key.**
Create an IAM OIDC provider for GitHub. Create an apply role whose trust policy requires `aud` equal to `sts.amazonaws.com` and `sub` equal to the repository's `production` environment. Protect that environment with required reviewers. Grant the workflow `id-token: write`. Create a second, read-only plan role trusted for pull requests. Delete the access key and the IAM user, then confirm in CloudTrail that only role sessions remain.

**2. A database password must not appear in the state file.**
Set `manage_master_user_password = true` and let RDS own the secret; the application reads it from Secrets Manager by ARN. If the password must come from you, pass it through `password_wo` from an ephemeral resource. Marking a variable `sensitive` does not meet the requirement, and neither does a `data` source.

**3. Developers should see the plan for every pull request, but a pull request must not be able to change production.**
Pull request jobs assume the plan role: read-only, no secret access, and write access in the state bucket to the lock file only. The apply role trusts only the protected branch or environment, so workflow edits in a pull request cannot reach it. Pipeline files need owner review. Plans do not run for forks.

**4. Auditors ask how you know production matches the code.**
Three independent answers. A scheduled refresh-only plan reports no drift. A CloudTrail query shows no mutating calls outside the apply role in the period. Config conformance pack results show compliance, evaluated without reference to Terraform. Mapped to controls in [IaC control mappings](../../control-mappings/services/iac-terraform.md).

**5. A community module is updated and the next plan wants to add an IAM role nobody asked for.**
The module was referenced with a version range, so `init` picked up the new release. Pin an exact version or commit SHA, review the diff between releases, and add a policy check that fails any plan creating IAM roles outside an approved path. The lock file would not have helped: it covers providers only.

## Pitfalls and exam traps

- `sensitive = true` redacts output. The value is still in state and in saved plan files.
- A `data` source that reads a secret stores it in state. An `ephemeral` resource does not.
- The dependency lock file tracks providers, not modules.
- CLI workspaces separate state, not access. They share one backend and one set of credentials.
- `plan` is not harmless: it runs provider code and data sources with the credentials it is given.
- A read-only plan role still needs to write and delete the `.tflock` object when S3 locking is on.
- An OIDC trust policy that checks only `aud` trusts every repository on that CI service.
- `prevent_destroy` does not survive deletion of the resource block and does not stop a console delete.
- `allowed_account_ids` is a safety catch against mistakes, not an access control. IAM decides access.
- `-lock=false` is acceptable for a read-only drift check and dangerous for anything that writes.
- `terraform apply` without a saved plan re-plans, so what runs can differ from what was reviewed.
- SCPs do not apply to the management account. Do not run pipelines there.
- `default_tags` cannot be excluded for a single resource, only overridden.
- State bucket encryption stops someone with disk or cross-account bucket access. It does not stop a principal who holds both `s3:GetObject` and `kms:Decrypt`.

## Self-check

1. Name the five inputs to `terraform apply` that an attacker could target.
2. Which two token claims must an OIDC trust policy check, and what goes wrong if only one is checked?
3. Why should the plan role be unable to read secrets?
4. A variable is marked `sensitive`. Where can its value still be read?
5. What does `.terraform.lock.hcl` protect, and what does it leave unprotected?
6. Give one proactive, one preventive, and one detective control for "no public S3 buckets" in a Terraform shop.
7. Which S3 permissions does a pipeline need on its state when `use_lockfile` is on?
8. A console change was made in production during an incident. How is it found, and how is it resolved?

<details>
<summary>Answers</summary>

1. The code, the pipeline, the state, the providers and modules, and the deployment credentials.
2. `aud` and `sub`. Without `sub`, any repository or workspace on the same CI service can assume the role. Without `aud`, a token minted for another relying party is accepted.
3. `plan` executes provider plugins and data sources from unreviewed pull request code. Whatever the plan role can read, a pull request author can exfiltrate.
4. In the state file, in a saved plan file, and through `terraform output -json` or `-raw` if it feeds an output.
5. It pins provider versions and checksums, so a changed or substituted provider package fails `init`. It does not cover modules or the Terraform binary.
6. Proactive: a Checkov, Trivy, or OPA check on the plan that fails the pipeline. Preventive: account-level Block Public Access locked by an SCP, or an RCP. Detective: Config rule `s3-bucket-public-read-prohibited` **(verify)** or Access Analyzer external access findings.
7. `s3:ListBucket` on the bucket; `s3:GetObject` and `s3:PutObject` on the state key; `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on the `.tflock` key; plus KMS permissions if a customer managed key is used.
8. Found by the scheduled refresh-only plan (exit code 2), by a CloudTrail alert on write calls from a principal other than the apply role, or by Config. Resolved through code: apply to revert it, or change the configuration to adopt it, with the decision recorded on the pull request.

</details>

## Further reading

- [Terraform: S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform: Manage sensitive data](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)
- [Terraform: Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)
- [HCP Terraform: Dynamic credentials with the AWS provider](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions: OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc)
- [AWS Prescriptive Guidance: Terraform AWS Provider best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/)
- [AWS IAM: OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)
