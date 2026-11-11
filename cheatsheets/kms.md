# KMS cheatsheet

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 5.2.1, 5.3.2, 5.3.3, 5.3.5 · **Teaching note:** [Domain 5](../teaching/05-data-protection.md) · **Runbook:** [KMS key scheduled for deletion](../runbooks/kms-key-scheduled-deletion.md)

## Key ownership

| | AWS owned | AWS managed (`aws/service`) | Customer managed |
|---|---|---|---|
| Visible in your account | No | Yes | Yes |
| You edit the key policy | No | No | **Yes** |
| Cross-account use | No | **No** | Yes |
| Rotation | AWS decides | Automatic, yearly | Optional, configurable |
| CloudTrail events in your account | No | Yes | Yes |
| Cost | None | Per request | Monthly per key plus per request |
| Use when | Default is fine | You want audit only | You need control: policy, sharing, disable, conditions |

## Key types

| Type | Specs | Operations | Notes |
|---|---|---|---|
| Symmetric encryption | AES-256-GCM | Encrypt, Decrypt, GenerateDataKey, ReEncrypt | Default. Used by all AWS service integrations. Never leaves KMS. |
| Asymmetric | RSA, ECC, and others | Encrypt/Decrypt or Sign/Verify (one usage per key) | Public key is downloadable for use outside AWS |
| HMAC | HMAC-SHA family | GenerateMac, VerifyMac | |

Direct `Encrypt` handles at most **4 KB**. Larger data uses envelope encryption.

## Envelope encryption

```
GenerateDataKey(KeyId) -> plaintext data key + encrypted data key
  encrypt data locally with plaintext key; discard plaintext key
  store encrypted data key next to the ciphertext

Decrypt(encrypted data key) -> plaintext data key
  decrypt data locally; discard plaintext key
```

| API | Returns | Use |
|---|---|---|
| `GenerateDataKey` | Plaintext + encrypted key | Encrypt now |
| `GenerateDataKeyWithoutPlaintext` | Encrypted key only | Component that stores keys but must not encrypt |
| `ReEncrypt` | Ciphertext under a new key | Change keys without exposing plaintext to the caller |

**Encryption context:** non-secret key-value pairs bound to the ciphertext as additional authenticated data. The same context must be supplied to decrypt. It appears in CloudTrail and can be required in policies and grants.

## Key policy

Every key has exactly one key policy. **Without an allow in the key policy, no IAM policy can grant access to the key.**

The default statement that turns on IAM policies for the key:

```json
{
  "Sid": "EnableIAMPolicies",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::111122223333:root" },
  "Action": "kms:*",
  "Resource": "*"
}
```

This delegates to the account's IAM. Remove it and only principals named in the key policy can use the key. A locked-out key needs AWS Support to recover.

Separate duties in the policy:

