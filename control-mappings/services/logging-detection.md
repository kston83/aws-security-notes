# Control impact: logging and detection services

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching note:** [Domain 1](../../teaching/01-detection.md)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

## CloudTrail

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Organization trail, multi-Region, management events | AU-2, AU-3, AU-12, AU-12(1), AC-6(9), AC-2(4) | I | API activity unrecorded in some accounts or Regions; Event history only, 90 days | Trail configuration | `multi-region-cloudtrail-enabled` (CloudTrail.1) |
| Data events for sensitive resources | AU-2, AU-3(1), AU-12 | I | No record of object reads, item access, or function invocations | Event selectors | `cloudtrail-s3-dataevents-enabled` |
| Log file integrity validation | AU-9, AU-9(3), AU-10, SI-7 | I | Cannot show logs are complete and unaltered | Digest files; `validate-logs` output | `cloud-trail-log-file-validation-enabled` (CloudTrail.4) |
| SSE-KMS encryption of log files | AU-9, SC-28 | I | Log contents readable by anyone with bucket access | Trail and key policy | `cloud-trail-encryption-enabled` (CloudTrail.2) |
| Delivery to a log archive account bucket with restricted policy | AU-9, AU-9(2), AU-9(4), AC-5 | I | Workload administrators can read, alter, or delete their own audit trail | Bucket policy; account structure | `s3-bucket-policy-grantee-check`, custom |
| Object Lock and lifecycle on the log bucket | AU-11, AU-9, SI-12 | I | Logs deleted early or kept without limit | Bucket configuration | `s3-bucket-default-lock-enabled` |
| Trail integrated with CloudWatch Logs; metric filters and alarms | AU-6, AU-6(1), SI-4(5), AU-5 | I | No near-real-time alerting on specific API activity | Log group, filters, alarms | `cloud-trail-cloud-watch-logs-enabled` (CloudTrail.5) |
| Alarm on trail delivery failure or `StopLogging` | AU-5, SI-4(5) | I | Logging failure goes unnoticed | Alarm and rule definitions | Custom |
| SCP denying trail changes | AU-9, AC-6(1), CM-5 | I | Any administrator can stop or redirect logging | SCP | Control Tower mandatory control |
| CloudTrail Lake event data store | AU-6, AU-7, AU-11 | S, E | Long-range queries need custom tooling | Event data store configuration | Manual |
| Insights events | SI-4(2), AU-6 | S | Unusual API volume or error rates not flagged | Insight selectors | Manual |

## CloudWatch

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| OS and application logs shipped by the CloudWatch agent | AU-2, AU-12, SI-4 | I | Host-level events stay on hosts and are lost with them | Agent configuration; log groups | `ec2-instance-managed-by-systems-manager` plus custom |
| Log group retention set | AU-11, SI-12 | I | Logs kept forever at cost, or expired before the retention requirement | Log group settings | `cw-loggroup-retention-period-check` |
| Log groups encrypted with KMS | AU-9, SC-28 | I | Sensitive log content protected only by IAM on the log group | Log group settings | `cloudwatch-log-group-encrypted` |
| Alarms with actions configured | SI-4(5), AU-5, IR-6 | I | Alarm fires and nobody is told | Alarm definitions | `cloudwatch-alarm-action-check` |
| Cross-account observability to a monitoring account | AU-6(3), SI-4(16) | S | Analysts must sign in to each account | Sink and link configuration | Manual |
| Subscription filters to SIEM or Security Lake | AU-6(3), AU-6(1) | S | Logs not correlated with other sources | Subscription filters | Manual |

## Config

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Recorder on in every account and Region, all resource types | CM-8, CM-8(1), CM-2(2), CM-3, AU-2 | I | No inventory or configuration history; Security Hub controls cannot evaluate | Recorder status | `config-enabled` (Config.1) |
| Organization aggregator in the security account | CM-8, CA-7, AU-6(3) | S, E | No fleet-wide view | Aggregator configuration | Manual |
| Managed and custom rules; conformance packs | CM-6, CA-2, CA-7 | I | Configuration settings unverified | Compliance status | Conformance pack status |
| Automatic remediation | CM-6(1), SI-2, IR-4(1) | I | Noncompliance persists until a human acts | Remediation configuration and history | Manual |
| Delivery of history and snapshots to the log archive | AU-9, AU-11, CM-3 | E | Configuration history lost with the account | Delivery channel | Manual |

## GuardDuty

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Enabled in every account and Region with delegated administrator and auto-enable | SI-4, SI-4(1), SI-4(2), SI-4(4), AU-6, CA-7, RA-3 | I | No managed threat detection; new accounts unmonitored | Organization configuration | `guardduty-enabled-centralized` (GuardDuty.1) |
| S3, EKS, RDS, Lambda protection and Runtime Monitoring | SI-4, SI-4(23), AC-2(12) | I | Data-plane, container, database, and host threats undetected | Feature status per account | `guardduty-s3-protection-enabled`, `guardduty-eks-protection-audit-enabled`, `guardduty-runtime-monitoring-enabled` |
| Malware Protection for EC2, S3, and backups | SI-3 | I | No malware scanning of volumes, uploaded objects, or recovery points | Scan configuration and results | `guardduty-malware-protection-enabled` |
| Findings routed to responders through EventBridge | SI-4(5), IR-4, IR-5, IR-6, AU-6(1) | I | Findings sit unread in the console | Rules and targets | Custom |
| Findings not left unresolved | IR-4, IR-5, SI-4 | S, E | Detection without response | Finding age and status | `guardduty-non-archived-findings` |
| Suppression rules and trusted IP lists reviewed | SI-4, CM-3 | S | Over-broad suppression hides real threats | Filter list; review records | Manual |

## Security Hub, Detective, Security Lake, Inspector, Macie

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Security Hub enabled organization-wide with cross-Region aggregation | CA-7, AU-6, AU-6(3), SI-4(16), RA-5 | I | Findings scattered by account, Region, and service | Central configuration | `securityhub-enabled` |
| Standards enabled: FSBP, CIS, NIST 800-53 | CA-2, CA-7, CM-6 | I, E | No continuous assessment against a baseline | Standards status and scores | Manual |
| Automation rules and custom actions | IR-4(1), AU-6(1) | S | Triage is manual for every finding | Rule definitions | Manual |
| Detective enabled | IR-4, AU-6, AU-7, SI-4(16) | S | Investigation requires hand-built queries across sources | Behavior graph membership | Manual |
| Security Lake collecting native and custom sources | AU-6(3), AU-12(1), AU-4, AU-11 | S | No normalized, central store for cross-source analysis | Source and subscriber configuration | Manual |
| Inspector enabled for EC2, ECR, Lambda | RA-5, RA-5(2), SI-2, SI-2(2) | I | Vulnerabilities in hosts, images, and functions unknown | Coverage and findings | `inspector-ec2-scan-enabled`, `inspector-ecr-scan-enabled`, `inspector-lambda-standard-scan-enabled` |
| Macie enabled | RA-2, CM-12, SI-12 | S, E | Sensitive data location unknown | Findings | `macie-status-check` |
| AWS Health events and security contact routed to the security team | SI-5, IR-6 | I | AWS notifications about abuse or exposed keys go unread | Alternate contact; EventBridge rule | `account-contact-details-configured` (Account.1) |
