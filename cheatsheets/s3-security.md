# S3 security cheatsheet

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 3.1.2, 4.1.2, 5.2.1–5.2.4 · **Teaching note:** [Domain 5](../teaching/05-data-protection.md) · **Runbook:** [S3 data exposure](../runbooks/s3-data-exposure.md)

## Access control layers

A request to S3 is allowed only if it passes all of these:

| Layer | Set at | Notes |
|---|---|---|
| Organization policies | SCP (caller side), RCP (bucket side) | |
| **Block Public Access** | Account and bucket (and organization) | Overrides policies and ACLs that would grant public access |
| IAM identity policy | Caller | Required for cross-account callers |
| Bucket policy | Bucket | Main resource policy. 20 KB limit. |
| Access point policy | Access point | Bucket policy must delegate to access points |
| ACLs | Bucket and object | Legacy. Disabled by default through Object Ownership. |
| VPC endpoint policy | Endpoint | If the request comes through one |
| KMS key policy | Key | For SSE-KMS objects |

## Block Public Access

| Setting | Effect |
|---|---|
| `BlockPublicAcls` | Rejects new public ACLs |
| `IgnorePublicAcls` | Ignores existing public ACLs |
| `BlockPublicPolicy` | Rejects bucket policies that grant public access |
| `RestrictPublicBuckets` | Limits access to a bucket with a public policy to AWS services and the bucket owner's account |

- Turn on all four at the **account** level. They are on by default for new buckets.
- Prevent anyone turning them off with an SCP denying `s3:PutAccountPublicAccessBlock` and `s3:PutBucketPublicAccessBlock`.
- "Public" means a policy with a wildcard principal and no condition restricting to fixed values such as specific accounts, organization, VPC endpoints, or IP ranges.
- For genuinely public content, serve through CloudFront with origin access control and keep the bucket private.

## Object Ownership

| Setting | Effect |
|---|---|
| **Bucket owner enforced** (default) | ACLs disabled. Bucket owner owns every object. Access is by policy only. |
| Bucket owner preferred | ACLs enabled; owner takes ownership when uploader sends `bucket-owner-full-control` |
| Object writer | Legacy; uploader owns the object |

Keep bucket owner enforced. The classic "cross-account uploads the bucket owner cannot read" problem disappears.

## Encryption

| Option | Key | Notes |
|---|---|---|
| SSE-S3 | S3-managed | Baseline for all new objects |
| SSE-KMS | KMS key | Adds key policy control and audit. Enable Bucket Keys. |
| DSSE-KMS | KMS key, two layers | For specific compliance requirements |
| SSE-C | You send the key with each request | S3 stores only a hash of the key. Disabled by default on new buckets **(verify)**. Has been abused for ransomware; deny it unless needed. |
| Client-side | You | S3 never sees plaintext |

**Enforce a specific KMS key**

```json
{
  "Sid": "DenyWrongKey",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET/*",
  "Condition": {
    "StringNotEqualsIfExists": {
      "s3:x-amz-server-side-encryption-aws-kms-key-id": "arn:aws:kms:REGION:111122223333:key/KEY_ID"
    }
  }
}
```

With `IfExists`, uploads that omit the header fall through to default bucket encryption, which should be set to the same key.

**Deny SSE-C**

```json
{
  "Sid": "DenySSEC",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET/*",
  "Condition": { "Null": { "s3:x-amz-server-side-encryption-customer-algorithm": "false" } }
}
```

## Common bucket policy statements

**Require TLS (and a minimum version)**

```json
{
  "Sid": "DenyInsecureTransport",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::BUCKET", "arn:aws:s3:::BUCKET/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```

Add a second statement with `"NumericLessThan": { "s3:TlsVersion": "1.2" }` for a minimum version.

**Organization only**

```json
{
  "Sid": "DenyOutsideOrg",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::BUCKET", "arn:aws:s3:::BUCKET/*"],
  "Condition": {
    "StringNotEqualsIfExists": { "aws:PrincipalOrgID": "o-EXAMPLE" },
    "BoolIfExists": { "aws:PrincipalIsAWSService": "false" }
  }
}
```

