# Controls by family

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · Read [README.md](README.md) first for method and caveats.

Reverse lookup: for each control, the AWS configurations that implement or support it and where evidence comes from. Baseline column: L, M, H per 800-53B **(verify)**; `–` means not in a baseline.

Families that are mostly procedural (AT, PL, PM, PS, PT) or mostly inherited from AWS (PE) are summarized at the end.

## AC: Access Control

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| AC-2 | Account Management | L M H | IAM Identity Center with IdP as the source of identities and SCIM provisioning; IAM roles in place of users; credential report; unused access findings; Organizations for account lifecycle | Identity Center assignments, IAM credential report, Access Analyzer findings, CloudTrail IAM events |
| AC-2(1) | Automated Account Management | M H | SCIM provisioning and deprovisioning from the IdP; permission sets managed as code | IdP and Identity Center logs |
| AC-2(3) | Disable Accounts | M H | Config rule on unused credentials with remediation; Access Analyzer unused access | `iam-user-unused-credentials-check` |
| AC-2(4) | Automated Audit Actions | M H | CloudTrail records account creation, modification, enabling, disabling, removal; EventBridge rules alert on them | CloudTrail |
| AC-2(12) | Account Monitoring for Atypical Usage | H | GuardDuty IAM anomaly findings; CloudTrail Insights | GuardDuty findings |
| AC-3 | Access Enforcement | L M H | IAM policy evaluation on every API call; resource policies; KMS key policies; S3 Block Public Access; VPC endpoint policies | Policies as code, Access Analyzer, Config |
| AC-3(7) | Role-Based Access Control | – | IAM roles and permission sets per job function | Permission set definitions |
| AC-3(13) | Attribute-Based Access Control | – | Tag-based conditions: `aws:PrincipalTag`, `aws:ResourceTag`; session tags from the IdP | Policies, tag policies |
| AC-4 | Information Flow Enforcement | M H | Security groups, NACLs, route tables, Network Firewall, transit gateway route tables, VPC endpoint policies, data perimeter conditions in SCPs and RCPs, DNS Firewall | Config, Network Access Analyzer, flow logs |
| AC-5 | Separation of Duties | M H | Separate accounts for log archive, security tooling, and workloads; KMS key administrators distinct from key users; pipeline roles distinct from developers; permissions boundaries | Account structure, key policies, IAM policies |
| AC-6 | Least Privilege | M H | Scoped IAM policies; permissions boundaries; SCPs and RCPs; Access Analyzer policy generation and unused access; no wildcard admin | `iam-policy-no-statements-with-admin-access`, Access Analyzer |
| AC-6(1) | Authorize Access to Security Functions | M H | SCP restricting changes to CloudTrail, GuardDuty, Config, Security Hub to a security role | SCP text, CloudTrail |
| AC-6(2) | Non-Privileged Access for Nonsecurity Functions | M H | Separate read-only and administrative permission sets; no routine use of admin roles | Identity Center assignments |
| AC-6(5) | Privileged Accounts | M H | Root credentials removed from member accounts; small set of admin permission set assignments | Root access management state, assignments |
| AC-6(7) | Review of User Privileges | M H | Access Analyzer unused access findings; last-accessed data; periodic assignment review | Findings, review records |
| AC-6(9) | Log Use of Privileged Functions | M H | CloudTrail management events, organization-wide | CloudTrail |
| AC-6(10) | Prohibit Non-Privileged Users from Executing Privileged Functions | M H | IAM default deny; SCP guardrails | Policies |
| AC-7 | Unsuccessful Logon Attempts | L M H | Enforced at the IdP for federated users; Cognito lockout behavior; alarm on failed `ConsoleLogin` | IdP logs, CloudTrail |
| AC-12 | Session Termination | M H | Role maximum session duration; Identity Center session duration; session revocation | Role and permission set settings |
| AC-17 | Remote Access | L M H | Session Manager in place of SSH/RDP; Client VPN with SAML and MFA; Verified Access | Session logs, VPN connection logs |
| AC-17(1) | Monitoring and Control | M H | Session Manager logging to S3 or CloudWatch Logs; Verified Access logs | Session logs |
| AC-17(2) | Protection of Confidentiality and Integrity Using Encryption | M H | TLS for Session Manager and all API endpoints; IPsec for Site-to-Site VPN | Service configuration |
| AC-20 | Use of External Systems | L M H | `aws:PrincipalOrgID` and `aws:ResourceOrgID` data perimeter; Access Analyzer external access | RCP and SCP text, findings |
| AC-21 | Information Sharing | M H | RAM shares restricted to the organization; resource policies scoped by organization; Access Analyzer | RAM settings, findings |
| AC-22 | Publicly Accessible Content | L M H | S3 Block Public Access; EBS snapshot, AMI, and RDS snapshot public-sharing blocks; declarative policies | `s3-account-level-public-access-blocks-periodic`, `ebs-snapshot-public-restorable-check`, `rds-snapshots-public-prohibited` |

