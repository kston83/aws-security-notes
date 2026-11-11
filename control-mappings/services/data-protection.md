# Control impact: data protection services

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching note:** [Domain 5](../../teaching/05-data-protection.md)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

## KMS and CloudHSM

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Customer managed keys for sensitive data | SC-12, SC-28(1), AC-3 | I | No organizational control over key policy, sharing, or disablement | Key inventory; resource encryption settings | Service-specific rules |
| Key policy separates administrators from users | AC-5, AC-6, SC-12 | I | Those who manage keys can also read the data | Key policies | Custom |
| Automatic key rotation enabled | SC-12 | I | Key material lifetime unbounded | Rotation status | `cmk-backing-key-rotation-enabled` (KMS.4) |
| Deletion guarded: SCP, 30-day window, alert on `ScheduleKeyDeletion` | SC-12(1), CP-9, SI-4(5) | I | Accidental or malicious key deletion destroys data | SCP; EventBridge rule; CloudTrail | `kms-cmk-not-scheduled-for-deletion` (KMS.3) |
| Encryption context required in policies and grants | AC-3, SC-28 | I | Ciphertext can be decrypted outside its intended context | Key policy conditions | Custom |
| KMS events in CloudTrail | AU-2, AU-12, AC-6(9) | E | No record of key use | CloudTrail | `cloudtrail-enabled` |
| Imported key material with escrow copy and expiry process | SC-12, SC-12(1) | I | Key material lost on expiry or deletion; data unrecoverable | Import records; escrow procedure | Manual |
| External key store or CloudHSM | SC-12(6), SC-28(3), SC-13 | I | Requirement for keys outside the provider or in single-tenant HSMs unmet | Key store configuration | Manual |
| Multi-Region keys only where needed, replication permission restricted | SC-12, AC-4 | I | Key material spreads to Regions outside the boundary | `kms:ReplicateKey` grants; key list | Custom |

## S3

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Block Public Access at account level | AC-3, AC-22, SC-7 | I | One permissive policy or ACL makes data public | Account setting | `s3-account-level-public-access-blocks-periodic` (S3.1) |
| Block Public Access at bucket level | AC-3, AC-22 | I | Same, per bucket | Bucket setting | `s3-bucket-level-public-access-prohibited` (S3.8) |
| Bucket policy denies non-TLS requests | SC-8, SC-8(1) | I | Data and credentials can transit in clear text | Bucket policy | `s3-bucket-ssl-requests-only` (S3.5) |
| Default encryption with SSE-KMS customer managed key | SC-28, SC-28(1), SC-12 | I | Encryption without organizational key control | Bucket encryption configuration | `s3-default-encryption-kms` |
| Object Ownership: bucket owner enforced | AC-3 | I | ACLs create access paths outside policy review | Ownership controls | `s3-bucket-acl-prohibited` |
| Versioning | CP-9, SI-7, CP-10 | I | Overwrites and deletions are unrecoverable | Versioning status | `s3-bucket-versioning-enabled` |
| Object Lock (compliance mode) | AU-9, SI-7, SI-12, AU-11 | I | Records can be altered or deleted before retention ends | Lock configuration | `s3-bucket-default-lock-enabled` |
| Lifecycle rules for retention and disposal | SI-12, AU-11 | I | Data kept past its disposal date or deleted early | Lifecycle configuration | `s3-lifecycle-policy-check` |
| Cross-Region or cross-account replication | CP-6, CP-9 | I | Single location for critical data | Replication rules | `s3-bucket-replication-enabled` |
| CloudTrail data events on sensitive buckets | AU-2, AU-3(1), AU-12 | E | No record of who read which object | Event selectors | `cloudtrail-s3-dataevents-enabled` |
| Server access logging | AU-2, AU-12 | E | No request-level record including anonymous access | Logging configuration | `s3-bucket-logging-enabled` |
| Organization-only bucket policy or RCP | AC-3, AC-4, AC-21 | I | Bucket shareable with any external account | Policy text | Access Analyzer |

