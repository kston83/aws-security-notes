# SCS-C03 study plan

> **Last reviewed:** 2026-11-10

An eight-week plan at roughly 6–8 hours a week for someone who already works in AWS. Compress or stretch to fit; keep the order. IAM comes first because every other domain depends on reading policies fluently.

## Weekly plan

| Week | Focus | Read | Do |
|---|---|---|---|
| 1 | IAM: policy evaluation | [teaching/04](../teaching/04-identity-and-access-management.md), [policy evaluation](../cheatsheets/iam-policy-evaluation.md) | Write a permissions boundary and prove it holds with `aws iam simulate-principal-policy`. Break cross-account access three different ways and fix each. |
| 2 | IAM: authentication and federation; org policies | [teaching/04](../teaching/04-identity-and-access-management.md#task-41-authentication), [org policies](../cheatsheets/org-policies-scp-rcp.md) | Set up IAM Identity Center with a permission set. Write an SCP that denies leaving approved Regions and an RCP that enforces an org-only data perimeter on S3. |
| 3 | Data protection: KMS and encryption | [teaching/05](../teaching/05-data-protection.md), [KMS](../cheatsheets/kms.md) | Create a customer managed key, share it cross-account, use a grant, schedule deletion and cancel it. Trace each call in CloudTrail. |
| 4 | Data protection: S3, secrets, certificates | [S3 security](../cheatsheets/s3-security.md), [teaching/05](../teaching/05-data-protection.md#secrets) | Enable Object Lock in compliance mode on a test bucket. Rotate a secret with a Lambda rotation function. |
| 5 | Detection | [teaching/01](../teaching/01-detection.md), [logging sources](../cheatsheets/logging-sources.md) | Build an organization trail to a log archive account. Query it with Athena. Generate GuardDuty sample findings and route them through EventBridge. |
| 6 | Infrastructure security | [teaching/03](../teaching/03-infrastructure-security.md), [network security](../cheatsheets/network-security.md) | Deploy Network Firewall with a domain allow list. Put WAF on an ALB with a rate-based rule. Remove SSH and use Session Manager. |
| 7 | Incident response | [teaching/02](../teaching/02-incident-response.md), all [runbooks](../runbooks/README.md) | Walk the compromised credentials and compromised EC2 runbooks end to end in a sandbox. Time yourself. |
| 8 | Governance, then review | [teaching/06](../teaching/06-security-foundations-and-governance.md), [services at a glance](../cheatsheets/security-services-at-a-glance.md) | Deploy a conformance pack with auto-remediation. Take two full practice exams. Re-read the pitfalls section of every teaching note. |

## How to use the notes

- Read the teaching note, then answer its self-check questions **without** looking. Anything you miss goes on a list.
- Use cheatsheets for spaced review. Cover the right-hand column of a table and recite it.
- Do the labs. Most SCS questions describe a broken configuration and ask why. You recognize the failure faster if you have caused it yourself.

## Question technique

- **Find the constraint.** "Least operational overhead" points to a managed service or an organization-level feature. "Most cost-effective" rules out Shield Advanced, CloudHSM, and Macie-on-everything unless required. "Immediately" rules out anything that waits for a rotation or a scheduled evaluation.
- **Preventive beats detective** when the question asks to *ensure* or *prevent*. Config rules detect; SCPs, RCPs, and resource policies prevent.
- **Explicit deny always wins.** When an answer hinges on policy interaction, look for the deny first.
- **Centralized beats per-account** when the scenario mentions an organization.
- **Ordering questions:** write the incident response order on your scratch sheet at the start: contain, preserve evidence, eradicate, recover. For a compromised instance, snapshot and isolate before you terminate anything.

## Lab safety

Use a dedicated sandbox account inside an organization you control. Set a budget alarm. Shield Advanced carries a one-year commitment and CloudHSM bills hourly, so read about those rather than deploying them.