## AU: Audit and Accountability

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| AU-2 | Event Logging | L M H | CloudTrail management events; data events for sensitive resources; VPC Flow Logs; Resolver query logs; service logs | Trail configuration, `cloudtrail-enabled`, `vpc-flow-logs-enabled` |
| AU-3 | Content of Audit Records | L M H | CloudTrail record fields: who, what, when, where, source, outcome | Sample records |
| AU-3(1) | Additional Audit Information | M H | Data events; source identity and session tags in CloudTrail; flow log custom fields | Event selectors |
| AU-4 | Audit Log Storage Capacity | L M H | S3 for log storage (no capacity limit to manage); lifecycle to colder tiers | Bucket configuration |
| AU-5 | Response to Audit Logging Process Failures | L M H | Alarm on trail delivery errors and on absence of logs; EventBridge on `StopLogging` | Alarm definitions, alarm history |
| AU-6 | Audit Record Review, Analysis, and Reporting | L M H | GuardDuty analysis of logs; Security Hub; Athena, Logs Insights, CloudTrail Lake queries; Detective | Findings, saved queries, review records |
| AU-6(1) | Automated Process Integration | M H | EventBridge routing of findings to ticketing and response | Rule definitions |
| AU-6(3) | Correlate Audit Record Repositories | M H | Security Lake; Detective behavior graph; Security Hub cross-Region and cross-account aggregation | Aggregation settings |
| AU-7 | Audit Record Reduction and Report Generation | M H | Athena, CloudTrail Lake, Logs Insights, OpenSearch | Queries and dashboards |
| AU-8 | Time Stamps | L M H | CloudTrail timestamps in UTC from AWS time sources; Amazon Time Sync Service for instances | Inherited plus instance configuration |
| AU-9 | Protection of Audit Information | L M H | Log archive account; bucket policy restricting access; SSE-KMS; SCP denying deletion; log file validation | Bucket policy, SCP, `cloud-trail-log-file-validation-enabled`, `cloud-trail-encryption-enabled` |
| AU-9(2) | Store on Separate Physical Systems or Components | H | Logs delivered to a separate account; cross-Region replication of the archive | Account structure, replication rule |
| AU-9(3) | Cryptographic Protection | H | Log file validation digests; SSE-KMS | Validation output |
| AU-9(4) | Access by Subset of Privileged Users | M H | Log archive account accessible only to a small audit role | IAM and bucket policies |
| AU-10 | Non-repudiation | H | CloudTrail with integrity validation ties actions to authenticated principals; source identity persists through role chaining | CloudTrail, validation |
| AU-11 | Audit Record Retention | L M H | S3 lifecycle and Object Lock retention; CloudWatch Logs retention settings; CloudTrail Lake retention | `cw-loggroup-retention-period-check`, lifecycle configuration |
| AU-12 | Audit Record Generation | L M H | Organization trail across all accounts and Regions | `multi-region-cloudtrail-enabled` |
| AU-12(1) | System-Wide and Time-Correlated Audit Trail | H | Organization trail to one archive; Security Lake | Trail configuration |

