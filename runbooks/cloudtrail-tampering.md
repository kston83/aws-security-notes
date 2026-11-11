# CloudTrail tampering and disabled security services

> **Last reviewed:** 2026-11-10 · **Severity:** Critical until explained · **SCS-C03:** 1.3.2, 2.2.4 · **NIST 800-53:** AU-5, AU-9, AU-12, SI-4, IR-4

## Trigger

- GuardDuty `Stealth:IAMUser/CloudTrailLoggingDisabled`, `DefenseEvasion:IAMUser/AnomalousBehavior`, `Stealth:S3/ServerAccessLoggingDisabled`
- Security Hub or Config control for CloudTrail failing
- EventBridge rule matching any of the events below
- A "log source stopped delivering" alarm

Events that indicate tampering with visibility:

| Service | Events |
|---|---|
| CloudTrail | `StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors`, `DeleteEventDataStore`, `PutInsightSelectors` |
| Log storage | `PutBucketPolicy`, `DeleteBucketPolicy`, `PutBucketLifecycle`, `DeleteBucket`, `PutBucketVersioning` on the log bucket; `DeleteLogGroup`, `DeleteLogStream`, `PutRetentionPolicy` |
| KMS | `DisableKey`, `ScheduleKeyDeletion`, `PutKeyPolicy` on the log encryption key |
| GuardDuty | `DeleteDetector`, `UpdateDetector`, `DisassociateFromAdministratorAccount`, `CreateFilter` (suppression), `CreateIPSet`, `DeleteMembers` |
| Security Hub | `DisableSecurityHub`, `BatchDisableStandards`, `DisassociateFromAdministratorAccount`, `UpdateStandardsControl` |
| Config | `StopConfigurationRecorder`, `DeleteConfigurationRecorder`, `DeleteDeliveryChannel`, `DeleteConfigRule` |
| Network | `DeleteFlowLogs`, `DeleteResolverQueryLogConfig` |
| EventBridge, SNS | `DeleteRule`, `DisableRule`, `RemoveTargets`, `DeleteTopic`, `Unsubscribe` on alerting resources |

A subtle one: `PutEventSelectors` can narrow a trail to exclude management events without stopping it. `UpdateTrail` can redirect logs to an attacker's bucket or turn off multi-Region.

## Triage

```bash
aws cloudtrail describe-trails --include-shadow-trails \
  --query 'trailList[].[Name,HomeRegion,IsMultiRegionTrail,IsOrganizationTrail,S3BucketName,LogFileValidationEnabled]' --output table
aws cloudtrail get-trail-status --name TRAIL_NAME \
  --query '[IsLogging,LatestDeliveryTime,LatestDeliveryError,StopLoggingTime,LatestDigestDeliveryTime]'
aws cloudtrail get-event-selectors --trail-name TRAIL_NAME
```

Find who did it. The tampering event itself is recorded before logging stops, and Event history holds 90 days of management events regardless of trail state:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging \
  --query 'Events[].CloudTrailEvent' --output text
```

Decide: authorized change by a known role through the pipeline, or not. An organization trail cannot be altered from a member account, so tampering with one implicates the management account or the CloudTrail delegated administrator. Treat that as critical.

## Contain

**1. Restore logging first.** Every minute without it is a blind spot.

```bash
aws cloudtrail start-logging --name TRAIL_NAME
```

If the trail was deleted or altered, redeploy it from infrastructure as code. If selectors were changed:

```bash
aws cloudtrail put-event-selectors --trail-name TRAIL_NAME --event-selectors '[{"ReadWriteType":"All","IncludeManagementEvents":true}]'
```

(Restore your data event selectors from the IaC definition as well.)

**2. Re-enable other services that were turned off.**

```bash
aws guardduty update-detector --detector-id DETECTOR_ID --enable
aws configservice start-configuration-recorder --configuration-recorder-name RECORDER_NAME
```

For organization-managed services, re-enable from the delegated administrator so member settings are reapplied.

**3. Contain the principal** that made the change with [Compromised IAM credentials](compromised-iam-credentials.md). Tampering with logging is rarely the attacker's only action.

**4. Protect the archive.** Confirm the log bucket's policy, versioning, Object Lock, and lifecycle are intact, and that the KMS key is enabled:

```bash
aws s3api get-bucket-versioning --bucket LOG_BUCKET
aws s3api get-object-lock-configuration --bucket LOG_BUCKET
aws s3api get-bucket-lifecycle-configuration --bucket LOG_BUCKET
aws kms describe-key --key-id LOG_KEY_ID --query 'KeyMetadata.KeyState'
```

If the key is pending deletion, cancel it now: [KMS key scheduled for deletion](kms-key-scheduled-deletion.md).

## Preserve evidence

- Export Event history for the gap window from every Region before it ages out (90 days).
- Record trail status output, selectors, and bucket configuration as found.

## Investigate

**1. Establish the gap.** From `StopLoggingTime` (or the tampering event) to when logging resumed.

**2. Verify integrity of what you do have.**

```bash
aws cloudtrail validate-logs --trail-arn TRAIL_ARN --start-time START_TIME --end-time END_TIME --verbose
```

This reports log files that were modified or deleted after delivery, and missing digest files.

**3. Reconstruct the gap from other sources.**

| Source | Covers |
|---|---|
| CloudTrail Event history | Management events for 90 days, per Region, even with no trail. The main fallback. |
| CloudTrail Lake event data store | If one exists, independent of the trail |
| Other trails | A second trail, or the organization trail if a local trail was the one tampered with |
| Config | Resource changes during the gap (if the recorder was running) |
| VPC Flow Logs, Resolver logs | Network activity |
| GuardDuty | Reads its own event stream and is unaffected by your trail's state |
| S3 server access logs, ELB logs, service logs | Data-plane activity |
| Billing and Cost Explorer | Resources launched |

Data events during the gap are not recoverable from Event history.

**4. Look at what else the principal did** before and after, with the queries in [CLI one-liners](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail).

## Eradicate and recover

- Redeploy logging and detection configuration from source, and check for drift everywhere, not just where the alert fired.
- Delete suppression rules, trusted IP lists, and automation rules you did not create.
- Remove attacker access per the credentials runbook.
- Confirm delivery end to end: a new log file in the bucket, a new digest, a GuardDuty sample finding reaching the responder.

## Follow up

| Gap | Fix |
|---|---|
| Trail could be stopped by account principals | Organization trail; SCP denying CloudTrail, GuardDuty, Config, and Security Hub changes except by a security role. [Org policies](../cheatsheets/org-policies-scp-rcp.md#scp-patterns) |
| Logs could be deleted | Log archive account; Object Lock compliance mode; versioning; deny-delete SCP |
| Could not prove integrity | Log file validation on every trail |
| Slow to notice | EventBridge rules on the events above; alarm on absence of log delivery |
| Single source of truth | CloudTrail Lake event data store or a second copy |
| Too many principals with the permission | Review who holds `cloudtrail:*`, `guardduty:*`, `config:*`; use unused access findings |
