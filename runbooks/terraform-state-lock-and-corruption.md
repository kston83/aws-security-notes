# Terraform state lock and corruption

> **Last reviewed:** 2026-11-11 · **Severity:** Medium; High if production applies are blocked or the state was changed by an unknown principal · **SCS-C03:** 2.2.2, 2.2.4, 5.2.2, 6.2.1 · **Terraform Associate (004):** 6b, 6c, 6d, 7a, 7b · **NIST 800-53:** CP-9, CP-10, CM-3, CM-5, SI-7, AU-6

Usually an operational incident. It becomes a security incident when someone changed the state on purpose: removing a resource from state hides it from Terraform, and editing state can make the next apply destroy or replace things. Background: [state management](../teaching/terraform/06-state-management.md), [state and backends cheatsheet](../cheatsheets/terraform-state-and-backends.md).

## Trigger

- `Error acquiring the state lock`, with a `Lock Info` block (ID, Path, Operation, Who, Version, Created), and no apply known to be running
- An apply failed or was killed part way. Terraform may leave `errored.tfstate` in the working directory when it could not write to the backend.
- `terraform plan` proposes to create everything, or to destroy resources nobody removed from code
- State will not parse, is zero bytes, or is missing; with the legacy DynamoDB lock, a checksum mismatch error on the state object
- Two applies ran at once (`-lock=false`, a forced unlock, or two backends pointing at one key)
- CloudTrail `PutObject`, `DeleteObject`, or `DeleteObjects` on a state key from a principal that is not the pipeline

## Triage

1. **Read the lock.** With S3-native locking (`use_lockfile = true`) the lock is an object beside the state named `STATE_KEY.tflock`. Its body is JSON lock metadata **(verify)**.

```bash
aws s3api head-object --bucket STATE_BUCKET --key STATE_KEY.tflock
aws s3 cp s3://STATE_BUCKET/STATE_KEY.tflock - | jq .
```

Legacy DynamoDB locking (`dynamodb_table`, deprecated) keeps an item whose `LockID` is `STATE_BUCKET/STATE_KEY`, plus a `STATE_BUCKET/STATE_KEY-md5` item holding the state checksum **(verify)**:

```bash
aws dynamodb get-item --table-name LOCK_TABLE --key '{"LockID":{"S":"STATE_BUCKET/STATE_KEY"}}' --query 'Item.Info.S' --output text | jq .
```

2. **Is the holder alive?** `Who` is `user@host` and `Created` is the start time. Check the CI system for a running job, ask the named person, and look for recent API calls by the deployment role:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=ROLE_SESSION_NAME \
  --start-time START_TIME --query 'Events[].[EventTime,EventName]' --output table
```

A lock held by a live apply is not an incident. Wait for it.

3. **Is the state readable?**

```bash
aws s3api list-object-versions --bucket STATE_BUCKET --prefix STATE_KEY \
  --query '{Versions:Versions[].[VersionId,LastModified,Size,IsLatest],DeleteMarkers:DeleteMarkers[].[VersionId,LastModified,IsLatest]}'
aws s3 cp s3://STATE_BUCKET/STATE_KEY - | jq '{serial, lineage, terraform_version, resources: (.resources | length)}'
```

**Serial** increases by one on every state write. **Lineage** is an ID fixed when the state is first created. A lower serial, a different lineage, or a sharp drop in resource count identifies an overwrite.

Escalate to a security incident if the last writer of the state is not the pipeline or a known engineer (see Investigate), and treat the changes it hid as [unexpected drift](terraform-unexpected-drift.md).

## Contain

**1. Stop further writes.** Pause the pipeline for this configuration and tell the team not to run `apply`. Side effect: deployments wait.

**2. Back up before any surgery.** Every later step can make things worse.

```bash
terraform state pull > evidence/state-before-$(date -u +%Y%m%dT%H%M%SZ).json
aws s3api get-bucket-versioning --bucket STATE_BUCKET
```

If `state pull` fails because the object is corrupt, copy the raw object versions instead (Preserve evidence). The backup holds secrets: keep it in the evidence bucket, not the repository.

**3. Release a dead lock,** only after triage step 2 shows the holder is gone. The lock ID is in the error message.

```bash
# changes state: removes the lock; a second writer can now start
terraform force-unlock LOCK_ID
```

Side effect: if the holder is in fact alive, two processes write the same state. `force-unlock` does not touch infrastructure and cannot release a local state lock held by another process. If it fails for S3-native locking, deleting the `.tflock` object has the same effect (`aws s3api delete-object --bucket STATE_BUCKET --key STATE_KEY.tflock`, changes state).

## Preserve evidence

- Every recent version of the state object and the lock file, with version IDs and timestamps:

```bash
aws s3api get-object --bucket STATE_BUCKET --key STATE_KEY --version-id VERSION_ID evidence/state-VERSION_ID.json
```

- The `Lock Info` block, the failed run's log, and any `errored.tfstate`.
- CloudTrail extracts for the state bucket (below).

## Investigate

**1. Who wrote or deleted the state.** Needs CloudTrail data events on the state bucket.

```sql
SELECT eventtime, useridentity.arn, eventname, sourceipaddress, useragent,
       json_extract_scalar(requestparameters, '$.key') AS object_key,
       json_extract_scalar(responseelements, '$.x-amz-version-id') AS version_id
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'STATE_BUCKET'
  AND eventname IN ('PutObject','DeleteObject','DeleteObjects','CopyObject','CompleteMultipartUpload')
  AND eventtime BETWEEN 'START_TIME' AND 'END_TIME'