## CA: Assessment, Authorization, and Monitoring

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| CA-2 | Control Assessments | L M H | Security Hub standards; Config conformance packs; Audit Manager assessments; Well-Architected reviews | Assessment reports |
| CA-3 | Information Exchange | L M H | PrivateLink, VPN, peering, and cross-account access documented and restricted | Network and resource policy configuration |
| CA-7 | Continuous Monitoring | L M H | Security Hub, Config, GuardDuty, Inspector, Access Analyzer running continuously across the organization | Findings history, scores |
| CA-7(4) | Risk Monitoring | L M H | Security Hub severity and trends; Inspector risk scores | Dashboards |
| CA-9 | Internal System Connections | L M H | Security group references, transit gateway route tables, VPC Lattice policies | Config |

## CM: Configuration Management

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| CM-2 | Baseline Configuration | L M H | Infrastructure as code; Control Tower landing zone; Image Builder golden images; Config recording | Repositories, Config snapshots |
| CM-2(2) | Automation Support for Accuracy and Currency | M H | Config recorder; drift detection | Config |
| CM-3 | Configuration Change Control | M H | Pipelines with approvals; CloudFormation change sets; CloudTrail and Config record every change | Pipeline history, Config timeline |
| CM-4 | Impact Analyses | L M H | Change sets; Access Analyzer `CheckNoNewAccess`; these mappings | Pipeline output |
| CM-5 | Access Restrictions for Change | L M H | Deployment only through pipeline roles; SCPs restricting manual change; stack policies | IAM, SCP |
| CM-6 | Configuration Settings | L M H | Config rules and conformance packs; Security Hub controls; declarative policies; State Manager | Compliance status |
| CM-6(1) | Automated Management, Application, and Verification | H | Config auto-remediation; Firewall Manager; Control Tower controls | Remediation history |
| CM-7 | Least Functionality | L M H | Security groups limited to required ports; Region restriction SCP; service allow-list SCP; minimal images | `restricted-ssh`, `vpc-sg-open-only-to-authorized-ports`, SCP |
| CM-7(5) | Authorized Software: Allow-by-Exception | M H | Allowed AMIs setting; ECR image signing and admission control; Lambda code signing | Declarative policy, signing configuration |
| CM-8 | System Component Inventory | L M H | Config resource inventory and aggregator; Systems Manager Inventory; Resource Explorer; tags | Aggregator queries |
| CM-8(1) | Updates During Installation and Removal | M H | Config records resource creation and deletion automatically | Config timeline |
| CM-12 | Information Location | M H | Macie discovery; Region restriction; tags for data classification | Macie findings |
| CM-14 | Signed Components | – | AWS Signer with Lambda code signing configuration; signed container images | Signing profiles |

## CP: Contingency Planning

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| CP-2 | Contingency Plan | L M H | Resilience Hub assessments inform the plan | Assessment reports |
| CP-4 | Contingency Plan Testing | L M H | AWS Backup restore testing; Fault Injection Service; Application Recovery Controller drills | Test results |
| CP-6 | Alternate Storage Site | M H | Cross-Region replication; AWS Backup cross-Region and cross-account copy | Replication and copy configuration |
| CP-7 | Alternate Processing Site | M H | Multi-AZ and multi-Region deployment | Architecture |
| CP-9 | System Backup | L M H | AWS Backup plans by policy; RDS automated backups; DynamoDB point-in-time recovery; S3 Versioning; Data Lifecycle Manager | `db-instance-backup-enabled`, `dynamodb-pitr-enabled`, `s3-bucket-versioning-enabled`, Backup Audit Manager |
| CP-9(1) | Testing for Reliability and Integrity | M H | AWS Backup restore testing | Restore test reports |
| CP-9(3) | Separate Storage for Critical Information | H | Backup account; logically air-gapped vault | Vault configuration |
| CP-9(8) | Cryptographic Protection | M H | Backup vault KMS encryption; encrypted snapshots | Vault and snapshot settings |
| CP-10 | System Recovery and Reconstitution | L M H | Infrastructure as code redeploy; point-in-time restore; Auto Scaling replacement | Recovery exercise records |

