# S3 data exposure

> **Last reviewed:** 2026-11-10 · **Severity:** High; Critical if regulated data · **SCS-C03:** 2.2.3, 2.2.4, 5.2.x · **NIST 800-53:** IR-4, IR-6, AC-3, AC-21, AC-22, SC-28

## Trigger

- GuardDuty `Policy:S3/BucketPublicAccessGranted`, `Policy:S3/BucketAnonymousAccessGranted`, `Policy:S3/BucketBlockPublicAccessDisabled`, `Policy:S3/AccountBlockPublicAccessDisabled`, `Exfiltration:S3/*`, `UnauthorizedAccess:S3/*`
- IAM Access Analyzer external access finding on a bucket
- Macie policy finding or sensitive data finding on an exposed bucket
- Security Hub or Config S3 public access control failing
- External report that data is reachable

## Triage

```bash
aws s3control get-public-access-block --account-id ACCOUNT_ID
aws s3api get-public-access-block --bucket BUCKET
aws s3api get-bucket-policy-status --bucket BUCKET
aws s3api get-bucket-policy --bucket BUCKET --query Policy --output text
aws s3api get-bucket-acl --bucket BUCKET
aws s3api get-bucket-ownership-controls --bucket BUCKET
aws s3control list-access-points --account-id ACCOUNT_ID --bucket BUCKET
aws s3api get-bucket-tagging --bucket BUCKET
```

Establish:

1. **How is it exposed?** Public bucket policy, public ACL, cross-account grant to an unknown account, access point policy, or a presigned URL in circulation.
2. **Is exposure intended?** Check tags and ask the owner. Public website assets are meant to be public; a bucket named for backups is not.
3. **What is in it?** Classification tag, Macie findings, or a quick listing of prefixes. This sets severity and notification duties.
4. **Since when?** Find the change in CloudTrail (see Investigate).

## Contain

**1. Block public access on the bucket.** Immediate, overrides public policies and ACLs, reversible.

```bash
aws s3api put-public-access-block --bucket BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Side effect: legitimate public readers lose access. If the bucket hosts a public site, serve it through CloudFront with origin access control instead.

**2. Cross-account exposure** is not covered by Block Public Access. Save the current policy, then remove the offending statement or add an explicit deny for principals outside the organization:

```bash
aws s3api get-bucket-policy --bucket BUCKET --query Policy --output text > evidence/BUCKET-policy-before.json
# edit, then:
aws s3api put-bucket-policy --bucket BUCKET --policy file://BUCKET-policy-fixed.json
```

Deny statement: [S3 cheatsheet, organization only](../cheatsheets/s3-security.md#common-bucket-policy-statements).

**3. Presigned URLs.** They cannot be revoked individually. Invalidate them by removing the signer's permission or credentials: deactivate the signing user's key, or revoke the signing role's sessions. See [Compromised IAM credentials](compromised-iam-credentials.md#contain).

**4. If a principal is actively exfiltrating,** contain that principal with the credentials runbook, and consider an explicit deny on the bucket for everything except the responder role.

**5. Turn on account-level Block Public Access** if it was off and nothing in the account needs public buckets.

## Preserve evidence

- The bucket policy, ACL, and public access block configuration as found (step 2 above saved the policy).
- Config history for the bucket:

```bash
aws configservice get-resource-config-history --resource-type AWS::S3::Bucket --resource-id BUCKET --limit 10 > evidence/BUCKET-config-history.json
```

- CloudTrail and server access log extracts for the exposure window.

## Investigate

**Who exposed it, and when.** Management events are always available:

```sql
SELECT eventtime, useridentity.arn, eventname, sourceipaddress, requestparameters
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'BUCKET'
  AND eventname IN ('PutBucketPolicy','DeleteBucketPolicy','PutBucketAcl','PutBucketPublicAccessBlock',
                    'DeleteBucketPublicAccessBlock','PutBucketOwnershipControls','CreateAccessPoint','PutAccessPointPolicy')
ORDER BY eventtime;
```

If the change was unexpected for that principal, run the credentials runbook for it.

**What was accessed.** This depends on what logging was on *before* the incident:

| Source | Shows | Limits |
|---|---|---|
| CloudTrail data events | Each `GetObject`, `ListObjects`, with principal and IP | Only if data events were enabled for the bucket. Anonymous requests appear with an anonymous principal. |
| S3 server access logs | Each request including anonymous ones, with requester, IP, key, bytes | Best effort; only if enabled |
| GuardDuty S3 Protection | Anomalous access patterns | Derived from data events GuardDuty reads itself; gives findings, not a full record |
| CloudFront or ALB logs | Requests through those paths | |

```sql
-- Data events: reads from outside the organization's accounts
SELECT eventtime, useridentity.type, useridentity.accountid, useridentity.arn, sourceipaddress, eventname,
       json_extract_scalar(requestparameters, '$.key') AS object_key
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'BUCKET'
  AND eventname IN ('GetObject','ListObjects','ListObjectsV2','CopyObject')
  AND eventtime BETWEEN 'START_TIME' AND 'END_TIME'
ORDER BY eventtime;
```

If neither data events nor access logs were enabled, you cannot show what was read. Record that plainly; for notification purposes the usual assumption is that everything exposed was accessed.

**What the data is.** Run a Macie sensitive data discovery job on the bucket if it has not been classified.

**Were objects changed or added?** Look for `PutObject` and `DeleteObject` from unexpected principals. A writable public bucket can be used to plant content.

## Eradicate

- Correct the bucket policy and ACLs to least privilege. Set Object Ownership to bucket owner enforced to retire ACLs.
- Remove unexpected access points and replication rules.
- If credentials or secrets were among the exposed objects, rotate all of them.
- Remove planted objects; restore changed ones from earlier versions.

## Recover

- Restore legitimate access paths deliberately: specific principals, CloudFront with origin access control, or access points scoped to a VPC.
- Confirm with Access Analyzer that no external access findings remain for the bucket.
- Decide on notification with legal and privacy leads, based on the data classification and the access evidence. Record the decision (IR-6).

## Follow up

| Gap | Fix |
|---|---|
| Block Public Access could be turned off | SCP denying `s3:PutAccountPublicAccessBlock` and `s3:PutBucketPublicAccessBlock` except for a platform role |
| Cross-account access unconstrained | RCP or bucket policy requiring `aws:PrincipalOrgID`. [Org policies](../cheatsheets/org-policies-scp-rcp.md#rcp-patterns) |
| No record of reads | CloudTrail data events on sensitive buckets |
| Unknown data sensitivity | Macie automated discovery; classification tags |
| Slow detection | Access Analyzer organization analyzer; Security Hub S3 controls; EventBridge rule on `PutBucketPolicy` |
| Baseline drift | [S3 baseline checklist](../cheatsheets/s3-security.md#baseline-for-a-sensitive-bucket) enforced by Config rules with remediation |
