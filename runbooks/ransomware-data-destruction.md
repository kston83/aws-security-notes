# Ransomware and data destruction

> **Last reviewed:** 2026-11-10 · **Severity:** Critical · **SCS-C03:** 2.2.4, 5.2.2, 5.2.4 · **NIST 800-53:** IR-4, CP-9, CP-10, SC-28, SI-7, AU-6

## Trigger

- Ransom note found in a bucket, database, or file system
- GuardDuty `Impact:S3/*`, `Exfiltration:S3/*`, `Impact:EC2/*`, or an `AttackSequence` finding involving data
- Mass `DeleteObject`, `DeleteObjects`, `PutObject` with unfamiliar encryption, `DeleteDBInstance`, `DeleteSnapshot`, `DeleteRecoveryPoint`, `ScheduleKeyDeletion`, or `PutBucketLifecycleConfiguration` events
- Applications reporting unreadable or missing data
- Files on instances encrypted by malware

## How it happens on AWS

| Pattern | Mechanism |
|---|---|
| Delete and demand | Attacker with stolen credentials copies data out, deletes objects, snapshots, and backups, leaves a note |
| Re-encrypt in place | Attacker overwrites objects using encryption you cannot reverse: SSE-C with their key, or a KMS key in their account or one whose material they then delete |
| Lifecycle abuse | Attacker sets a lifecycle rule to expire all objects within a day |
| Key destruction | Attacker schedules deletion of your KMS keys |
| Host ransomware | Malware on instances encrypts attached EBS, EFS, or FSx file systems |
| Database | Attacker drops tables or deletes instances and snapshots |

Almost all of these start with compromised credentials. Containment of identity comes first.

## Triage

Answer quickly:

1. **Is it still happening?** Check CloudTrail for the last few minutes of destructive events.
2. **Which principal?** That is your first containment target.
3. **What is affected?** Buckets, databases, volumes, keys, accounts.
4. **Do backups exist outside the attacker's reach?** A backup account, a locked vault, replicated buckets.

Declare a critical incident. Engage the incident commander, legal, and AWS Support (or AWS Security Incident Response). Do not contact the attacker or pay without executive and legal direction.

## Contain