## IA: Identification and Authentication

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| IA-2 | Identification and Authentication (Organizational Users) | L M H | Federation through Identity Center; unique identities; no shared users | Identity Center configuration |
| IA-2(1), IA-2(2) | MFA to Privileged and Non-Privileged Accounts | L M H | MFA at the IdP; MFA on root and any IAM users; deny-without-MFA policies | `root-account-mfa-enabled`, `mfa-enabled-for-iam-console-access`, `iam-user-mfa-enabled` |
| IA-2(8) | Access to Accounts: Replay Resistant | L M H | SigV4 request signing; TLS; FIDO authenticators | Inherited plus MFA type |
| IA-3 | Device Identification and Authentication | M H | IoT device certificates; Verified Access device trust; Roles Anywhere certificates | Certificates, trust provider configuration |
| IA-4 | Identifier Management | L M H | IdP-managed identifiers; IAM unique IDs; source identity | IdP records |
| IA-5 | Authenticator Management | L M H | IAM password policy; access key rotation or elimination; Secrets Manager rotation; ACM renewal | `iam-password-policy`, `access-keys-rotated`, `secretsmanager-rotation-enabled-check` |
| IA-5(1) | Password-Based Authentication | L M H | Password policy at the IdP and in IAM; Cognito password policy and compromised-credential checks | Policy settings |
| IA-5(2) | Public Key-Based Authentication | M H | Private CA; Roles Anywhere trust anchors; mutual TLS | CA configuration |
| IA-5(7) | No Embedded Unencrypted Static Authenticators | – | Secrets Manager and Parameter Store references; secret scanning in pipelines | Scan results |
| IA-8 | Identification and Authentication (Non-Organizational Users) | L M H | Cognito user pools; federation with external IdPs | User pool configuration |
| IA-9 | Service Identification and Authentication | – | IAM roles for services; service principals with `aws:SourceArn`; mutual TLS | Trust and resource policies |
| IA-11 | Re-Authentication | L M H | Session duration limits; `aws:MultiFactorAuthAge` conditions | Role settings, policies |

## IR: Incident Response

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| IR-3 | Incident Response Testing | M H | Game days with GuardDuty sample findings; Fault Injection Service | Exercise records |
| IR-4 | Incident Handling | L M H | Runbooks; responder role; isolation security groups; quarantine SCP; Security Incident Response service | [Runbooks](../runbooks/README.md), incident records |
| IR-4(1) | Automated Incident Handling Processes | M H | EventBridge with Lambda, Step Functions, and Systems Manager Automation | Automation definitions and execution history |
| IR-5 | Incident Monitoring | L M H | Security Hub and GuardDuty findings with workflow status; Incident Manager; OpsCenter | Findings history |
| IR-6 | Incident Reporting | L M H | SNS and EventBridge notification; security contact on every account | Notification configuration |
| IR-7 | Incident Response Assistance | L M H | AWS Support; Security Incident Response; Shield Response Team | Support plan |
| IR-8 | Incident Response Plan | L M H | Incident Manager response plans | Plan documents |

## MA and MP: Maintenance, Media Protection

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| MA-4 | Nonlocal Maintenance | L M H | Session Manager with IAM authorization, MFA, and logging; no direct SSH or RDP | Session logs |
| MP-2 | Media Access | L M H | Access to snapshots, AMIs, and backups controlled by IAM and KMS | Policies |
| MP-6 | Media Sanitization | L M H | Physical media: inherited from AWS. Logical: cryptographic erasure by deleting the KMS key or data key | Artifact reports; key deletion records |

## RA: Risk Assessment

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| RA-2 | Security Categorization | L M H | Data classification tags; Macie discovery | Tags, Macie findings |
| RA-3 | Risk Assessment | L M H | Security Hub, Inspector, Access Analyzer, and Well-Architected findings as inputs | Reports |
| RA-5 | Vulnerability Monitoring and Scanning | L M H | Inspector on EC2, ECR, Lambda; Security Hub controls; Access Analyzer | Inspector findings, coverage report |
| RA-5(2) | Update Vulnerabilities to Be Scanned | L M H | Inspector updates its vulnerability intelligence continuously and rescans | Inherited behavior of the service |
| RA-5(5) | Privileged Access | M H | Inspector scans through the SSM agent or agentless snapshot access | Coverage |
| RA-5(11) | Public Disclosure Program | L M H | Process; not an AWS configuration | |

