# KMS key scheduled for deletion or disabled

> **Last reviewed:** 2026-11-10 · **Severity:** High; Critical if the key protects production data or backups · **SCS-C03:** 5.2.1, 5.3.5 · **NIST 800-53:** SC-12, SC-12(1), SC-28, CP-9, IR-4

## Trigger

- EventBridge rule on `ScheduleKeyDeletion`, `DisableKey`, `DeleteImportedKeyMaterial`, `PutKeyPolicy`, `RevokeGrant`, or `DisconnectCustomKeyStore`
- Config rule `kms-cmk-not-scheduled-for-deletion` noncompliant
- CloudWatch alarm on `KMSInvalidStateException` or `DisabledException` errors
- Workloads failing to read encrypted data

Deleting a key makes everything encrypted under it permanently unreadable. The waiting period (7 to 30 days) is your only window.

## Triage

```bash
aws kms describe-key --key-id KEY_ID \
  --query 'KeyMetadata.[KeyId,Arn,KeyState,KeyManager,Origin,DeletionDate,PendingDeletionWindowInDays,MultiRegion,Description]'
aws kms list-aliases --key-id KEY_ID --query 'Aliases[].AliasName'
aws kms list-resource-tags --key-id KEY_ID
```

Who did it:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=KEY_ARN \
  --query 'Events[?EventName==`ScheduleKeyDeletion` || EventName==`DisableKey` || EventName==`PutKeyPolicy`].CloudTrailEvent' --output text
```

Decide:

| Situation | Action |
|---|---|
| Planned decommission with a ticket, and the usage check below shows no dependency | Let it proceed; note in the record |
| Planned, but something still uses the key | Cancel and tell the owner |
| Unplanned or unknown | Cancel immediately, then investigate |

Cancelling is safe and reversible. When unsure, cancel.

## Contain

**1. Cancel deletion and re-enable.** Cancelling leaves the key disabled; enable it as a separate step.

```bash
aws kms cancel-key-deletion --key-id KEY_ID
aws kms enable-key --key-id KEY_ID
aws kms describe-key --key-id KEY_ID --query 'KeyMetadata.KeyState'     # expect "Enabled"
```

**2. If the key policy was changed,** restore it from version control or Config history.

```bash
aws kms get-key-policy --key-id KEY_ID --policy-name default --query Policy --output text > evidence/KEY_ID-policy-found.json
aws kms put-key-policy --key-id KEY_ID --policy-name default --policy file://KEY_ID-policy-good.json
```

If the policy locks everyone out, including administrators and the account, only AWS Support can help. Open a case at once.

**3. If imported key material was deleted,** re-import the same material from your escrow copy. A different key material will not decrypt existing ciphertext.

**4. If a multi-Region key is involved,** check the primary and each replica; they are deleted independently.

**5. Contain the principal** if the action was not authorized: [Compromised IAM credentials](compromised-iam-credentials.md).

## Investigate

**What depends on the key.** There is no single API for this. Combine:

- **CloudTrail:** recent `Decrypt`, `GenerateDataKey`, and `CreateGrant` events for the key ARN show active users. The encryption context shows which resource.

```sql
SELECT eventname, useridentity.arn, 
       json_extract_scalar(requestparameters, '$.encryptionContext') AS ctx, count(*) AS n
FROM cloudtrail_logs
WHERE eventsource = 'kms.amazonaws.com'
  AND resources[1].arn = 'KEY_ARN'
  AND eventtime > 'START_TIME'
GROUP BY 1,2,3 ORDER BY n DESC;
```

- **Grants:** `aws kms list-grants --key-id KEY_ID` lists services and resources granted use.
- **Resource inventory:** search Config (advanced query or aggregator) for resources referencing the key: EBS volumes and snapshots, RDS instances and snapshots, S3 bucket default encryption, Secrets Manager secrets, backup vaults, log groups, SNS topics, SQS queues.

```bash
aws configservice select-resource-config --expression \
  "SELECT resourceId, resourceType WHERE configuration.kmsKeyId = 'KEY_ARN'"
```

Property names differ by resource type (`kmsKeyId`, `kmsMasterKeyId`, `encryption.kmsKeyId`), so run it per type you care about.

**Why it happened.** Mistaken clean-up of "unused" keys is the common cause. Malicious deletion as a destructive act or extortion is the serious one; look for accompanying snapshot deletion, backup deletion, or data re-encryption, and go to [Ransomware and data destruction](ransomware-data-destruction.md) if you find them.

**What broke while the key was unusable.** Services cache data keys for varying times, so failures can appear late: EBS volumes fail on next attach or instance start, RDS instances can move to an inaccessible state and may need restoring from a snapshot once the key is back.

## Recover

- Restart or recover affected workloads once the key is enabled. For RDS instances in an inaccessible-encryption state, follow the service's recovery guidance; restoring from a snapshot may be required.
- Verify by decrypting a known ciphertext or reading a known object.
- Confirm backups encrypted with the key are readable with a test restore.

## Follow up

| Gap | Fix |
|---|---|
| Too many principals can delete keys | Key policy separating administrators from users; SCP denying `kms:ScheduleKeyDeletion` and `kms:DisableKey` except for a key-admin role. [KMS cheatsheet](../cheatsheets/kms.md#key-policy) |
| Short waiting period chosen | Policy condition `kms:ScheduleKeyDeletionPendingWindowInDays` requiring 30 days |
| No alert | EventBridge rule on `ScheduleKeyDeletion` and `DisableKey`; alarm on KMS invalid-state errors |
| Key and data in the same blast radius | Backups encrypted with a key in a separate account |
| No decommission process | Disable first, wait, watch for errors, then schedule deletion |
| Unknown dependencies | Tag keys with owner and purpose; one key per data classification or application |