## EBS, RDS, DynamoDB, EFS

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| EBS encryption by default | SC-28, SC-28(1) | I | New volumes and snapshots created unencrypted | Account setting per Region | `ec2-ebs-encryption-by-default` (EC2.7) |
| Attached volumes encrypted | SC-28 | I | Data readable from snapshots or shared volumes | Volume attributes | `encrypted-volumes` (EC2.3) |
| Snapshots not public; block public access for snapshots | AC-3, AC-22 | I | Disk contents downloadable by anyone | Snapshot attributes; account setting | `ebs-snapshot-public-restorable-check` (EC2.1) |
| RDS storage encryption | SC-28, SC-28(1) | I | Database files and backups unencrypted | Instance attributes | `rds-storage-encrypted` (RDS.3) |
| RDS not publicly accessible | SC-7, AC-3 | I | Database reachable from the internet | Instance attributes | `rds-instance-public-access-check` (RDS.2) |
| RDS snapshots private | AC-3, AC-22 | I | Database contents restorable by anyone | Snapshot attributes | `rds-snapshots-public-prohibited` (RDS.1) |
| RDS TLS required (`rds.force_ssl`, `require_secure_transport`) | SC-8, SC-8(1) | I | Database traffic and credentials in clear text | Parameter group | Custom |
| RDS automated backups and retention | CP-9, CP-10 | I | No point-in-time recovery | Instance attributes | `db-instance-backup-enabled` |
| RDS IAM authentication or Secrets Manager managed credentials | IA-5, IA-2 | I | Static shared database passwords | Instance and secret configuration | `rds-instance-iam-authentication-enabled` |
| DynamoDB point-in-time recovery | CP-9, CP-10 | I | Deleted or corrupted items unrecoverable | Table settings | `dynamodb-pitr-enabled` |
| DynamoDB customer managed key | SC-28(1), SC-12 | I | No key control | Table settings | `dynamodb-table-encrypted-kms` |
| EFS encrypted at rest; TLS enforced by file system policy | SC-28, SC-8 | I | File data exposed at rest or in transit | File system settings and policy | `efs-encrypted-check` |

## Secrets, certificates

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Secrets in Secrets Manager with rotation | IA-5, IA-5(1), SC-12 | I | Long-lived static credentials | Secret rotation configuration | `secretsmanager-rotation-enabled-check`, `secretsmanager-scheduled-rotation-success-check` (SecretsManager.1) |
| Secrets encrypted with customer managed key | SC-28(1), AC-3 | I | No second control on secret access | Secret settings | `secretsmanager-using-cmk` |
| No secrets in code, user data, or environment variables | IA-5(7) | S | Credentials exposed in repositories, metadata, and logs | Scan results | Pipeline scanning |
| ACM certificates with automatic renewal; expiry monitored | SC-17, SC-8, IA-5 | I | Expired certificates cause outages or push users to bypass validation | Certificate inventory | `acm-certificate-expiration-check` |
| Private CA hierarchy with revocation | SC-17, IA-5(2) | I | No controlled internal trust root; revoked certificates accepted | CA configuration | Manual |
| ELB and CloudFront TLS security policies set to current versions | SC-8(1), SC-13 | I | Deprecated protocols and ciphers accepted | Listener and distribution settings | `elb-predefined-security-policy-ssl-check`, `cloudfront-viewer-policy-https` |

## Backup and discovery

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| AWS Backup plans applied by organization policy | CP-9, CM-6 | I | Backups depend on each team remembering | Backup policies; job history | `backup-plan-min-frequency-and-min-retention-check` |
| Vault Lock | CP-9, SI-7, AU-9 | I | Backups deletable by a compromised administrator | Vault lock configuration | `backup-recovery-point-manual-deletion-disabled` |
| Cross-account and cross-Region copy; logically air-gapped vault | CP-6, CP-9(3) | I | Backups share the blast radius of the workload | Copy rules | Backup Audit Manager |
| Recovery points encrypted | CP-9(8), SC-28 | I | Backup media readable without key access | Vault settings | `backup-recovery-point-encrypted` |
| Restore testing | CP-4, CP-9(1) | I, E | Backups unproven until needed | Restore test results | Backup Audit Manager |
| Macie enabled with automated discovery | RA-2, CM-12, SI-12 | S, E | Location of sensitive data unknown | Macie findings | `macie-status-check` (Macie.1) |
| CloudWatch Logs data protection policies | SC-28, AC-3 | I | Sensitive values readable in logs by anyone with log access | Policy on log groups | Manual |
