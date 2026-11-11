# Control impact: compute services

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching note:** [Domain 3](../../teaching/03-infrastructure-security.md#task-32-compute)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

On EC2 you own the guest operating system, so SI-2, CM-6, CM-7, and SI-3 at the host level are yours. On Lambda and Fargate, AWS patches the runtime host and you inherit that part.

## EC2

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| IMDSv2 required | AC-3, AC-6, SC-7, IA-5 | I | SSRF or a misconfigured proxy yields the instance role's credentials | Instance metadata options; account default | `ec2-imdsv2-check` (EC2.8) |
| Instance profile with least-privilege role; no keys on disk | AC-6, IA-5, IA-9, IA-5(7) | I | Long-term keys on hosts; a compromised host has broad AWS access | Role policies | `ec2-instance-profile-attached`, `iam-policy-no-statements-with-admin-access` |
| Instances launched from hardened, approved AMIs | CM-2, CM-6, CM-7, CM-7(5), SR-3 | I | Unknown or unhardened images in production | Allowed AMIs setting; AMI inventory | `approved-amis-by-id`, `approved-amis-by-tag` |
| Image Builder pipeline rebuilds and tests images on schedule | CM-2, SI-2, CM-3, SA-10 | I | Images drift out of date; hardening is manual | Pipeline history | Manual |
| AMIs and snapshots not public | AC-3, AC-22 | I | Image contents, including any embedded secrets, public | Image attributes; block public access | `ebs-snapshot-public-restorable-check` |
| No public IP; no direct inbound management ports | SC-7, AC-17, CM-7 | I | Host exposed to the internet | Instance and security group attributes | `ec2-instance-no-public-ip`, `restricted-ssh` |
| Termination protection and detailed monitoring where required | CP-10, SI-4 | S | Accidental loss; coarse metrics | Instance attributes | `ec2-instance-detailed-monitoring-enabled` |
| Stopped instances removed after a period | CM-8, SI-2 | S | Unpatched, forgotten instances restart later | Instance state | `ec2-stopped-instance` |

## Systems Manager

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| All instances managed by Systems Manager | CM-8, CM-6, SI-2, RA-5(5) | I | Instances invisible to inventory, patching, and scanning | Managed instance list | `ec2-instance-managed-by-systems-manager` (SSM.1) |
| Patch Manager baselines and scheduled patching | SI-2, SI-2(2), CM-3 | I | Known vulnerabilities remain exploitable | Patch compliance | `ec2-managedinstance-patch-compliance-status-check` (SSM.2) |
| State Manager associations enforce baseline | CM-6, CM-6(1), CM-2 | I | Configuration drifts after launch | Association compliance | `ec2-managedinstance-association-compliance-status-check` (SSM.3) |
| Session Manager for administrative access, with IAM and MFA | AC-17, MA-4, IA-2(1), AC-3, AC-6 | I | SSH keys and open ports; access not tied to identity | IAM policies; absence of port 22/3389 rules | `restricted-ssh` |
| Session logging to S3 or CloudWatch Logs, encrypted | AC-17(1), AU-2, AU-12, AU-14, MA-4(1) | I, E | No record of what administrators did on hosts | Session preferences; logs | Manual |
| Inventory collection | CM-8, CM-8(1), CM-7(5) | E | Installed software unknown | Inventory data | Manual |
| Automation runbooks for response and remediation | IR-4(1), SI-2, CM-6(1) | S | Response and remediation manual and inconsistent | Runbook definitions; execution history | Manual |
| SSM documents not public | AC-3, AC-22 | I | Operational procedures and embedded details exposed | Document permissions | `ssm-document-not-public` (SSM.4) |

## Inspector

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| EC2 scanning | RA-5, RA-5(2), SI-2 | I | Host vulnerabilities unknown | Coverage; findings | `inspector-ec2-scan-enabled` |
| ECR enhanced scanning, on push and continuous | RA-5, SI-2, SR-3, SA-11 | I | Vulnerable images deployed and never re-evaluated | Repository scan configuration | `inspector-ecr-scan-enabled`, `ecr-private-image-scanning-enabled` |
| Lambda standard and code scanning | RA-5, SA-11, SA-11(1) | I | Vulnerable dependencies and code flaws in functions | Coverage; findings | `inspector-lambda-standard-scan-enabled`, `inspector-lambda-code-scan-enabled` |
| Network reachability findings reviewed | RA-5, SC-7, CM-7 | S | Unintended exposure unnoticed | Findings | Manual |
| SBOM export | SR-3, SR-4, CM-8 | E | No component inventory for supply chain questions | Exported SBOMs | Manual |
| Findings to Security Hub and ticketing with SLAs | SI-2, RA-5, CA-5 | S | Findings without remediation tracking | Integration; ticket history | Manual |

## Containers

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| ECR repositories private; immutable tags | AC-3, CM-5, SI-7 | I | Images public or silently replaced | Repository settings | `ecr-private-tag-immutability-enabled` |
| Image signing and verification at deploy | SI-7, CM-14, SR-4, SR-11 | I | Unverified images run in production | Signing profile; admission policy | Manual |
| ECS task role separate from execution role, least privilege | AC-6, IA-9 | I | Application holds agent permissions or vice versa | Task definitions | Custom |
| ECS tasks non-privileged, read-only root, no host network | AC-6, CM-7, SC-39 | I | Container escape affects the host | Task definitions | `ecs-containers-nonprivileged`, `ecs-containers-readonly-access`, `ecs-task-definition-user-for-host-mode-check` |
| Secrets injected from Secrets Manager, not plain environment variables | IA-5(7), SC-28 | I | Secrets visible in task definitions and consoles | Task definitions | `ecs-no-environment-secrets` |
| EKS private endpoint or restricted public access | SC-7, AC-3 | I | Cluster API exposed to the internet | Cluster configuration | `eks-endpoint-no-public-access` |
| EKS secrets envelope encryption with KMS | SC-28, SC-28(1), SC-12 | I | Kubernetes secrets stored without organizational key control | Cluster configuration | `eks-secrets-encrypted` |
| EKS control plane audit logging | AU-2, AU-12 | E | No record of Kubernetes API activity | Cluster logging | `eks-cluster-logging-enabled` |
| EKS Pod Identity or IRSA, not node role | AC-6, IA-9 | I | Every pod inherits the node's permissions | Service account associations | Manual |
| GuardDuty Runtime Monitoring and EKS Protection | SI-4, SI-3, SI-4(23) | I | Runtime compromise undetected | Feature status | `guardduty-eks-protection-runtime-enabled` |

## Lambda

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Resource policy not public; scoped with `aws:SourceArn` | AC-3, AC-6 | I | Anyone, or any resource of a service, can invoke the function | Function policy | `lambda-function-public-access-prohibited` (Lambda.1) |
| Execution role least privilege, one per function | AC-6, IA-9 | I | One compromised function reaches unrelated resources | Role policies | Access Analyzer unused access |
| Supported runtime | SI-2, SA-22 | I | Runtime no longer receives security patches | Function configuration | `lambda-function-settings-check` (Lambda.2) |
| Code signing configuration | SI-7, CM-14, SR-11 | I | Unreviewed code deployable | Code signing configuration | Manual |
| Environment secrets in Secrets Manager; variables encrypted with customer managed key | IA-5(7), SC-28(1) | I | Secrets readable by anyone with `GetFunctionConfiguration` | Function configuration | Manual |
| In a VPC when reaching private resources | SC-7, AC-4 | I | Private resources must be exposed for the function to reach them | Function configuration | `lambda-inside-vpc` |

## Pipelines and generative AI

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Pipeline uses OIDC federation and scoped deploy roles | IA-5, IA-9, AC-6, CM-5 | I | Stored long-term keys in CI; pipeline compromise is account compromise | Trust policies | Access Analyzer |
| Static analysis, dependency, secret, and IaC scanning gates | SA-11, SA-11(1), RA-5, CM-4, SA-15 | I | Flaws found in production instead of the build | Pipeline results | Pipeline gates |
| CloudFormation Guard rules and hooks | CM-6, CM-4, SA-10 | I | Noncompliant resources deployed, found later by detective controls | Rule sets; hook results | Hook status |
| Bedrock Guardrails on applications | SI-10, AC-4, SC-7(10) | I | Prompt injection and sensitive data disclosure unmitigated | Guardrail configuration | Manual |
| Bedrock model invocation logging | AU-2, AU-12 | E | No record of prompts and responses for investigation | Logging configuration | Manual |
| Bedrock access through PrivateLink; model access restricted by IAM and SCP | SC-7, AC-3, CM-7 | I | Unapproved models used; traffic over the internet | Endpoint; policies | Manual |
