# Domain 5: Data Protection

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 5.1.1–5.1.3, 5.2.1–5.2.4, 5.3.1–5.3.5 (18%) · **Related:** [KMS cheatsheet](../cheatsheets/kms.md), [S3 security cheatsheet](../cheatsheets/s3-security.md), [ransomware runbook](../runbooks/ransomware-data-destruction.md), [data protection mappings](../control-mappings/services/data-protection.md)

## Why this matters

Every other control exists to protect data. When those controls fail, encryption decides whether the attacker gets something usable, and backups decide whether you still have it. Data protection requirements are also the ones most often written into contracts and regulations, so they are the ones you will be asked to prove.

## Mental model

Three states, three properties:

| | In transit | At rest | In use |
|---|---|---|---|
| **Confidentiality** | TLS, IPsec, MACsec, private connectivity | KMS-backed encryption, client-side encryption | Nitro Enclaves, least-privilege access, masking |
| **Integrity** | TLS, signatures | Versioning, Object Lock, checksums, code signing | |
| **Availability** | Redundant paths | Backups, replication, retention locks | |

One idea underlies AWS encryption at rest. **Access to encrypted data requires two permissions: one on the data and one on the key.** Server-side encryption with an AWS owned or AWS managed key mostly protects against physical media loss. Encryption with a **customer managed key** adds a second, independent access control that you write (the key policy), a second audit trail (KMS events in CloudTrail), and a kill switch (disable the key).

## Task 5.1: Data in transit

### Requiring encryption

| Service | How to require TLS |
|---|---|
| S3 | Bucket policy deny when `aws:SecureTransport` is `false`. Add `s3:TlsVersion` to set a minimum version. |
| ALB / NLB | HTTPS or TLS listeners with a **security policy** that sets protocols and ciphers. Redirect HTTP to HTTPS on the ALB. |
| CloudFront | Viewer protocol policy (redirect or HTTPS only), minimum viewer TLS version through the security policy, origin protocol policy HTTPS only |
| API Gateway | HTTPS only by design; choose the minimum TLS version on custom domains |
| RDS / Aurora | Parameter group: `rds.force_ssl` (PostgreSQL, SQL Server) or `require_secure_transport` (MySQL, MariaDB). Clients should verify the server certificate against the RDS CA bundle. |
| Redshift | `require_ssl` parameter |
| ElastiCache, MemoryDB, OpenSearch, MSK | In-transit encryption settings, some of which can only be chosen at creation |
| SQS, SNS, DynamoDB, most AWS APIs | Endpoints are HTTPS. Add an `aws:SecureTransport` deny to resource policies where they exist. |

ELB security policies are named sets of protocol versions and ciphers. Choosing a newer policy drops old protocol versions. FIPS and post-quantum variants exist. If a compliance scan flags weak ciphers on a load balancer, the fix is a different security policy.

### Certificates

**AWS Certificate Manager (ACM)**

- Public certificates are free and renew automatically when validated by DNS.
- Certificates are Regional. CloudFront requires the certificate in us-east-1.
- ACM-issued certificates deploy to integrated services (ELB, CloudFront, API Gateway). Historically the private key of a public certificate could not be exported; exportable public certificates are now an option at a cost **(verify)**.
- Imported certificates do not auto-renew. Monitor expiry with the Config rule `acm-certificate-expiration-check` or EventBridge expiry events.

**AWS Private CA**

- A managed private certificate authority hierarchy for internal TLS, mutual TLS, device identity, and IAM Roles Anywhere.
- Keep the root CA rarely used and issue from subordinates. Share a CA across accounts with AWS RAM.
- Revocation through CRLs or OCSP.
- A CA is Regional. For multi-Region issuance, create subordinate CAs in each Region under one root.
- Short-lived certificate mode costs less for certificates valid for days.

### Private access

| Mechanism | What it gives you |
|---|---|
| **Gateway endpoint** (S3, DynamoDB) | Route-table entry sending traffic to the service over the AWS network. No cost. Not reachable from on premises or peered VPCs. |
| **Interface endpoint** (PrivateLink) | An ENI with a private IP in your subnet for an AWS service or a partner or internal service. Has a security group. Reachable over VPN, Direct Connect, and peering. |
| **Endpoint policy** | Limits which principals, actions, and resources can be used through the endpoint. Pair with `aws:SourceVpce` in resource policies. |
| **PrivateLink endpoint service** | Expose your own service behind a Network Load Balancer to other VPCs and accounts without peering, with no route exposure and no overlapping-CIDR problem |
| **Client VPN** | TLS VPN for users into a VPC |
| **Verified Access** | Per-request, identity- and device-aware access to private applications without a VPN |

