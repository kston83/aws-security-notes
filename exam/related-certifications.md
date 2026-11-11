# Related AWS certifications

> **Last reviewed:** 2026-11-10

Security content appears in every AWS certification. This page shows where each exam touches security and which notes in this repo cover it. Domain weights other than SCS-C03 are from memory of the published guides; confirm against the [current exam guides](https://docs.aws.amazon.com/aws-certification/latest/examguides/) before planning around them **(verify)**.

## Coverage map

| Certification | Security-relevant domain | Weight | Depth expected | Notes to read |
|---|---|---|---|---|
| Cloud Practitioner (CLF-C02) | Security and Compliance | 30% | Recognize services and the shared responsibility model | [services at a glance](../cheatsheets/security-services-at-a-glance.md), "Why this matters" and "Mental model" sections of each teaching note |
| Solutions Architect – Associate (SAA-C03) | Design Secure Architectures | 30% | Choose the right control for a requirement | [teaching/04](../teaching/04-identity-and-access-management.md), [teaching/05](../teaching/05-data-protection.md), [network cheatsheet](../cheatsheets/network-security.md) |
| Developer – Associate (DVA-C02) | Security | 26% | Application auth, encryption in code, secrets | [teaching/04](../teaching/04-identity-and-access-management.md#task-41-authentication), [KMS cheatsheet](../cheatsheets/kms.md), [teaching/05](../teaching/05-data-protection.md#secrets) |
| CloudOps Engineer – Associate (SOA-C03) | Security and Compliance | 16% | Operate and troubleshoot controls | [teaching/01](../teaching/01-detection.md), [teaching/06](../teaching/06-security-foundations-and-governance.md#task-63-evaluate-compliance), [CLI one-liners](../cheatsheets/cli-oneliners.md) |
| Solutions Architect – Professional (SAP-C02) | Spread across all domains, heaviest in Design Solutions for Organizational Complexity | n/a | Multi-account design and trade-offs | [teaching/06](../teaching/06-security-foundations-and-governance.md), [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md), [policy evaluation](../cheatsheets/iam-policy-evaluation.md) |
| DevOps Engineer – Professional (DOP-C02) | Security and Compliance; Incident and Event Response; Monitoring and Logging | 17%; 14%; 15% | Automate controls and response | [teaching/02](../teaching/02-incident-response.md#automated-response), [teaching/06](../teaching/06-security-foundations-and-governance.md#task-62-deployment) |
| Advanced Networking – Specialty (ANS-C01) | Network Security, Compliance, and Governance | 24% | Deep network controls and inspection architectures | [teaching/03](../teaching/03-infrastructure-security.md#task-33-network), [network cheatsheet](../cheatsheets/network-security.md) |

## What each exam adds beyond SCS

Topics you need for the other exam that the security notes cover only lightly:

| Certification | Gaps relative to this repo |
|---|---|
| SAA-C03 | Resilience, performance, and cost domains; database and storage selection |
| DVA-C02 | SDK usage, Cognito token flows in application code, CI/CD mechanics, envelope encryption with the AWS Encryption SDK in practice |
| SOA-C03 | CloudWatch operations, Systems Manager fleet operations, backup and restore mechanics |
| SAP-C02 | Migration strategy, hybrid DNS, cost governance, cross-Region architecture |
| DOP-C02 | Pipeline design, deployment strategies, CloudFormation depth |
| ANS-C01 | BGP, Direct Connect design, Transit Gateway routing, hybrid DNS, load balancer internals |

## Suggested order for a security practitioner

1. **SAA-C03** if you lack broad AWS architecture experience. SCS assumes it.
2. **SCS-C03**, the core credential for this role.
3. **ANS-C01** if you own network security architecture, or **DOP-C02** if you own security automation and pipelines.
4. **SAP-C02** when you start designing multi-account landing zones.

## Non-AWS frameworks that pair with these notes

| Framework | Where it shows up here |
|---|---|
| NIST SP 800-53 Rev. 5 | [control-mappings/](../control-mappings/README.md) |
| NIST SP 800-61 (incident handling) | Structure of every [runbook](../runbooks/README.md) |
| CIS AWS Foundations Benchmark | Referenced as Security Hub standard in [teaching/06](../teaching/06-security-foundations-and-governance.md#task-63-evaluate-compliance) |
| OWASP Top 10 and OWASP Top 10 for LLM Applications | [teaching/03](../teaching/03-infrastructure-security.md) |
| MITRE ATT&CK (Cloud matrix) | Tactic labels in [GuardDuty triage](../runbooks/guardduty-finding-triage.md) |