| Role | Actions |
|---|---|
| Key administrators | `kms:Create*`, `Describe*`, `Enable*`, `Disable*`, `Put*`, `Update*`, `Revoke*`, `ScheduleKeyDeletion`, `CancelKeyDeletion`, `TagResource`. **No** `Encrypt`/`Decrypt`. |
| Key users | `kms:Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, `DescribeKey` |
| Service integration | `kms:CreateGrant`, `ListGrants`, `RevokeGrant` with `kms:GrantIsForAWSResource: true` |

### Cross-account use

1. Key policy in the owning account allows the external account or principal.
2. IAM policy in the external account allows its principal to use that key ARN.

Both are required. Callers must reference the key by full ARN.

### Useful condition keys

| Key | Use |
|---|---|
| `kms:ViaService` | Allow use only through a given service, for example `s3.eu-west-1.amazonaws.com` |
| `kms:CallerAccount` | Restrict to callers from an account |
| `kms:EncryptionContext:KEY` | Require a specific encryption context value |
| `kms:GrantIsForAWSResource` | Allow grant creation only by AWS services on your behalf |
| `kms:KeyOrigin`, `kms:KeySpec`, `kms:KeyUsage` | Restrict what kind of keys can be created |
| `kms:RequestAlias`, `kms:ResourceAliases` | Authorize by alias (ABAC for keys) |
| `aws:SourceArn`, `aws:SourceAccount` | Confused-deputy guard for service principals |

## Grants

A grant gives a principal specific operations on a key without editing the key policy.

- Used heavily by AWS services (EBS, RDS, Redshift) to use your key for a specific resource.
- Created with `CreateGrant`; removed with `RevokeGrant` (by an admin) or `RetireGrant` (by the grantee or retiring principal).
- Can carry constraints on encryption context.
- Eventually consistent: use the **grant token** returned at creation to use the grant immediately.
- Allow only. A grant cannot deny.

## Rotation

| Key | Automatic rotation | How |
|---|---|---|
| Customer managed, symmetric, KMS-generated | Optional; period configurable from 90 to 2,560 days, default 365 **(verify)** | New backing key material; **same key ID and ARN**; old material kept to decrypt old ciphertext |
| Same, on demand | `RotateKeyOnDemand` | Immediate rotation, limited number per key |
| AWS managed | Yearly, mandatory | |
| Imported key material | On-demand rotation by importing new material **(verify)**, or manual | |
| Asymmetric, HMAC, custom key store, external key store | Not supported | **Manual:** create a new key and repoint the alias |

Automatic rotation does **not** re-encrypt existing data. Manual rotation changes the key ID, so applications must reference an alias, and the old key must be kept to decrypt old data.

## Key material origin

| | AWS generated (`AWS_KMS`) | Imported (`EXTERNAL`) | Custom key store (`AWS_CLOUDHSM`) | External key store (`EXTERNAL_KEY_STORE`) |
|---|---|---|---|---|
| Generated by | KMS HSMs | You | Your CloudHSM cluster | Your HSM outside AWS |
| Durability | AWS | **You must keep a copy** | You (cluster backups) | You |
| Expiry | No | Optional expiry date | No | n/a |
| Delete material immediately | No | `DeleteImportedKeyMaterial` | Delete from HSM | Remove at your end |
| Automatic rotation | Yes | No | No | No |
| Availability and latency | AWS | AWS | Your cluster | Your proxy and HSM |
| Key types | All | Symmetric and some asymmetric | Symmetric | Symmetric |

Import steps: create a key with origin `EXTERNAL` → `GetParametersForImport` (wrapping public key and import token, valid 24 hours) → wrap your key material → `ImportKeyMaterial` (with or without expiry).

If imported material expires or is deleted, the key is unusable until the **same** material is re-imported. Ciphertext produced by KMS with imported material is still not decryptable outside KMS.

**Custom key store** requirements: an active CloudHSM cluster with at least two HSMs in different Availability Zones, and a dedicated crypto user for KMS.

**External key store (XKS):** KMS calls your key manager through an XKS proxy for every operation. You gain a kill switch outside AWS and take on responsibility for availability, latency, and durability. Use only when regulation requires keys outside the cloud provider.

## Multi-Region keys

- Key ID starts with `mrk-`. A primary and replicas share key ID and key material.
- Each replica is an independent resource: own key policy, grants, aliases, tags, and enabled state.
- Ciphertext from one can be decrypted by any related key, with no cross-Region call.
- Rotation is configured on the primary and propagates.
- A single-Region key cannot be converted. Decide at creation.
- Use for: client-side encryption across Regions, DynamoDB global tables with client-side encryption, disaster recovery, distributed signing.
- Do not use for: plain cross-Region S3 replication or snapshot copy. Those re-encrypt under a destination key anyway.
- Control with the `kms:MultiRegion` condition key and `kms:ReplicateKey` permission.

## Deletion

| Action | Effect | Reversible |
|---|---|---|
| Disable | All cryptographic operations fail | Yes, enable |
| Schedule deletion | Waiting period 7–30 days (default 30). Key state `PendingDeletion`; unusable. | Yes, cancel during the wait |
| Deleted | All data encrypted under it is permanently unrecoverable | **No** |
| Delete imported key material | Immediate | Yes, by re-importing the same material |

Before deleting: disable the key and wait. Check CloudTrail for recent use. Alarm on any attempt to use a key that is disabled or pending deletion, since that is a workload still depending on it. A multi-Region primary cannot be deleted while replicas exist.

## Service integration notes

| Service | Notes |
|---|---|
| S3 | SSE-KMS; **Bucket Keys** reduce KMS calls and cost; with Bucket Keys the encryption context is the bucket ARN, not the object ARN |
| EBS | Uses grants. Sharing encrypted snapshots needs a customer managed key shared with the target account. |
| RDS | Key fixed at creation; cross-Region snapshot copy takes a key in the destination Region |
| CloudTrail | Key policy must allow `cloudtrail.amazonaws.com` `kms:GenerateDataKey*` with `aws:SourceArn` |
| CloudWatch Logs | Key policy must allow `logs.REGION.amazonaws.com` |
| SNS / SQS | Publishers such as EventBridge or S3 need `kms:GenerateDataKey` and `kms:Decrypt` in the key policy; the AWS managed key does not work for service publishers |
| Secrets Manager | Cross-account secrets need a customer managed key |
| Lambda | Environment variables encrypted at rest; use a customer managed key and encryption helpers for sensitive values |

## Troubleshooting

| Error or symptom | Likely cause |
|---|---|
| `AccessDeniedException` on `kms:Decrypt` although IAM allows | Key policy lacks the IAM-enabling statement or does not name the principal; cross-account side missing; encryption context condition; `kms:ViaService` mismatch |
| `KMSInvalidStateException` | Key disabled, pending deletion, or pending import |
| `InvalidCiphertextException` | Wrong key, wrong encryption context, or corrupted ciphertext |
| `ThrottlingException` | Shared per-account request quota exceeded. Use S3 Bucket Keys, cache data keys (Encryption SDK), request a quota increase. |
| Service cannot use the key | Service principal or service role missing in key policy; missing `kms:CreateGrant` |
| Encrypted snapshot or AMI fails to launch in another account | Encrypted with an AWS managed key, or the customer managed key is not shared |
| Auto Scaling cannot launch instances with encrypted volumes | The Auto Scaling service-linked role needs a grant or key policy access to the key |
