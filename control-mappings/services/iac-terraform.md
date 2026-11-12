# Control impact: infrastructure as code with Terraform

> **Last reviewed:** 2026-11-11 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching notes:** [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [Domain 6](../../teaching/06-security-foundations-and-governance.md#task-62-deployment)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

Rows cover the Terraform delivery path itself; the AWS resources it creates are mapped in the other service files. "Pipeline check" means a CI step that fails the run.

## Source control and change review

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Terraform configuration for every environment held in version control | CM-2, CM-3, SA-10, CP-10 | I | No reviewable baseline; environments rebuilt from memory | Repository history | Manual |
| Default branch protected: pull request required, approval by someone other than the author, no force push | CM-3, CM-5, AC-5, SA-10 | I | One person can change production infrastructure unreviewed | Branch protection settings; pull request records | Manual |
| Plan output attached to every pull request and reviewed before merge | CM-3, CM-4 | I, E | Reviewers approve code without seeing what it will create, change, or destroy | Plan output on the pull request | Pipeline check |
| Apply runs the saved plan file that was reviewed, not a fresh plan | CM-3, CM-4, SI-7 | I | What is applied can differ from what was approved | Pipeline logs; plan artifact digest | Pipeline check |
| Pipeline definition, backend, and provider configuration files require owner review | CM-5, AC-5, AC-6 | I | A pull request can rewrite the pipeline to skip checks or print credentials | Code owner rules; pull request records | Manual |
| State files, saved plans, and secret-bearing `.tfvars` files excluded from the repository and blocked by secret scanning | IA-5(7), SA-11 | I | Secrets and full state readable by everyone with repository access, permanently in history | `.gitignore`; scan results | Pipeline check |

## State storage and locking

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Remote backend for all state; no local state on workstations | CM-2, CP-9, SC-28 | I | State lost with a laptop or copied without control | Backend blocks; bucket inventory | Pipeline check |
| State bucket Block Public Access enabled, all four settings | AC-3, AC-22 | I | State and the secrets in it readable anonymously | Bucket configuration | `s3-bucket-level-public-access-prohibited` |
| State bucket encrypted with a customer managed KMS key | SC-28, SC-28(1), SC-12, AC-3 | I | No key policy as a second access control; no per-use decrypt record | Bucket encryption setting; key policy | `s3-default-encryption-kms` |
| State bucket policy denies requests without TLS | SC-8, SC-8(1) | I | State readable in transit | Bucket policy | `s3-bucket-ssl-requests-only` |
| State bucket versioning enabled with noncurrent versions retained | CP-9, CP-10, SI-7 | I | A corrupt or tampered state cannot be rolled back | Bucket versioning and lifecycle configuration | `s3-bucket-versioning-enabled` |
| Bucket deletion, versioning suspension, and version deletion denied except to a break-glass role | CM-5, AC-3, CP-9 | I | State history destroyed by mistake or to hide tampering | Bucket policy or SCP | Custom |
| State locking enabled (`use_lockfile`) and `-lock=false` absent from write operations | CM-3, SI-7 | I | Concurrent applies corrupt state or overwrite each other | Backend block; pipeline definition | Pipeline check |
| One state per environment and account, with IAM access scoped to the state key prefix | AC-3, AC-5, AC-6 | I | A pipeline for one workload reads or rewrites another's state | IAM policies; bucket key layout | Access Analyzer policy checks |
| CloudTrail data events recorded for the state bucket | AU-2, AU-12, AC-6(9) | I, E | Reads of state leave no record | Trail event selectors | `cloudtrail-s3-dataevents-enabled` |
| Secrets kept out of state with service-managed passwords, ephemeral resources, and write-only arguments | IA-5, IA-5(7), SC-28 | I | Passwords and keys stored in plain text in every state version | State inspection; module code | Pipeline check |
| State restore from a previous version rehearsed | CP-9(1), CP-10, CP-4 | S, E | Recovery attempted for the first time during an incident | Exercise record; [runbook](../../runbooks/terraform-state-lock-and-corruption.md) | Manual |

## Deployment credentials

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| No IAM user access keys for Terraform; pipelines obtain credentials by OIDC federation | IA-5, IA-5(7), IA-9 | I | Long-lived keys in CI variables and on workstations | IAM credential report; identity provider list | Custom |
| Apply role assumable only through OIDC with a repository and branch or environment condition | IA-9, AC-3, AC-6, CM-5 | I | Any repository or branch on the CI service can deploy | Role trust policy | Custom |
| Separate plan role (read-only, no access to secret values) and apply role | AC-5, AC-6, AC-6(2) | I | Unreviewed pull request code runs with write access or reads secrets through a data source | Role policies; pipeline definition | Custom |
| Permissions boundary on deployment roles, required on every role they create | AC-6, AC-3, CM-5 | I | The deployment role creates an administrator role and escalates | Role and boundary policies | Custom |
| SCP denies deployment roles changing their own boundary, trust policy, the OIDC provider, and security services | AC-6(1), AC-3, CM-5 | I | A compromised pipeline removes its own limits and the monitoring | SCP text | Manual |
| Production write access held only by the apply role; human access read-only with break-glass | CM-5, CM-3, AC-6(5) | I | Changes made by hand outside review | Permission set assignments; CloudTrail | Custom rule on non-pipeline changes |
| `allowed_account_ids` set on every AWS provider block | CM-3 | S | A run with the wrong credentials changes the wrong account | Provider blocks | Pipeline check |
| Role session name and source identity carry the pipeline run identifier | AU-3, AU-3(1), AC-6(9) | I, E | API calls cannot be tied to a run or commit | CloudTrail records | Manual |

## Providers and modules (supply chain)

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| `required_version` and `required_providers` with source and version constraints in every root module | CM-2, SA-10, SR-3 | I | Provider or CLI version changes between runs without review | Configuration | Pipeline check |
| Dependency lock file committed and verified in CI with `-lockfile=readonly` | SI-7, SI-7(1), SR-11 | I | A substituted or altered provider binary runs with deployment credentials | `.terraform.lock.hcl` history; init logs | Pipeline check |
| Modules pinned to an exact version or a full commit SHA | CM-2, SA-10, SR-3, SI-7 | I | A moved tag or new release inserts resources nobody reviewed | Module source arguments | Pipeline check |
| Providers and modules installed only from a private registry or approved mirror | SR-3, CM-7(5) | I | Typo-squatted or unvetted dependencies installed from the public internet | CLI configuration; runner egress rules | Pipeline check |
| Terraform CLI installed in the runner image from a release with verified signature and checksum | CM-14, SI-7, SR-11 | I | A tampered binary holds every deployment credential | Image build logs | Pipeline check |

## Pre-deployment checks

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| `terraform fmt -check` and `terraform validate` on every pull request | SA-11, CM-3(2) | I | Invalid configuration reaches the plan or apply stage | Pipeline logs | Pipeline check |
| Static analysis of configuration or plan (Checkov, Trivy) blocks merge on failed rules | SA-11, SA-11(1), RA-5, CM-6 | I, E | Known misconfigurations deployed and found only afterward | Scan reports | Pipeline check |
| Policy as code evaluated against the plan (OPA, Sentinel) at a mandatory level | CM-4, CM-6, CM-7 | I | Organization rules depend on reviewers noticing | Policy results per run | Pipeline check |
| Custom conditions (variable validation, preconditions, postconditions) in shared modules | CM-6, SI-10 | I | Modules accept insecure inputs silently | Module code | Pipeline check |
| `terraform test` suites for shared modules run in CI | SA-11, CM-3(2), CM-4 | I, E | Module changes break security properties unnoticed | Test results | Pipeline check |
| Approval by a second person required before a production apply | CM-3, AC-5, CM-5 | I | The author of a change also authorizes it | Environment protection rules; approval records | Manual |
| `prevent_destroy` on stateful and security resources, with a pipeline check on planned deletions | CM-3, CM-4 | S | A refactor or typo destroys a database, key, or log bucket | Configuration; plan checks | Pipeline check |

## Drift and reconciliation

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Scheduled refresh-only plan per state with an alert on detected drift | CM-2(2), CM-3, CM-6, CA-7 | I, E | Manual changes persist unnoticed until the next apply reverts or builds on them | Scheduled run history; alerts | Pipeline check |
| Alert on write API calls in production from principals other than the apply role | CM-3, CM-5, AU-6, SI-4 | I | Out-of-band changes found only by chance | EventBridge rule or query; alert history | Custom |
| AWS Config rules evaluate deployed resources independently of Terraform | CA-7, CM-6, CA-2 | I, E | Compliance claims rest on the tool that made the change | Config compliance history | Config |
| `default_tags` on every provider naming owner, repository, and environment | CM-8, PM-5 | S | Resources cannot be traced to the code that manages them | Tag compliance | `required-tags` |