**1. Stop the principal.** Follow [Compromised IAM credentials](compromised-iam-credentials.md#contain). If the principal is unclear or there are several, attach the quarantine SCP to the account now.

```bash
aws organizations attach-policy --policy-id QUARANTINE_POLICY_ID --target-id ACCOUNT_ID
```

**2. Stop destructive lifecycle rules.** Lifecycle actions run asynchronously, so removing the rule quickly can save most objects.

```bash
aws s3api get-bucket-lifecycle-configuration --bucket BUCKET > evidence/BUCKET-lifecycle-found.json
aws s3api delete-bucket-lifecycle --bucket BUCKET        # removes ALL lifecycle rules; restore the legitimate ones later
```

**3. Cancel pending KMS key deletions.** See [KMS key scheduled for deletion](kms-key-scheduled-deletion.md).

```bash
for k in $(aws kms list-keys --query 'Keys[].KeyId' --output text); do
  s=$(aws kms describe-key --key-id "$k" --query 'KeyMetadata.KeyState' --output text)
  [ "$s" = "PendingDeletion" ] && echo "PENDING: $k"
done
```

**4. Protect what backups remain.** Confirm state before anything else touches them.

```bash
aws backup list-backup-vaults --query 'BackupVaultList[].[BackupVaultName,Locked,NumberOfRecoveryPoints]' --output table
aws ec2 describe-snapshots --owner-ids self --query 'length(Snapshots)'
aws rds describe-db-snapshots --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' --output table
```

Check the EBS and RDS **Recycle Bin** and RDS retained automated backups for anything deleted that can be restored.

**5. Add a temporary bucket policy deny** on affected buckets for all writes and deletes except the responder role, if the account is not quarantined.

**6. For host ransomware,** isolate affected instances with [Compromised EC2 instance](compromised-ec2-instance.md) and unmount shared file systems from unaffected hosts.

## Preserve evidence

- Ransom notes: copy with metadata (`head-object` output shows encryption type and the uploader's timestamp).
- A sample of affected objects' metadata:

```bash
aws s3api head-object --bucket BUCKET --key SAMPLE_KEY
# SSECustomerAlgorithm present => SSE-C; SSEKMSKeyId shows which KMS key (check the account ID in the ARN)
```

- CloudTrail extracts for the attack window, IAM snapshot, bucket configurations as found.

## Investigate

- **Timeline of destructive actions** by principal, from CloudTrail management and data events.
- **Exfiltration before destruction.** `GetObject` volume, replication rules added, snapshots shared or copied to other accounts (`ModifySnapshotAttribute`, `ModifyDBSnapshotAttribute`, `CopySnapshot`), flow log byte counts, DataSync or Transfer Family activity. Assume data was taken if the attacker had read access, and treat this as a data breach too. See [S3 data exposure](s3-data-exposure.md#investigate).
- **How objects were encrypted.**

| Finding | Recoverability |
|---|---|
| Objects deleted, versioning on | Recoverable: remove delete markers or restore previous versions |
| Objects overwritten, versioning on | Recoverable: previous versions exist unless the attacker also deleted versions |
| Versions permanently deleted, no Object Lock | Not recoverable from the bucket; use replicas or backups |
| SSE-C with attacker's key | Not recoverable without the key; restore previous versions or backups |
| KMS key in attacker's account | Same |
| Your KMS key pending deletion | Recoverable if cancelled in time |

- **Initial access and persistence.** As in the credentials runbook. Eradication must be complete before recovery, or the attacker repeats the attack on restored data.

## Eradicate

- Remove all attacker access and persistence across accounts and Regions.
- Rotate all credentials and secrets the compromised principals could reach.
- Rebuild compromised compute from clean images.

## Recover

Recover into a clean state. If confidence in the account is low, restore into a new account.

**S3, versioned bucket: undo deletions** by removing delete markers.

```bash
aws s3api list-object-versions --bucket BUCKET --prefix PREFIX \
  --query 'DeleteMarkers[?IsLatest==`true`].[Key,VersionId]' --output text |
while read -r key vid; do
  aws s3api delete-object --bucket BUCKET --key "$key" --version-id "$vid"
done
```

For large buckets or overwritten objects, use S3 Batch Operations with an inventory of the versions to restore (copy the last good version over the top). Choose the last good version by timestamp before the attack began.

**Other stores**

| Store | Recovery path |
|---|---|
| S3 without versions | Replica bucket; AWS Backup recovery point |
| EBS | Snapshots; Recycle Bin; AWS Backup |
| RDS / Aurora | Point-in-time restore to before the attack; snapshots; retained automated backups; Aurora backtrack |
| DynamoDB | Point-in-time recovery; on-demand backups |
| EFS / FSx | AWS Backup recovery points |
| Anything in AWS Backup | Restore from the vault; from the logically air-gapped vault or backup account if the primary vault is damaged |

Before reconnecting restored data to production: verify integrity, scan for malware (GuardDuty Malware Protection covers S3, EBS, and backups), and confirm the entry point is closed.

Restore legitimate lifecycle rules removed during containment. Detach the quarantine SCP last.

## Follow up

This incident type is decided before it starts. Controls, in order of value:

| Control | Detail |
|---|---|
| Immutable backups | AWS Backup Vault Lock in compliance mode; S3 Object Lock for critical buckets |
| Backups out of reach | Cross-account copy to a dedicated backup account; logically air-gapped vault; separate KMS key there |
| Versioning | On for all important buckets, with lifecycle for noncurrent versions; MFA delete where practical |
| Deny destructive actions | SCPs denying `backup:DeleteRecoveryPoint`, `backup:DeleteBackupVault`, `ec2:DeleteSnapshot`, `rds:DeleteDBSnapshot`, `kms:ScheduleKeyDeletion`, `s3:PutLifecycleConfiguration` except for named roles |
| Block foreign encryption | Bucket policy denying SSE-C and denying KMS keys other than yours. [S3 cheatsheet](../cheatsheets/s3-security.md#encryption) |
| Recycle Bin | Retention rules for EBS snapshots and AMIs |
| No long-term keys | Most of these attacks start with one |
| Detection | GuardDuty S3 Protection; CloudTrail data events on critical buckets; alarms on mass delete, lifecycle change, key deletion |
| Proof | AWS Backup restore testing on a schedule; a recovery exercise at least yearly |

Teaching note: [Domain 5, backup and replication](../teaching/05-data-protection.md#backup-and-replication).