An endpoint policy plus a bucket policy condition gives you both directions of a perimeter: the endpoint policy stops principals in the VPC reaching buckets outside the organization, and the bucket policy stops access to your bucket from outside the VPC.

### Inter-resource encryption

| Where | Mechanism |
|---|---|
| EC2 to EC2 | Traffic between supported Nitro instance types in the same Region is encrypted automatically at the hardware layer |
| Inter-Region VPC peering and transit gateway peering | Encrypted on the AWS backbone automatically |
| EMR | A **security configuration** enables in-transit encryption (TLS certificates you supply) and at-rest encryption for S3 and local disks |
| EKS | Pod-to-pod encryption is not automatic. Use a service mesh or mutual TLS, VPC Lattice, or rely on Nitro for node-to-node. Encrypt Kubernetes secrets with a KMS key (envelope encryption). |
| SageMaker AI | Enable inter-container traffic encryption for distributed training; run in a VPC with endpoints |
| ElastiCache, OpenSearch, MSK, Redshift | Node-to-node encryption options in the cluster configuration |

## Task 5.2: Data at rest

### Choosing where keys live

| | KMS | KMS with imported key material | KMS custom key store (CloudHSM) | KMS external key store (XKS) | CloudHSM directly |
|---|---|---|---|---|---|
| Key material generated in | KMS HSMs | Your systems | Your CloudHSM cluster | Your external HSM | Your CloudHSM cluster |
| Tenancy | Multi-tenant service | Multi-tenant | Single-tenant HSM | Outside AWS | Single-tenant HSM |
| AWS service integration | Full | Full | Full | Most services | None native: you use PKCS #11, JCE, or other libraries |
| You can delete key material immediately | No (7–30 day wait) | Yes | Yes | Yes (you hold it) | Yes |
| Operational burden | Lowest | Low to medium | High | Highest | High |
| Choose when | Default | You must generate or hold a copy of keys, or need expiry | You need single-tenant HSMs with KMS integration | Keys must remain outside AWS | You need direct HSM access: TLS offload, database TDE, custom crypto, HSM user control |

Start with KMS. Move right only when a stated requirement forces it. Details: [KMS cheatsheet](../cheatsheets/kms.md).

### Server-side or client-side

| Type | Who encrypts | AWS sees plaintext? | Use when |
|---|---|---|---|
| Server-side (SSE-S3, SSE-KMS, DSSE-KMS, service-integrated encryption) | The AWS service | Transiently, in service memory | Default. Transparent to applications. |
| SSE-C | S3, with a key you send on every request | Transiently | You manage keys but want S3 to do the work. Rare, and disabled by default on new buckets **(verify)**. |
| Client-side (AWS Encryption SDK, S3 Encryption Client, DynamoDB client-side encryption) | Your application | Never | The requirement is that the service provider cannot access plaintext, or you need field-level protection end to end |

**Envelope encryption** is how all of these work: a data key encrypts the data, and a KMS key encrypts the data key. The encrypted data key is stored with the data. Only the small data key goes to KMS, so it scales and the KMS key never leaves the HSM.

### Service specifics

| Service | Facts to know |
|---|---|
| **S3** | All new objects are encrypted with SSE-S3 at minimum. Set default bucket encryption to SSE-KMS and enable **S3 Bucket Keys** to cut KMS request volume. Enforce with a bucket policy on `s3:x-amz-server-side-encryption-aws-kms-key-id`. |
| **EBS** | Turn on **encryption by default** per Region. An existing unencrypted volume cannot be encrypted in place: snapshot, copy the snapshot with encryption, create a volume from the copy. |
| **RDS / Aurora** | Encryption is chosen at creation. To encrypt an existing database: snapshot, copy the snapshot with encryption, restore. Replicas and snapshots inherit encryption. |
| **DynamoDB** | Always encrypted. Choose AWS owned, AWS managed, or customer managed key. |
| **EFS** | Encryption at rest is set at creation. In transit is a mount option; enforce with a file system policy on `aws:SecureTransport`. |
| **CloudWatch Logs, SNS, SQS, Kinesis, Secrets Manager** | Optional or default KMS encryption. The key policy must allow the service principal where the service calls KMS itself. |

### Integrity

| Mechanism | Guarantees |
|---|---|
| **S3 Versioning** | Overwrites and deletes create new versions or delete markers; previous versions remain |
| **MFA delete** | Permanently deleting a version or changing versioning state requires the root user's MFA. Only root can enable it. |
| **S3 Object Lock** | Write once, read many. **Governance mode:** users with `s3:BypassGovernanceRetention` can override. **Compliance mode:** nobody, including root, can delete or shorten retention until it expires. **Legal hold:** indefinite, independent of retention, removable by those with permission. Requires versioning. |
| **S3 Glacier Vault Lock** | A vault lock policy that becomes immutable once locked |
| **AWS Backup Vault Lock** | WORM for recovery points; compliance mode becomes immutable after a cooling-off period |
| **Checksums** | S3 verifies integrity on upload and can store additional checksums for later verification |
| **CloudTrail log file validation** | Signed hourly digests prove log files are unaltered |
| **Code signing** | AWS Signer signs Lambda deployment packages and container images. A Lambda code signing configuration rejects unsigned or untrusted code. |

