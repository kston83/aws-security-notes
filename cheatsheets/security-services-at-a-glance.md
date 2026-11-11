# AWS security services at a glance

> **Last reviewed:** 2026-11-10 · **SCS-C03:** all domains · Service names and features change often **(verify)**.

## Which service answers which question

| Question | Service |
|---|---|
| Is someone attacking or misusing my account right now? | GuardDuty |
| Are my resources configured securely? Where do all findings go? | Security Hub (CSPM) |
| What software vulnerabilities do my workloads have? | Inspector |
| Where is my sensitive data in S3? | Macie |
| What did this resource look like last week, and is it compliant? | Config |
| Who can access this from outside my account or organization? What access is unused? | IAM Access Analyzer |
| What else did this compromised principal touch? | Detective |
| Who called this API? | CloudTrail |
| How do I normalize and centralize all security logs? | Security Lake |
| How do I enforce firewall rules in every account? | Firewall Manager |
| How do I gather audit evidence? | Audit Manager |
| Where are AWS's own compliance reports? | Artifact |

## Detection and response

| Service | One line | Scope | Org support |
|---|---|---|---|
| GuardDuty | Threat detection from logs, runtime, and malware scanning | Regional | Delegated admin, auto-enable |
| Security Hub | Findings aggregation, posture standards, correlation | Regional, cross-Region aggregation | Delegated admin, central configuration |
| Inspector | Continuous vulnerability scanning: EC2, ECR, Lambda | Regional | Delegated admin, auto-enable |
| Macie | Sensitive data discovery in S3 | Regional | Delegated admin |
| Detective | Investigation graph over CloudTrail, flow logs, findings | Regional | Delegated admin |
| Security Lake | OCSF data lake | Regional with rollup | Delegated admin |
| Security Incident Response | Managed triage, case handling, access to AWS responders | Organization | Membership covers accounts |
| CloudTrail | API audit log | Regional, multi-Region trails | Organization trail |
| Config | Configuration history, rules, remediation | Regional | Aggregator, organization rules |
| CloudWatch | Metrics, logs, alarms, dashboards | Regional | Cross-account observability |
| EventBridge | Event routing for automation | Regional | Cross-account buses |
| Systems Manager | Fleet operations: Session Manager, Patch Manager, Run Command, Automation, OpsCenter, Incident Manager | Regional | Delegated admin for several features |

## Identity

| Service | One line |
|---|---|
| IAM | Principals, policies, roles, federation for one account |
| IAM Identity Center | Workforce single sign-on to accounts and applications |
| IAM Access Analyzer | External, internal, and unused access findings; policy validation and generation |
| IAM Roles Anywhere | Temporary credentials for external workloads using X.509 certificates |
| STS | Issues temporary credentials |
| Organizations | Accounts, OUs, SCPs, RCPs, declarative and management policies |
| Cognito | Customer identity: user pools (authentication) and identity pools (AWS credentials) |
| Verified Permissions | Application authorization with Cedar policies |
| Directory Service | Managed Microsoft AD, AD Connector, Simple AD |
| RAM | Share resources across accounts |

## Network and edge

| Service | One line | Layer |
|---|---|---|
| Shield Standard | Automatic DDoS protection, free | 3, 4 |
| Shield Advanced | Enhanced DDoS detection, response team, cost protection | 3, 4, 7 |
| WAF | Web request filtering | 7 |
| Firewall Manager | Central policy for WAF, Shield, security groups, Network Firewall, DNS Firewall, NACLs | Management |
| Network Firewall | Managed stateful firewall and IPS for VPCs | 3–7 |
| Route 53 Resolver DNS Firewall | Filters outbound DNS | DNS |
| Security groups, NACLs | Instance and subnet filtering | 3, 4 |
| PrivateLink and VPC endpoints | Private connectivity to services | Network |
| Verified Access | Zero-trust application access without VPN | 7 |
| Client VPN, Site-to-Site VPN | Remote and site connectivity | 3 |
| Network Access Analyzer | Finds unintended network paths | Analysis |
| Reachability Analyzer | Tests a path between two endpoints | Analysis |
| VPC Lattice | Service-to-service connectivity with auth policies | 7 |

