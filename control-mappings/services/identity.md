# Control impact: identity services

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching note:** [Domain 4](../../teaching/04-identity-and-access-management.md)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

## IAM

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Root user has MFA; no root access keys | IA-2(1), AC-6(5), AC-2 | I | Single-factor path to unrestricted access; unattributable use | Account summary; credential report | `root-account-mfa-enabled`, `iam-root-access-key-check` (IAM.4, IAM.9) |
| Root credentials removed from member accounts (centralized root access) | AC-6(5), AC-2, IA-5 | I | Each account carries a standing super-user credential to protect | Root access management state | Manual / custom |
| MFA required for console users and for sensitive actions | IA-2(1), IA-2(2) | I | Password compromise alone gives access | Credential report; policy with MFA condition | `mfa-enabled-for-iam-console-access`, `iam-user-mfa-enabled` (IAM.5) |
| No long-term access keys, or keys rotated and unused keys removed | IA-5, AC-2(3) | I | Stale credentials persist indefinitely; leaked keys remain valid | Credential report | `access-keys-rotated`, `iam-user-unused-credentials-check` (IAM.3, IAM.8) |
| Password policy | IA-5(1) | I | Weak passwords accepted for IAM users | Account password policy | `iam-password-policy` (IAM.7) |
| No policies with full administrative wildcard | AC-6, AC-6(10) | I | Excess privilege; any compromise is total | Policy documents | `iam-policy-no-statements-with-admin-access` (IAM.1) |
| Permissions attached to groups or roles, not users | AC-2, AC-3(7) | S | Access is unmanageable and reviews miss grants | IAM snapshot | `iam-user-no-policies-check` |
| Permissions boundaries on delegated role creation | AC-6, AC-5, AC-3 | I | Delegated administrators can escalate their own privileges | Role definitions; creator policy condition | Custom Config rule |
| Role trust policies scoped; external ID for third parties; OIDC `sub` conditions | AC-3, IA-9, AC-20 | I | Unintended principals, including other tenants of a vendor or any repository, can assume the role | Trust policies; Access Analyzer | Access Analyzer external access |
| Role maximum session duration set | AC-12, IA-11 | I | Long-lived sessions extend the window for stolen credentials | Role settings | Custom |
| `iam:PassRole` scoped by resource and service | AC-6, AC-3 | I | Privilege escalation by passing a powerful role to a service | Policies | Access Analyzer policy validation |

## IAM Identity Center and federation

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Workforce access federated from the IdP | IA-2, IA-4, AC-2 | I | Local IAM users multiply; leavers keep access | Identity source configuration | `iam-user-group-membership-check`, absence of IAM users |
| SCIM provisioning and deprovisioning | AC-2(1), AC-2(3) | I | Manual account lifecycle; delays in removal | Provisioning logs | Manual |
| MFA enforced at the IdP or in Identity Center | IA-2(1), IA-2(2) | I | Single-factor workforce access | IdP policy; Identity Center MFA settings | Manual |
| Permission sets per job function, managed as code | AC-3(7), AC-6, CM-3 | I | Ad hoc permissions; no change control over access | Repository; assignments | Manual |
| Session attributes passed for ABAC | AC-3(13), AC-16 | I | Access decisions cannot use user attributes; more roles needed | Attribute mapping | Manual |
| Session duration limits | AC-12, IA-11 | I | Long unattended sessions | Permission set settings | Manual |
| Identity Center events in CloudTrail | AC-2(4), AU-2 | E | No record of assignments and sign-ins | CloudTrail | `cloudtrail-enabled` |

## Organizations policies

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| SCP protecting security services and logging | AC-6(1), AU-9, CM-5 | I | Any account administrator can disable detection and logging | SCP text and attachments | Custom; Control Tower mandatory controls |
| SCP restricting Regions | CM-7, AC-3 | I | Resources created in unmonitored Regions | SCP text | Control Tower Region deny |
| SCP denying member account root actions | AC-6(5), AC-3 | I | Root usable in every account | SCP text | Custom |
| RCP identity perimeter (`aws:PrincipalOrgID`) | AC-3, AC-4, AC-20, AC-21 | I | A single permissive resource policy exposes data outside the organization | RCP text; Access Analyzer | Access Analyzer external access |
| SCP resource perimeter (`aws:ResourceOrgID`) | AC-4, SC-7(10) | I | Insiders or stolen credentials can move data to external resources | SCP text | Custom |
| Declarative policies for EC2 (block public AMIs and snapshots, IMDS defaults, VPC BPA) | CM-6, AC-22, SC-7 | I | Baseline settings can be changed per account | Policy and account status report | `ebs-snapshot-public-restorable-check` |
| Tag policies | CM-8, AC-16 | S | Inconsistent tags weaken inventory and ABAC | Tag policy compliance report | `required-tags` |

## IAM Access Analyzer

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Organization-level external access analyzer in every Region | AC-3, AC-6, AC-21, CA-7 | S, E | Unintended external sharing goes unnoticed | Findings and their resolution history | `iam-external-access-analyzer-enabled` (IAM.28) |
| Unused access analyzer | AC-2(3), AC-6(7) | S, E | Unused privileges and credentials accumulate | Findings | Manual |
| Custom policy checks in pipelines | CM-4, AC-6, SA-11 | S | Over-permissive policies reach production | Pipeline results | Pipeline gate |

## Cognito and application identity

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| User pool password policy, MFA, compromised-credential protection | IA-8, IA-5(1), IA-2 | I | Customer accounts taken over through weak or reused passwords | User pool configuration | `cognito-user-pool-advanced-security-enabled` |
| Identity pool: no unauthenticated role, or a minimal one | AC-3, AC-6, AC-14 | I | Anonymous users obtain AWS credentials with real permissions | Identity pool roles | Custom |
| Verified Permissions policies for application authorization | AC-3, AC-24 | I | Authorization logic scattered in code and unreviewable | Policy store | Manual |

## IAM Roles Anywhere

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Trust anchor from a controlled CA; trust policy conditions on certificate attributes | IA-3, IA-5(2), IA-9 | I | Any certificate from the CA can assume the role; or long-term keys are used off-AWS | Trust anchors, profiles, trust policy | Manual |
| Certificate revocation enforced | IA-5, SC-17 | I | Compromised device certificates remain usable | CRL configuration | Manual |
