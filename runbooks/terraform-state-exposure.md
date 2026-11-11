# Terraform state exposure

> **Last reviewed:** 2026-11-11 · **Severity:** High; Critical if the state holds production credentials or was publicly readable · **SCS-C03:** 2.2.2, 2.2.3, 2.2.4, 5.3.1, 6.2.1 · **Terraform Associate (004):** 2d, 4h, 6c · **NIST 800-53:** IR-4, IR-6, IA-5, AC-3, SC-28, AU-6

**State** is the JSON file in which Terraform records every attribute of every resource it manages. Attributes marked `sensitive` are hidden in CLI output only; in state they are plaintext. Anyone who read the file has every secret in it. Background: [state management](../teaching/terraform/06-state-management.md), [securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md).

## Trigger

- A secret scanner or reviewer finds `terraform.tfstate`, `terraform.tfstate.backup`, `errored.tfstate`, or a saved plan file in a repository, pull request, ticket, chat, or CI artifact. Saved plans carry the same values as state.
- IAM Access Analyzer external access finding, or GuardDuty `Policy:S3/BucketPublicAccessGranted` or `Policy:S3/BucketAnonymousAccessGranted`, on the state bucket
- CloudTrail `PutBucketPolicy`, `PutBucketAcl`, `DeleteBucketPolicy`, `PutBucketPublicAccessBlock`, or `DeleteBucketPublicAccessBlock` on the state bucket
- `GetObject` on a state key from a principal that is not the pipeline or a platform engineer
- A state bucket or object found shared with an account outside the organization

## Triage

1. **Which state?** Record the bucket, key, and workspace. With the S3 backend a non-default workspace lives at `env:/WORKSPACE_NAME/STATE_KEY` unless `workspace_key_prefix` is set. Check which keys share the bucket: a bucket-level exposure exposes all of them.

```bash
aws s3api list-objects-v2 --bucket STATE_BUCKET --query 'Contents[].[Key,LastModified,Size]' --output table
aws s3api get-bucket-policy-status --bucket STATE_BUCKET
aws s3api get-public-access-block --bucket STATE_BUCKET
aws s3api get-bucket-policy --bucket STATE_BUCKET --query Policy --output text
aws s3api get-bucket-acl --bucket STATE_BUCKET
```

2. **Which versions?** Every version readable during the window counts, not only the current one.

```bash
aws s3api list-object-versions --bucket STATE_BUCKET --prefix STATE_KEY \
  --query 'Versions[].[VersionId,LastModified,IsLatest,Size]' --output table
```

3. **How was it exposed, and since when?** Bucket policy or ACL (find the change in CloudTrail, see Investigate), a commit (`git log --all --diff-filter=A --format='%H %aI %an' -- '*.tfstate*'`), or an upload to a ticket or artifact store (its timestamp).
4. **Which environment does the state describe?** Production state with database or IAM credentials is Critical.

Stop only if the file is provably a lab or emulator state with no real credentials. A private repository is still an exposure: everyone and every integration with read access had the secrets.

## Contain

**1. Lock down the bucket.** Reversible, immediate.