**Specific VPC endpoint only**

```json
{
  "Sid": "DenyNotFromEndpoint",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::BUCKET", "arn:aws:s3:::BUCKET/*"],
  "Condition": { "StringNotEquals": { "aws:SourceVpce": "vpce-0123456789abcdef0" } }
}
```

This also blocks console access and AWS services acting on your behalf. Add exceptions deliberately, for example with `aws:PrincipalArn` or `aws:ViaAWSService`.

**CloudFront origin access control**

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "cloudfront.amazonaws.com" },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::BUCKET/*",
  "Condition": { "StringEquals": { "aws:SourceArn": "arn:aws:cloudfront::111122223333:distribution/DIST_ID" } }
}
```

**Service log delivery (CloudTrail example)**

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "cloudtrail.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::BUCKET/AWSLogs/*",
  "Condition": {
    "StringEquals": {
      "s3:x-amz-acl": "bucket-owner-full-control",
      "aws:SourceArn": "arn:aws:cloudtrail:REGION:111122223333:trail/TRAIL_NAME"
    }
  }
}
```

## Integrity and retention

| Feature | Key facts |
|---|---|
| Versioning | States: unversioned, enabled, suspended. Cannot be turned off once enabled, only suspended. Deleting without a version ID adds a delete marker. |
| MFA delete | Root user only, CLI or API only. Required to permanently delete versions or change versioning state. |
| Object Lock | Needs versioning. Per object version. Governance (bypass with `s3:BypassGovernanceRetention`), compliance (no bypass, including root), legal hold (no expiry). Bucket default retention applies to new objects. |
| Lifecycle | Transitions and expirations. Add rules for noncurrent versions and incomplete multipart uploads. Cannot remove locked versions. |
| Replication | Needs versioning on both sides. SSE-KMS replication is opt-in. Delete markers optional; version deletes never replicate. Replication Time Control for a 15-minute objective. |

## Access patterns

| Need | Use |
|---|---|
| Many applications, different permissions, one bucket | **Access points**, each with its own policy and optional VPC-only restriction |
| Same data, different Regions | Multi-Region Access Points |
| Transform or redact on read | S3 Object Lambda |
| Temporary access for someone without credentials | Presigned URL (short expiry; limited by signer's permissions and credential lifetime) |
| Private access from a VPC | Gateway endpoint (free, route table) or interface endpoint (reachable from on premises) |
| Browser uploads from another origin | CORS configuration (not access control) |
| Map corporate identities to prefixes | S3 Access Grants |

## Visibility

| Tool | Tells you |
|---|---|
| CloudTrail data events | Authoritative record of object-level API calls. Off by default; costs money. |
| Server access logs | Detailed request records, best effort, delivered to another bucket |
| IAM Access Analyzer for S3 | Buckets shared publicly or with other accounts |
| Macie | Sensitive data in objects; bucket security posture |
| GuardDuty S3 Protection | Anomalous data access patterns, access from malicious IPs, disabling of protections |
| GuardDuty Malware Protection for S3 | Scans new objects for malware |
| S3 Storage Lens | Organization-wide metrics, including encryption and replication coverage |
| S3 Inventory | Scheduled listing with encryption status, lock status, replication status |

## Baseline for a sensitive bucket

- [ ] Block Public Access on, at account and bucket
- [ ] Object Ownership: bucket owner enforced
- [ ] Default encryption SSE-KMS with a customer managed key and Bucket Keys
- [ ] Bucket policy: deny non-TLS, deny outside organization, deny SSE-C
- [ ] Versioning on; lifecycle for noncurrent versions
- [ ] Object Lock if records must be immutable
- [ ] CloudTrail data events for the bucket
- [ ] Macie job or automated discovery covering it
- [ ] Replication or AWS Backup copy to a separate account
- [ ] Access through VPC endpoints with endpoint policies where possible