Object Lock compliance mode is the strongest answer for "must not be deletable by anyone." Governance mode is for protection with an administrative escape hatch.

### Lifecycle and retention

- **S3 Lifecycle:** transition to colder storage classes and expire current versions, noncurrent versions, and incomplete multipart uploads. Lifecycle cannot delete an object version protected by Object Lock.
- **EFS lifecycle management:** moves files not accessed for a period to Infrequent Access or Archive.
- **FSx:** automatic daily backups with a retention period, plus AWS Backup for central policy.
- **Amazon Data Lifecycle Manager:** scheduled EBS snapshots and EBS-backed AMIs, with retention, cross-Region copy, and cross-account sharing.
- **CloudWatch Logs:** retention is per log group and defaults to never expire. Set it deliberately.
- **Retention is a requirement in two directions.** Keep long enough for legal and audit needs, and delete on schedule so you do not hold data you are obliged to dispose of.

### Backup and replication

**AWS Backup** centralizes backup across services:

- **Backup plans** define schedule, retention, and copies. **Backup policies** in Organizations push plans to accounts.
- **Vaults** hold recovery points, encrypted with a KMS key, with a vault access policy.
- **Vault Lock** prevents deletion and retention changes.
- **Cross-account and cross-Region copy** puts recovery points out of reach of a compromised workload account.
- **Logically air-gapped vaults** hold immutable copies that can be shared for recovery to another account.
- **Restore testing** and **Backup Audit Manager** prove that backups exist and work.

**Ransomware resilience** comes from combining these: immutable backups (Vault Lock, Object Lock), copies in a separate account with separate credentials, versioning, least privilege on delete and on key administration, SCPs denying backup deletion, and restore tests. See the [ransomware runbook](../runbooks/ransomware-data-destruction.md).

**S3 Replication** (same-Region or cross-Region) requires versioning on both buckets. Replicating SSE-KMS objects must be enabled explicitly and the replication role needs decrypt on the source key and encrypt on the destination key. Delete markers are not replicated unless you turn that on; permanent version deletions are never replicated, which is protective. Set replica ownership to the destination account when replicating across accounts.

**DataSync** transfers data between on-premises storage and AWS, or between AWS storage services, with TLS in transit and integrity verification.

## Task 5.3: Secrets, keys, and sensitive data

### Secrets

| | Secrets Manager | Parameter Store (SecureString) |
|---|---|---|
| Rotation | Built in: managed rotation for supported services, or a Lambda rotation function | None native |
| Cross-account access | Resource policy on the secret | Limited (advanced parameters shared through RAM) |
| Multi-Region | Replica secrets | No |
| Cost | Per secret and per API call | Standard tier free |
| Use for | Database credentials, API keys, anything that rotates | Configuration, and low-churn secrets where cost matters |

Rotation mechanics: a secret has versions with staging labels. `AWSCURRENT` is what clients should use, `AWSPENDING` is being created, `AWSPREVIOUS` is the last one. The rotation function runs four steps: create secret, set secret (in the target system), test secret, finish secret (move the labels).

Rotation strategies:

- **Single user:** change the password of the one user in place. Brief window where old connections fail.
- **Alternating users:** two users; rotation updates the inactive one and switches. No downtime. Needs a separate superuser secret to perform the change.

A rotation Lambda in a VPC needs a network path to both the database and the Secrets Manager endpoint. That is the usual cause of failed rotation.

Cross-account secret access needs three things: the secret's resource policy, the caller's identity policy, and a **customer managed KMS key** whose policy allows the caller. The AWS managed key `aws/secretsmanager` cannot be used across accounts.

Never put secrets in user data, environment variables in plain text, AMIs, container image layers, or source code. Reference them at run time, or use CloudFormation dynamic references.

### Masking

| Tool | Does |
|---|---|
| **CloudWatch Logs data protection policies** | Detect sensitive data in log events with managed or custom data identifiers and mask it on read. Only principals with `logs:Unmask` see the original. Audit findings can go to another destination. |
| **SNS message data protection** | Audit, mask, redact, or block messages containing sensitive data on publish or delivery |
| **Macie** | Discovers sensitive data in S3. It finds; it does not mask. |
| Database features | Dynamic data masking in Redshift and Aurora PostgreSQL; column-level access through Lake Formation |
| **Bedrock Guardrails** | Mask or block PII in model inputs and outputs |