## SA and SR: Acquisition, Supply Chain

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| SA-3 | System Development Life Cycle | L M H | Pipelines with security stages | Pipeline definitions |
| SA-8 | Security and Privacy Engineering Principles | L M H | Well-Architected reviews; reference architectures | Review records |
| SA-9 | External System Services | L M H | AWS as provider: Artifact reports and agreements | Artifact |
| SA-10 | Developer Configuration Management | M H | Source control; signed commits; IaC | Repository settings |
| SA-11 | Developer Testing and Evaluation | M H | Code scanning; Inspector in the pipeline; Guard and cfn-lint | Scan results |
| SA-11(1) | Static Code Analysis | – | Inspector code scanning; Q Developer; CodeGuru Security | Findings |
| SA-15 | Development Process, Standards, and Tools | M H | Service Catalog approved products | Portfolio |
| SR-3 | Supply Chain Controls and Processes | L M H | Private artifact repositories (CodeArtifact, ECR); allowed AMIs; SBOM export from Inspector | Repository policy, SBOMs |
| SR-4 | Provenance | H | Image and code signing; SBOM | Signatures |
| SR-11 | Component Authenticity | L M H | Signer; ECR image signature verification | Signing configuration |

## SC: System and Communications Protection

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| SC-2 | Separation of System and User Functionality | M H | Separate accounts and roles for management functions; management account kept empty | Account structure |
| SC-4 | Information in Shared System Resources | M H | Inherited: hypervisor isolation, memory scrubbing. Dedicated tenancy where required. | Artifact |
| SC-5 | Denial-of-Service Protection | L M H | Shield Standard; Shield Advanced; WAF rate-based rules; CloudFront; Auto Scaling | Shield and WAF configuration |
| SC-7 | Boundary Protection | L M H | VPC design with public, private, and isolated subnets; security groups; NACLs; Network Firewall; WAF; VPC Block Public Access | Config, Network Access Analyzer |
| SC-7(3) | Access Points | M H | Limited, managed ingress and egress points: central ingress and egress VPCs | Architecture, route tables |
| SC-7(4) | External Telecommunications Services | M H | Managed interfaces at internet gateway, NAT, Direct Connect, VPN; traffic policy per interface | Network configuration |
| SC-7(5) | Deny by Default, Allow by Exception | M H | Security groups (implicit deny); Network Firewall strict order with default drop; default security group closed | `vpc-default-security-group-closed` |
| SC-7(8) | Route Traffic to Authenticated Proxy Servers | M H | Egress through Network Firewall or proxy fleet | Route tables |
| SC-7(10) | Prevent Exfiltration | – | Egress domain allow lists; DNS Firewall; endpoint policies with `aws:ResourceOrgID` | Firewall policy |
| SC-7(21) | Isolation of System Components | H | Separate accounts and VPCs; transit gateway route table separation | Architecture |
| SC-8 | Transmission Confidentiality and Integrity | M H | TLS enforced by `aws:SecureTransport`; ELB security policies; CloudFront HTTPS only; database force-SSL parameters; VPN; MACsec | `s3-bucket-ssl-requests-only`, `elb-tls-https-listeners-only`, `alb-http-to-https-redirection-check` |
| SC-8(1) | Cryptographic Protection | M H | Same, with approved TLS versions and ciphers | Security policy names |
| SC-10 | Network Disconnect | M H | Load balancer idle timeouts; session duration limits | Settings |
| SC-12 | Cryptographic Key Establishment and Management | L M H | KMS customer managed keys: key policies, rotation, deletion waiting period; CloudHSM | `cmk-backing-key-rotation-enabled`, `kms-cmk-not-scheduled-for-deletion` |
| SC-12(1) | Availability | H | Multi-Region keys; key deletion guardrails; escrow of imported key material | Key configuration |
| SC-12(2), SC-12(3) | Symmetric and Asymmetric Keys | H / – | KMS symmetric and asymmetric keys generated in validated HSMs | Key specs |
| SC-12(6) | Physical Control of Keys | – | External key store; CloudHSM | Key store configuration |
| SC-13 | Cryptographic Protection | L M H | KMS and AWS services using FIPS-validated modules; FIPS endpoints where required | Artifact, endpoint configuration |
| SC-17 | Public Key Infrastructure Certificates | M H | ACM; Private CA with defined hierarchy and revocation | CA configuration, `acm-certificate-expiration-check` |
| SC-20, SC-21, SC-22 | Secure Name/Address Resolution | L M H | Route 53 with DNSSEC signing; Resolver DNSSEC validation; Route 53 architecture | Hosted zone and resolver settings |
| SC-23 | Session Authenticity | M H | TLS; SigV4; signed cookies and URLs | Configuration |
| SC-28 | Protection of Information at Rest | M H | Encryption at rest on S3, EBS, RDS, DynamoDB, EFS, logs, backups | `ec2-ebs-encryption-by-default`, `rds-storage-encrypted`, `encrypted-volumes`, `cloudwatch-log-group-encrypted` |
| SC-28(1) | Cryptographic Protection | M H | Same, with KMS keys | Same |
| SC-28(3) | Cryptographic Keys | – | KMS HSM-protected keys; CloudHSM | Key configuration |
| SC-39 | Process Isolation | L M H | Inherited: Nitro hypervisor. Customer: separate accounts, containers, Nitro Enclaves | Artifact, architecture |