ORDER BY eventtime;
```

A write whose user agent is not Terraform, or that comes from a person and not the deployment role, was made by hand **(verify)** the user agent string your provider version sends.

**2. What changed between versions.**

```bash
diff <(jq -r '.resources[] | "\(.module // "root") \(.mode).\(.type).\(.name)"' evidence/state-GOOD_VERSION_ID.json | sort) \
     <(jq -r '.resources[] | "\(.module // "root") \(.mode).\(.type).\(.name)"' evidence/state-BAD_VERSION_ID.json | sort)
```

Resources removed from state still exist in AWS and are now unmanaged. Resources added to state that are not in code will be destroyed by the next apply.

**3. What the failed or racing apply did in AWS.** List the deployment role's write calls in the window ([CLI one-liners](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail)). Anything created but absent from state must be imported or deleted.

## Eradicate

Pick the first case that fits.

**A. Apply failed and left `errored.tfstate`.** It is the newest truth. Push it.

```bash
# changes state: overwrites the remote state
terraform state push errored.tfstate
```

**B. Current state is wrong; an earlier version is good.** `state push` refuses a state whose lineage differs from the remote, or whose serial is lower than the remote's. Raise the serial rather than reach for `-force`, which disables both checks.

```bash
jq '{serial, lineage}' evidence/state-GOOD_VERSION_ID.json
jq '.serial = NEW_SERIAL' evidence/state-GOOD_VERSION_ID.json > restore.tfstate     # NEW_SERIAL = current remote serial + 1
# changes state: overwrites the remote state with the restored copy
terraform state push restore.tfstate
```

**C. State deleted, or too corrupt for Terraform to read.** Work on the object directly. Remove the delete marker, or copy the good version over the current one:

```bash
# changes state: removing the delete marker makes the previous version current again
aws s3api delete-object --bucket STATE_BUCKET --key STATE_KEY --version-id DELETE_MARKER_VERSION_ID
# changes state: writes the good version as the newest version
aws s3api put-object --bucket STATE_BUCKET --key STATE_KEY --body evidence/state-GOOD_VERSION_ID.json
```

The bucket's default encryption applies to the new object. Add `--server-side-encryption` and `--ssekms-key-id` if the backend sets `kms_key_id` explicitly.

With DynamoDB locking, the `-md5` item must match the restored object; update or delete it **(verify)**.

**D. No good version exists.** Rebuild with `import` blocks, one per resource, starting from an empty state:

```hcl
import {
  to = aws_s3_bucket.logs
  id = "BUCKET_NAME"
}
```

```bash
terraform plan        # expect: N to import, 0 to add, 0 to change, 0 to destroy
# changes state: records the imported resources in state
terraform apply
```

Import ID formats differ per resource type; check the provider documentation. Practice this in [lab 06](../labs/06-drift-and-import/README.md).

A restored state is older than reality. Anything applied after that version is missing from it: import those resources too.

## Recover

**1. Reconcile state with reality.**

```bash
terraform plan -refresh-only          # read every proposed change
# changes state: accepts live values into state; changes no infrastructure
terraform apply -refresh-only
```

Do not accept a refresh you cannot explain. An unexplained difference goes to [unexpected drift](terraform-unexpected-drift.md).

**2. Confirm a clean plan.** `terraform plan -detailed-exitcode` exits `0` when there is nothing to change and `2` when there is.

**3. Resume the pipeline** and watch the first apply. Remove `restore.tfstate`, `errored.tfstate`, and local backups from working directories.

## Follow up

| Gap | Fix |
|---|---|
| No earlier version to restore | Versioning on the state bucket, with noncurrent versions kept long enough to notice a problem. [Lab 02](../labs/02-remote-state/README.md) |
| State could be deleted or overwritten by hand | Bucket policy allowing writes only from the deployment role; deny `s3:DeleteObjectVersion`; MFA delete or Object Lock where it fits. [S3 cheatsheet](../cheatsheets/s3-security.md#integrity-and-retention) |
| Applies raced | Locking on every backend (`use_lockfile = true`); ban `-lock=false` and `force-unlock` in pipelines; one configuration per state key; CI concurrency limit of one per workspace |
| Nobody knew who changed state | CloudTrail data events on the state bucket; alert on writes by any principal other than the deployment role. [Lab 08](../labs/08-detection-baseline/README.md) |
| Engineers ran state surgery from laptops | State commands (`state rm`, `state mv`, `state push`) only through a reviewed break-glass procedure; prefer `moved`, `removed`, and `import` blocks, which go through code review. [Terraform CLI cheatsheet](../cheatsheets/terraform-cli.md) |
| Interrupted applies | Do not cancel CI jobs mid-apply; give runners a graceful shutdown period |
| Controls not mapped | [IaC control mapping](../control-mappings/services/iac-terraform.md); [securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md) |