The best masking is not logging the data in the first place.

### Keys and certificates across Regions

- A KMS key is Regional. Ciphertext from one Region's key cannot be decrypted by a key in another, **unless** they are a **multi-Region key** and its replica: same key ID and key material, independently managed policies. Use these for client-side encryption that must be readable in another Region, global tables, and disaster recovery. Do not use them by default; a single-Region key is a stronger isolation boundary.
- When copying snapshots or replicating objects across Regions, AWS services re-encrypt under a key in the destination Region. That does not require a multi-Region key.
- ACM certificates and Private CAs are Regional. Request or issue per Region.
- Secrets Manager replicates secrets to other Regions, encrypting each replica with a key in that Region.

## Worked examples

**1. All objects in a bucket must be encrypted with a specific customer managed key, and uploads over HTTP must be rejected.**
Set default encryption to SSE-KMS with that key and enable Bucket Keys. Bucket policy: deny `s3:PutObject` when `s3:x-amz-server-side-encryption-aws-kms-key-id` is not the key's ARN, and deny all actions when `aws:SecureTransport` is false.

**2. An unencrypted RDS database must be encrypted with minimal downtime.**
Encryption cannot be turned on in place. Create a snapshot, copy it with encryption enabled, restore a new instance from the encrypted copy, and cut over. To reduce downtime, use replication (for example AWS DMS) from the old instance to the new one before switching.

**3. Regulated records must be retained for seven years and must be undeletable even by administrators.**
S3 Object Lock in compliance mode with a seven-year default retention, in a bucket with versioning. Lifecycle rules to move to archival storage classes.

**4. A team shares an encrypted AMI with another account and launches fail there.**
The snapshot is encrypted with a KMS key the other account cannot use. The key must be customer managed, and its policy must allow the target account (and the target account's IAM must allow its principals) to use it, including `kms:CreateGrant` for EBS.

## Pitfalls and exam traps

- Default encryption on a bucket applies to new objects. Existing objects stay as they were until rewritten, for example with S3 Batch Operations.
- A bucket policy that requires an encryption header rejects uploads that rely on default encryption without sending the header, depending on how the condition is written. Test it.
- SSE-KMS makes every reader need `kms:Decrypt`. Public or cross-account access that worked with SSE-S3 breaks.
- AWS managed keys (`aws/s3`, `aws/ebs`) have policies you cannot change, so they cannot be shared across accounts.
- Disabling or deleting a KMS key makes data unrecoverable. Deletion has a 7–30 day waiting period for this reason. Disable first.
- Object Lock compliance mode cannot be undone. Test with governance mode.
- Encryption protects confidentiality. It does nothing against an authorized principal deleting data. That is what versioning, locks, and backups are for.
- Automatic key rotation changes backing key material, not the key ID. Old ciphertext still decrypts. It does not re-encrypt existing data.
- A gateway endpoint does not help on-premises clients; they need an interface endpoint.
- ACM certificates for CloudFront must be in us-east-1.

## Self-check

1. What is the practical security benefit of a customer managed key over SSE-S3?
2. How do you encrypt an existing unencrypted EBS volume?
3. Which Object Lock mode can a suitably privileged administrator override?
4. Why does a rotation Lambda for an RDS secret in a private subnet time out?
5. What must be true for a principal in account B to read a Secrets Manager secret in account A?
6. Which requirement justifies CloudHSM over KMS?
7. When do you need a multi-Region KMS key rather than two independent keys?
8. Which feature masks credit card numbers in application logs for most readers while letting a few see them?

<details>
<summary>Answers</summary>

1. A second, independent access control (key policy) and audit trail (KMS CloudTrail events), plus the ability to disable access by disabling the key and to restrict use by condition or grant.
2. Snapshot it, copy the snapshot with encryption enabled, create a new volume from the encrypted copy, and swap it in.
3. Governance mode, with `s3:BypassGovernanceRetention`.
4. It has no network path to the Secrets Manager endpoint (needs an interface endpoint or NAT) or to the database (security group).
5. The secret's resource policy allows B's principal; B's identity policy allows the action; the secret is encrypted with a customer managed key whose key policy allows B's principal to decrypt.
6. A need for single-tenant HSMs under your exclusive control, direct use of standard cryptographic libraries (PKCS #11, JCE), TLS offload, or database TDE with HSM-held keys.
7. When ciphertext produced in one Region must be decrypted in another without a call back to the first Region or re-encryption, such as client-side encrypted data replicated across Regions.
8. A CloudWatch Logs data protection policy, with `logs:Unmask` granted to the few.

</details>

## Further reading

- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/)
- [AWS KMS cryptographic details](https://docs.aws.amazon.com/kms/latest/cryptographic-details/)
- [Protecting data with encryption in Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [AWS Backup Developer Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