## SI: System and Information Integrity

| Control | Name | Baseline | AWS configurations | Evidence |
|---|---|---|---|---|
| SI-2 | Flaw Remediation | L M H | Patch Manager baselines and compliance; Inspector findings; image rebuild pipeline | `ec2-managedinstance-patch-compliance-status-check`, Inspector |
| SI-2(2) | Automated Flaw Remediation Status | M H | Patch compliance reporting; Inspector coverage and finding status | Compliance reports |
| SI-3 | Malicious Code Protection | L M H | GuardDuty Malware Protection for EC2, S3, and backups; Runtime Monitoring; endpoint protection on instances | GuardDuty findings and scan records |
| SI-4 | System Monitoring | L M H | GuardDuty in all accounts and Regions; Security Hub; flow logs; Network Firewall IDS/IPS | `guardduty-enabled-centralized`, `securityhub-enabled` |
| SI-4(1) | System-Wide Intrusion Detection System | – | GuardDuty with delegated administrator | Organization configuration |
| SI-4(2) | Automated Tools and Mechanisms for Real-Time Analysis | M H | GuardDuty; CloudTrail Insights; CloudWatch anomaly detection | Findings |
| SI-4(4) | Inbound and Outbound Communications Traffic | M H | Flow logs; Network Firewall; GuardDuty network findings; Resolver logs | Logs and findings |
| SI-4(5) | System-Generated Alerts | M H | EventBridge to SNS, chat, or ticketing | Rule definitions |
| SI-4(16) | Correlate Monitoring Information | – | Security Hub correlation; Detective; GuardDuty attack sequences | Findings |
| SI-5 | Security Alerts, Advisories, and Directives | L M H | AWS Health and security bulletins routed to the security team; Inspector | Notification configuration |
| SI-7 | Software, Firmware, and Information Integrity | M H | CloudTrail log file validation; S3 Object Lock and Versioning; code and image signing; S3 checksums | Validation output, lock configuration |
| SI-7(1) | Integrity Checks | M H | Same; file integrity monitoring on instances | Reports |
| SI-10 | Information Input Validation | M H | WAF managed rules; API Gateway request validation | WAF configuration |
| SI-12 | Information Management and Retention | L M H | S3 Lifecycle; Object Lock retention; log retention settings; backup retention | Lifecycle and retention configuration |
| SI-16 | Memory Protection | M H | Inherited at the hypervisor; OS-level settings in hardened images | Image baseline |

## Mostly inherited or procedural families

| Family | Position |
|---|---|
| PE: Physical and Environmental Protection | Inherited from AWS for all AWS data centers. Evidence from Artifact. Your offices and endpoints remain yours. |
| AT: Awareness and Training | Procedural. Record role-based training, including AWS certifications such as those in [exam/](../exam/related-certifications.md), as AT-3 evidence. |
| PL, PM, PS, PT | Procedural and organizational. AWS tooling provides inputs (inventory, findings, architecture records) but does not implement these. |
