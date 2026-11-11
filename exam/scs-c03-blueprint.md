# SCS-C03 blueprint map

> **Last reviewed:** 2026-11-10 · **Source:** [AWS Certified Security – Specialty (SCS-C03) exam guide](https://docs.aws.amazon.com/aws-certification/latest/security-specialty-03/security-specialty-03.html)

Every skill in the official exam guide, mapped to where this repo covers it. Skill wording is taken from the exam guide.

## Exam facts

| Item | Value |
|---|---|
| Exam code | SCS-C03 (replaced SCS-C02 in December 2025) |
| Questions | 65 total: 50 scored, 15 unscored and unmarked |
| Question types | Multiple choice, multiple response, ordering, matching |
| Scoring | Scaled 100–1,000, pass at 750, compensatory (no per-domain pass mark) |
| Target candidate | 3–5 years securing cloud solutions |
| Guessing | No penalty; unanswered counts as wrong |

Check duration, price, and delivery options on the [certification page](https://aws.amazon.com/certification/certified-security-specialty/) **(verify)**.

## Domain weights

| Domain | Weight | Teaching note |
|---|---|---|
| 1. Detection | 16% | [01-detection](../teaching/01-detection.md) |
| 2. Incident Response | 14% | [02-incident-response](../teaching/02-incident-response.md) |
| 3. Infrastructure Security | 18% | [03-infrastructure-security](../teaching/03-infrastructure-security.md) |
| 4. Identity and Access Management | 20% | [04-identity-and-access-management](../teaching/04-identity-and-access-management.md) |
| 5. Data Protection | 18% | [05-data-protection](../teaching/05-data-protection.md) |
| 6. Security Foundations and Governance | 14% | [06-security-foundations-and-governance](../teaching/06-security-foundations-and-governance.md) |

## Domain 1: Detection

### Task 1.1: Design and implement monitoring and alerting solutions for an AWS account or organization

| Skill | Statement | Covered in |
|---|---|---|
| 1.1.1 | Analyze workloads to determine monitoring requirements | [teaching/01](../teaching/01-detection.md#task-11-monitoring-and-alerting) |
| 1.1.2 | Design and implement workload monitoring strategies (for example, resource health checks) | [teaching/01](../teaching/01-detection.md#task-11-monitoring-and-alerting) |
| 1.1.3 | Aggregate security and monitoring events | [teaching/01](../teaching/01-detection.md#aggregation), [services at a glance](../cheatsheets/security-services-at-a-glance.md) |
| 1.1.4 | Create metrics, alerts, and dashboards to detect anomalous data and events (GuardDuty, Security Lake, Security Hub, Macie) | [teaching/01](../teaching/01-detection.md#task-11-monitoring-and-alerting), [GuardDuty triage](../runbooks/guardduty-finding-triage.md) |
| 1.1.5 | Create and manage automations for regular assessments and investigations (Config conformance packs, Security Hub, State Manager) | [teaching/01](../teaching/01-detection.md#automated-assessment), [teaching/06](../teaching/06-security-foundations-and-governance.md#task-63-evaluate-compliance) |

### Task 1.2: Design and implement logging solutions

| Skill | Statement | Covered in |
|---|---|---|
| 1.2.1 | Identify sources for log ingestion and storage based on requirements | [logging sources](../cheatsheets/logging-sources.md) |
| 1.2.2 | Configure logging for AWS services and applications (organization trail, dedicated logging account, CloudWatch agent) | [teaching/01](../teaching/01-detection.md#task-12-logging) |
| 1.2.3 | Implement log storage and log data lakes (Security Lake) and integrate with third-party tools | [teaching/01](../teaching/01-detection.md#security-lake-and-ocsf) |
| 1.2.4 | Use AWS services to analyze logs (Logs Insights, Athena, Security Hub findings) | [teaching/01](../teaching/01-detection.md#analysis), [CLI one-liners](../cheatsheets/cli-oneliners.md) |
| 1.2.5 | Normalize, parse, and correlate logs (OpenSearch Service, Lambda, Managed Grafana) | [teaching/01](../teaching/01-detection.md#analysis) |
| 1.2.6 | Choose log sources based on network design, threats, and attacks (VPC Flow Logs, transit gateway flow logs, Resolver query logs) | [logging sources](../cheatsheets/logging-sources.md#network) |

### Task 1.3: Troubleshoot security monitoring, logging, and alerting solutions

| Skill | Statement | Covered in |
|---|---|---|
| 1.3.1 | Analyze functionality, permissions, and configuration of resources (Lambda, API Gateway, health checks, CloudFront logging) | [teaching/01](../teaching/01-detection.md#task-13-troubleshooting) |
| 1.3.2 | Remediate misconfiguration (CloudWatch agent, missing logs) | [teaching/01](../teaching/01-detection.md#task-13-troubleshooting), [logging sources](../cheatsheets/logging-sources.md#why-are-my-logs-missing) |

## Domain 2: Incident Response

### Task 2.1: Design and test an incident response plan

| Skill | Statement | Covered in |
|---|---|---|
| 2.1.1 | Design and implement response plans and runbooks (OpsCenter, SageMaker AI notebooks) | [teaching/02](../teaching/02-incident-response.md#task-21-plan-and-test), [runbooks](../runbooks/README.md) |
| 2.1.2 | Configure services to be prepared for incidents (provisioning access, deploying tools, minimizing blast radius, Shield Advanced) | [teaching/02](../teaching/02-incident-response.md#preparation) |
| 2.1.3 | Recommend procedures to test and validate the plan (Fault Injection Service, Resilience Hub) | [teaching/02](../teaching/02-incident-response.md#testing-the-plan) |
| 2.1.4 | Automatically remediate incidents (Systems Manager, Automated Forensics Orchestrator, Step Functions, Application Recovery Controller, Lambda) | [teaching/02](../teaching/02-incident-response.md#automated-response) |

### Task 2.2: Respond to security events

| Skill | Statement | Covered in |
|---|---|---|
| 2.2.1 | Capture and store system and application logs as forensic artifacts | [compromised EC2](../runbooks/compromised-ec2-instance.md) |
| 2.2.2 | Search and correlate logs across applications and AWS services | [teaching/02](../teaching/02-incident-response.md#task-22-respond), [CLI one-liners](../cheatsheets/cli-oneliners.md) |
| 2.2.3 | Validate findings to assess scope and impact | [GuardDuty triage](../runbooks/guardduty-finding-triage.md) |
| 2.2.4 | Contain, eradicate, and recover (network containment, restoring backups) | All [runbooks](../runbooks/README.md) |
| 2.2.5 | Describe methods for root cause analysis (Detective) | [teaching/02](../teaching/02-incident-response.md#root-cause-analysis) |

## Domain 3: Infrastructure Security

### Task 3.1: Design, implement, and troubleshoot security controls for network edge services

| Skill | Statement | Covered in |
|---|---|---|
| 3.1.1 | Define and select edge security strategies based on anticipated threats | [teaching/03](../teaching/03-infrastructure-security.md#task-31-edge) |
| 3.1.2 | Implement edge protection (CloudFront headers, WAF, IoT policies, OWASP Top 10, S3 CORS, Shield Advanced) | [teaching/03](../teaching/03-infrastructure-security.md#task-31-edge) |
| 3.1.3 | Design edge controls and rules (geography, rate limiting, client fingerprinting) | [teaching/03](../teaching/03-infrastructure-security.md#waf-rule-design) |
| 3.1.4 | Configure integrations with edge and third-party services (OCSF ingestion, third-party WAF rules) | [teaching/03](../teaching/03-infrastructure-security.md#waf-rule-design) |

### Task 3.2: Design, implement, and troubleshoot security controls for compute workloads

| Skill | Statement | Covered in |
|---|---|---|
| 3.2.1 | Hardened AMIs and container images (Systems Manager, EC2 Image Builder) | [teaching/03](../teaching/03-infrastructure-security.md#task-32-compute) |
| 3.2.2 | Apply instance profiles, service roles, and execution roles | [teaching/03](../teaching/03-infrastructure-security.md#workload-identity) |
| 3.2.3 | Scan compute for vulnerabilities (Inspector, GuardDuty runtime monitoring) | [teaching/03](../teaching/03-infrastructure-security.md#vulnerability-management) |
| 3.2.4 | Deploy patches (Patch Manager, Inspector) | [teaching/03](../teaching/03-infrastructure-security.md#vulnerability-management) |
| 3.2.5 | Secure administrative access (Session Manager, EC2 Instance Connect) | [teaching/03](../teaching/03-infrastructure-security.md#administrative-access) |
| 3.2.6 | Pipeline security tooling (Amazon Q Developer, CodeGuru Security) | [teaching/03](../teaching/03-infrastructure-security.md#pipeline-security) |
| 3.2.7 | Protections and guardrails for generative AI applications (OWASP Top 10 for LLM Applications) | [teaching/03](../teaching/03-infrastructure-security.md#generative-ai-workloads) |

### Task 3.3: Design and troubleshoot network security controls

| Skill | Statement | Covered in |
|---|---|---|
| 3.3.1 | Network controls to permit or prevent traffic (security groups, NACLs, Network Firewall) | [network cheatsheet](../cheatsheets/network-security.md), [teaching/03](../teaching/03-infrastructure-security.md#task-33-network) |
| 3.3.2 | Secure hybrid and multi-cloud connectivity (Site-to-Site VPN, Direct Connect, MACsec) | [teaching/03](../teaching/03-infrastructure-security.md#hybrid-connectivity) |
| 3.3.3 | Communication between hybrid environments and AWS (Verified Access) | [teaching/03](../teaching/03-infrastructure-security.md#hybrid-connectivity) |
| 3.3.4 | Network segmentation (north/south, east/west, isolated subnets) | [teaching/03](../teaching/03-infrastructure-security.md#segmentation) |
| 3.3.5 | Identify unnecessary network access (Verified Access, Network Access Analyzer, Inspector reachability) | [teaching/03](../teaching/03-infrastructure-security.md#finding-unnecessary-access) |

## Domain 4: Identity and Access Management

### Task 4.1: Design, implement, and troubleshoot authentication strategies

| Skill | Statement | Covered in |
|---|---|---|
| 4.1.1 | Identity solutions for human, application, and system authentication (IAM Identity Center, Cognito, MFA, IdP integration) | [teaching/04](../teaching/04-identity-and-access-management.md#task-41-authentication) |
| 4.1.2 | Mechanisms to issue temporary credentials (STS, S3 presigned URLs) | [teaching/04](../teaching/04-identity-and-access-management.md#temporary-credentials) |
| 4.1.3 | Troubleshoot authentication issues (CloudTrail, Cognito, permission sets, Directory Service) | [teaching/04](../teaching/04-identity-and-access-management.md#troubleshooting-authentication) |

### Task 4.2: Design, implement, and troubleshoot authorization strategies

| Skill | Statement | Covered in |
|---|---|---|
| 4.2.1 | Authorization controls (Verified Permissions, IAM paths, Roles Anywhere, cross-account resource policies, trust policies) | [teaching/04](../teaching/04-identity-and-access-management.md#task-42-authorization) |
| 4.2.2 | ABAC and RBAC strategies | [teaching/04](../teaching/04-identity-and-access-management.md#abac-and-rbac) |
| 4.2.3 | Least-privilege IAM policies (permission boundaries, session policies) | [policy evaluation cheatsheet](../cheatsheets/iam-policy-evaluation.md) |
| 4.2.4 | Analyze authorization failures (Policy Simulator, Access Analyzer) | [teaching/04](../teaching/04-identity-and-access-management.md#troubleshooting-authorization) |
| 4.2.5 | Investigate and correct unintended permissions (Access Analyzer) | [teaching/04](../teaching/04-identity-and-access-management.md#access-analyzer) |

## Domain 5: Data Protection

### Task 5.1: Design and implement controls for data in transit

| Skill | Statement | Covered in |
|---|---|---|
| 5.1.1 | Require encryption when connecting to resources (ELB security policies, enforcing TLS) | [teaching/05](../teaching/05-data-protection.md#task-51-data-in-transit) |
| 5.1.2 | Secure and private access to resources (PrivateLink, VPC endpoints, Client VPN, Verified Access) | [teaching/05](../teaching/05-data-protection.md#private-access), [network cheatsheet](../cheatsheets/network-security.md#vpc-endpoints) |
| 5.1.3 | Inter-resource encryption in transit (EMR, EKS, SageMaker AI, Nitro) | [teaching/05](../teaching/05-data-protection.md#inter-resource-encryption) |

### Task 5.2: Design and implement controls for data at rest

| Skill | Statement | Covered in |
|---|---|---|
| 5.2.1 | Encryption at rest (CloudHSM vs KMS, client-side vs server-side) | [teaching/05](../teaching/05-data-protection.md#task-52-data-at-rest), [KMS cheatsheet](../cheatsheets/kms.md) |
| 5.2.2 | Data integrity (Object Lock, Vault Lock, versioning, code signing, file validation) | [teaching/05](../teaching/05-data-protection.md#integrity) |
| 5.2.3 | Lifecycle management and retention | [teaching/05](../teaching/05-data-protection.md#lifecycle-and-retention) |
| 5.2.4 | Secure replication and backup (Data Lifecycle Manager, AWS Backup, ransomware protection, DataSync) | [teaching/05](../teaching/05-data-protection.md#backup-and-replication), [ransomware runbook](../runbooks/ransomware-data-destruction.md) |

### Task 5.3: Protect confidential data, credentials, secrets, and cryptographic key materials

| Skill | Statement | Covered in |
|---|---|---|
| 5.3.1 | Management and rotation of credentials and secrets (Secrets Manager) | [teaching/05](../teaching/05-data-protection.md#secrets) |
| 5.3.2 | Manage and use imported key material and external key stores | [KMS cheatsheet](../cheatsheets/kms.md#key-material-origin) |
| 5.3.3 | Differences between imported and AWS-generated key material | [KMS cheatsheet](../cheatsheets/kms.md#key-material-origin) |
| 5.3.4 | Mask sensitive data (CloudWatch Logs data protection policies, SNS message data protection) | [teaching/05](../teaching/05-data-protection.md#masking) |
| 5.3.5 | Keys and certificates across one or more Regions (customer managed keys, Private CA) | [teaching/05](../teaching/05-data-protection.md#certificates), [KMS cheatsheet](../cheatsheets/kms.md#multi-region-keys) |

## Domain 6: Security Foundations and Governance

### Task 6.1: Develop a strategy to centrally deploy and manage AWS accounts

| Skill | Statement | Covered in |
|---|---|---|
| 6.1.1 | Deploy and configure organizations by using AWS Organizations | [teaching/06](../teaching/06-security-foundations-and-governance.md#task-61-accounts) |
| 6.1.2 | Implement and manage Control Tower; deploy optional and custom controls | [teaching/06](../teaching/06-security-foundations-and-governance.md#control-tower) |
| 6.1.3 | Organization policies (SCPs, RCPs, AI service opt-out policies, declarative policies) | [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md) |
| 6.1.4 | Centrally manage security services (delegated administrators) | [teaching/06](../teaching/06-security-foundations-and-governance.md#delegated-administration) |
| 6.1.5 | Manage root user credentials (centralized root access, MFA, break-glass) | [teaching/06](../teaching/06-security-foundations-and-governance.md#root-user), [root runbook](../runbooks/root-user-activity.md) |

### Task 6.2: Implement a secure and consistent deployment strategy for cloud resources

| Skill | Statement | Covered in |
|---|---|---|
| 6.2.1 | IaC across accounts (StackSets, third-party IaC, CloudFormation Guard, cfn-lint) | [teaching/06](../teaching/06-security-foundations-and-governance.md#task-62-deployment) |
| 6.2.2 | Tags to organize resources | [teaching/06](../teaching/06-security-foundations-and-governance.md#tagging) |
| 6.2.3 | Deploy and enforce policies from a central source (Firewall Manager) | [teaching/06](../teaching/06-security-foundations-and-governance.md#central-enforcement) |
| 6.2.4 | Securely share resources across accounts (Service Catalog, RAM) | [teaching/06](../teaching/06-security-foundations-and-governance.md#sharing) |

### Task 6.3: Evaluate the compliance of AWS resources

| Skill | Statement | Covered in |
|---|---|---|
| 6.3.1 | Rules to detect and remediate noncompliant resources (Config, Security Hub) | [teaching/06](../teaching/06-security-foundations-and-governance.md#task-63-evaluate-compliance) |
| 6.3.2 | Audit services to collect and organize evidence (Audit Manager, Artifact) | [teaching/06](../teaching/06-security-foundations-and-governance.md#evidence), [control mappings](../control-mappings/README.md) |
| 6.3.3 | Evaluate architecture against best practices (Well-Architected Tool) | [teaching/06](../teaching/06-security-foundations-and-governance.md#evidence) |

## What changed from SCS-C02

- Six domains remain, but logging and monitoring merged into **Detection**, and **Incident Response** became its own domain.
- IAM is now the heaviest domain at 20%.
- New explicit topics: generative AI guardrails (3.2.7), RCPs and declarative policies (6.1.3), centralized root access (6.1.5), external key stores (5.3.2), Verified Access, Security Lake and OCSF, pipeline security tooling.
- New question types: ordering and matching.

The exam guide appendix has the authoritative comparison.