```bash
# changes state: blocks all public access to the bucket
aws s3api put-public-access-block --bucket STATE_BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Block Public Access does not stop a cross-account grant. Save the policy, then remove the offending statement or add an organization-only deny ([S3 cheatsheet](../cheatsheets/s3-security.md#common-bucket-policy-statements)):

```bash
aws s3api get-bucket-policy --bucket STATE_BUCKET --query Policy --output text > evidence/STATE_BUCKET-policy-before.json
# changes state: replaces the bucket policy
aws s3api put-bucket-policy --bucket STATE_BUCKET --policy file://STATE_BUCKET-policy-fixed.json
```

Side effect: a policy that is too tight also locks out the pipeline. Keep the deployment role and the responder role allowed.

**2. Deactivate exposed AWS access keys now.** Do not wait for a Terraform run. Get the key IDs from the exposed copy (see Investigate step 1).

```bash
# changes state: the key stops working everywhere
aws iam update-access-key --user-name USER_NAME --access-key-id ACCESS_KEY_ID --status Inactive
```

Side effect: whatever uses the key breaks until step 2 of Eradicate. Then follow [Compromised IAM credentials](compromised-iam-credentials.md) for each key.

**3. Take the copy out of reach.** Delete the ticket attachment, expire the CI artifact, and restrict the repository if it is public. This limits further reads only; it does not undo the exposure.

```bash
gh api repos/OWNER/REPO/actions/artifacts --paginate --jq '.artifacts[] | [.id,.name,.created_at] | @tsv'
# changes state: deletes the artifact (save a copy as evidence first)
gh api -X DELETE repos/OWNER/REPO/actions/artifacts/ARTIFACT_ID
```

**4. Pause applies** on the affected configuration until rotation is planned, so that nobody writes new secrets into a state that is still exposed.

## Preserve evidence

- The exact exposed file or object versions, copied to the evidence bucket. Never paste them into the ticket.

```bash
aws s3api get-object --bucket STATE_BUCKET --key STATE_KEY --version-id VERSION_ID evidence/state-VERSION_ID.json
```

- Bucket policy, ACL, and public access block as found; the commit hash, artifact ID, or ticket reference; who had access to that location.
- CloudTrail and server access log extracts for the window.

## Investigate

**1. List the secrets in the exposed copy.** Work on the exposed versions, not only the current state. `sensitive_attributes` lists the paths Terraform knows are sensitive (layout varies by Terraform version **(verify)**).

```bash
jq -r '.resources[] | select(.mode=="managed") | . as $r | .instances[]
  | select((.sensitive_attributes // []) | length > 0)
  | "\($r.module // "root")\t\($r.type).\($r.name)"' evidence/state-VERSION_ID.json | sort -u
jq -r '.outputs | to_entries[] | select(.value.sensitive == true) | .key' evidence/state-VERSION_ID.json
jq -r '.resources[].type' evidence/state-VERSION_ID.json | sort | uniq -c | sort -rn
jq -r '.resources[] | select(.type=="aws_iam_access_key") | .instances[].attributes | [.user,.id] | @tsv' evidence/state-VERSION_ID.json
```

For the live state, `terraform show -json` gives resource addresses directly:

```bash
terraform show -json | jq -r '[.values.root_module | recurse(.child_modules[]?) | .resources[]?][]
  | select([.sensitive_values | .. | select(. == true)] | length > 0) | .address'
```

The `sensitive` flag is only a marker. Also read unmarked attributes that often hold secrets: `user_data`, Lambda and ECS environment variables, `aws_ssm_parameter` values of type `String`, provisioner arguments, and data sources (`aws_secretsmanager_secret_version`, `aws_ssm_parameter`).

**2. Who made the bucket readable, and when.** Use the first query in [S3 data exposure](s3-data-exposure.md#investigate) with the state bucket name.

**3. Who read it.** CloudTrail data events, if they were enabled for the bucket:

```sql
SELECT eventtime, useridentity.type, useridentity.accountid, useridentity.arn, sourceipaddress, useragent,
       json_extract_scalar(requestparameters, '$.key') AS object_key
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
  AND json_extract_scalar(requestparameters, '$.bucketName') = 'STATE_BUCKET'
  AND eventname IN ('GetObject','GetObjectVersion','ListObjects','ListObjectsV2','ListObjectVersions')
  AND eventtime BETWEEN 'START_TIME' AND 'END_TIME'
ORDER BY eventtime;
```

Server access logs also record anonymous requests:

```bash
aws s3 sync s3://ACCESS_LOG_BUCKET/ACCESS_LOG_PREFIX evidence/access-logs/
grep -h 'REST.GET.OBJECT' -r evidence/access-logs/ | grep 'STATE_KEY'
```

For a repository, list forks, clones, and integrations with read access. If you cannot show who read the state, assume every secret in it is known.

**4. Were the secrets used?** For each credential, look for use from sources that are not yours: [CLI one-liners](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail). State also gives an attacker a map of the estate (ARNs, network layout, security group rules), so look for reconnaissance against the resources it names.

## Eradicate

**1. Rotate every secret found, whether or not you saw it used.** Deleting the file does not make a secret unknown again.

| In state | Rotate with |
|---|---|
| `aws_iam_access_key` | `terraform apply -replace=aws_iam_access_key.NAME`, then deliver the new key to its consumer. Better: replace the user with a role. |
| `random_password` feeding a database or other resource | `terraform apply -replace=random_password.NAME`. The dependent resource is updated in the same run. |
| `aws_db_instance` or `aws_rds_cluster` master password | Change the value at its source and apply, or move to `manage_master_user_password = true` so RDS keeps it in Secrets Manager |
| `tls_private_key`, `aws_key_pair` | `terraform apply -replace=tls_private_key.NAME`, then reissue certificates and replace key pairs that used it |
| `aws_secretsmanager_secret_version`, `aws_ssm_parameter` | Rotate the value at the issuing system, then apply. `aws secretsmanager rotate-secret --secret-id SECRET_ID` if rotation is configured. |
| Tokens and API keys passed in as variables or read by data sources | Revoke and reissue at the issuer |

```bash
terraform plan -replace=RESOURCE_ADDRESS -out=rotate.tfplan     # review: only the intended replacements
# changes state: destroys and recreates the resource, issuing a new secret
terraform apply rotate.tfplan
```

Side effects: `-replace` destroys before it creates unless the resource sets `create_before_destroy`, so consumers see an outage until they pick up the new value. The new secret is written to state again, so finish Contain first.

**2. Delete the exposed access keys** once replaced (`aws iam delete-access-key`).

**3. Purge the copy.** From git history, then force-push and have every clone re-cloned:

```bash
# changes state: rewrites repository history
git filter-repo --invert-paths --path PATH/TO/terraform.tfstate --path PATH/TO/terraform.tfstate.backup
```

Forks, cached views, and old clones keep the file. This is why rotation, not purging, is the fix. Delete remaining CI artifacts, caches, and attachments.

**4. Remove whatever an attacker created** with the credentials, per the credentials runbook.

## Recover

- Confirm no external access: `aws s3api get-bucket-policy-status --bucket STATE_BUCKET`, and no active Access Analyzer finding for the bucket.
- Confirm old secrets fail: the old access key is gone, the old database password is rejected.
- Run `terraform plan` and expect no changes, then resume the pipeline.
- Decide on notification with legal and privacy leads if the secrets gave access to regulated data (IR-6).

## Follow up

| Gap | Fix |
|---|---|
| Secrets stored in state at all | Ephemeral resources and write-only arguments (Terraform 1.10 and 1.11 **(verify)**), `manage_master_user_password`, roles instead of `aws_iam_access_key`. [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md), [lab 05](../labs/05-kms-and-secrets/README.md) |
| State bucket could be made public or shared | Block Public Access, bucket policy limited to the deployment and responder roles, `aws:PrincipalOrgID` deny, SSE-KMS with a key policy that names the readers. [State and backends cheatsheet](../cheatsheets/terraform-state-and-backends.md), [lab 02](../labs/02-remote-state/README.md) |
| State committed to git | `*.tfstate*`, `*.tfplan`, and `.terraform/` in `.gitignore`; secret scanning with push protection; a remote backend so no local state exists |
| State or plan uploaded as a CI artifact | Never upload state. Encrypt saved plans, keep them for the run only, and restrict who can download artifacts. |
| No record of reads | CloudTrail data events and server access logging on the state bucket. [Logging sources](../cheatsheets/logging-sources.md) |
| Slow detection | Access Analyzer organization analyzer; EventBridge rule on policy and ACL changes to the state bucket. [Lab 08](../labs/08-detection-baseline/README.md) |
| Controls not mapped | [IaC control mapping](../control-mappings/services/iac-terraform.md) |