## Data protection

| Service | One line |
|---|---|
| KMS | Managed keys and cryptographic operations, integrated with AWS services |
| CloudHSM | Single-tenant hardware security modules |
| Secrets Manager | Secret storage with rotation |
| Systems Manager Parameter Store | Configuration and simple secret storage |
| Certificate Manager (ACM) | Public and private TLS certificates for AWS services |
| Private CA | Managed private certificate authority |
| Macie | Sensitive data discovery |
| AWS Backup | Central backup with vault lock and cross-account copy |
| Signer | Code signing for Lambda and containers |
| Nitro Enclaves | Isolated compute for processing sensitive data, with KMS attestation |
| Payment Cryptography | Payment HSM operations as a service |
| Clean Rooms | Collaborative analysis without sharing raw data |

## Governance and compliance

| Service | One line |
|---|---|
| Control Tower | Landing zone, account factory, controls |
| Config | Rules, conformance packs, remediation |
| Security Hub CSPM | Standards: FSBP, CIS, PCI DSS, NIST 800-53 |
| Audit Manager | Continuous evidence collection mapped to frameworks |
| Artifact | AWS compliance reports and agreements |
| Well-Architected Tool | Workload reviews against the framework |
| Trusted Advisor | Account best-practice checks |
| Service Catalog | Approved, pre-configured products |
| CloudFormation (StackSets, Guard, hooks) | Consistent deployment and policy as code |
| Resilience Hub, Fault Injection Service | Resilience assessment and testing |

## Commonly confused pairs

| Pair | Difference |
|---|---|
| GuardDuty vs Inspector | Threats happening vs vulnerabilities present |
| GuardDuty vs Detective | Raises the finding vs investigates it |
| Security Hub vs Config | Aggregated findings and standards vs the configuration recorder and rules beneath them |
| Config vs CloudTrail | What a resource *is* vs who *did* what |
| Macie vs GuardDuty S3 Protection | What data is in the bucket vs suspicious access to the bucket |
| Inspector vs Patch Manager | Finds vulnerabilities vs applies patches |
| WAF vs Network Firewall | HTTP at the edge or load balancer vs all traffic in the VPC |
| WAF vs Shield | Request filtering vs DDoS protection |
| Security group vs NACL | Stateful, allow only, ENI vs stateless, allow and deny, subnet |
| SCP vs RCP | Limits your principals vs limits access to your resources |
| SCP vs permissions boundary | Organization-wide ceiling vs per-principal ceiling |
| Secrets Manager vs Parameter Store | Rotation and cross-account vs simple and free |
| KMS vs CloudHSM | Managed, integrated, multi-tenant vs single-tenant with direct HSM control |
| ACM vs Private CA | Certificates for AWS endpoints vs your own CA hierarchy |
| Audit Manager vs Artifact | Your evidence vs AWS's reports |
| Cognito user pool vs identity pool | Who you are (tokens) vs AWS credentials |
| IAM Identity Center vs Cognito | Workforce vs customers |
| Reachability Analyzer vs Network Access Analyzer | One path, troubleshooting vs all paths, auditing |
| Session Manager vs EC2 Instance Connect | No inbound port, via SSM agent vs SSH with a short-lived key |
| Object Lock governance vs compliance | Overridable with permission vs immutable for everyone |
| Trusted access vs delegated administrator | Service may operate in the org vs a member account administers it |

## Global vs Regional reminders

- **Global:** IAM, Organizations, Route 53, CloudFront, WAF for CloudFront (managed in us-east-1), Shield Advanced subscription, Artifact.
- **Regional, enable everywhere:** GuardDuty, Security Hub, Config, Inspector, Macie, Access Analyzer external access analyzers, KMS keys, ACM certificates, Secrets Manager secrets.
