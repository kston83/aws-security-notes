# Lab 05: KMS and secrets

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4h · **SCS-C03:** 5.2.1, 5.3.2 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [Data protection](../../teaching/05-data-protection.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [AWS provider security](../../cheatsheets/terraform-aws-provider-security.md), [KMS cheatsheet](../../cheatsheets/kms.md), [Runbook: Terraform state exposure](../../runbooks/terraform-state-exposure.md)

> **Test status:** smoke-tested on floci (init, validate, apply, Verify, destroy) on 2026-11-11. The step-by-step outputs and the "Break it" exercises have not been run end to end yet.

## Goal

Create a KMS key with an explicit key policy (separate administrator and user statements), automatic rotation, and an alias, then store two generated passwords in Secrets Manager encrypted with that key. One password is a normal resource and ends up in plaintext in `terraform.tfstate`. The other is **ephemeral** and passed through a **write-only argument**, and never reaches state. Afterward you can show the difference with `grep`, rotate a write-only secret by bumping a version number, and handle sensitive values without leaking them in CLI output.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 02](../02-remote-state/README.md) first; it shows why state is a secret store.
- Terraform 1.11 or later (write-only arguments and ephemeral resources) and the `random` provider 3.7 or later **(verify)**. `terraform init` installs the provider.
- Read [Terraform configuration](../../teaching/terraform/04-configuration.md) (objective 4h) and the [KMS cheatsheet](../../cheatsheets/kms.md).

| File | Holds |
|---|---|
| `kms.tf` | Two roles to name in the policy, the key policy document, the key, the alias |
| `secrets.tf` | The state-stored password (a) and the write-only password (b), each with a secret and a secret version |
| `variables.tf` | `secret_version`, the number you bump to rotate the write-only secret |
| `outputs.tf` | Key ARN and alias, secret names, one `sensitive` output |

## Steps

### 1. Read the key policy

A **key policy** is the resource policy on a KMS key; unlike most AWS resources, a key is unusable unless its key policy (alone or together with IAM) allows the caller. `kms.tf` builds it from three statements:

| Sid | Principal | Allows |
|---|---|---|
| `EnableIamPolicies` | account root | `kms:*`, which lets IAM policies in the account grant key access and avoids locking yourself out |
| `KeyAdministrators` | `lab05-key-admin` role | Manage the key (create, describe, enable and disable, put policy, tag, schedule deletion). No `Encrypt` or `Decrypt`. |
| `KeyUsers` | `lab05-key-user` role | `Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, `DescribeKey`. No management. |

Splitting the two statements is the separation of duties in SCS-C03 5.2.1: the people who administer the key cannot read what it protects. The key itself sets `enable_key_rotation = true` and `deletion_window_in_days = 7`, the shortest allowed window.

### 2. Read the two secrets

```hcl
# (a)
resource "random_password" "plain" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret_version" "plain" {
  secret_id     = aws_secretsmanager_secret.plain.id
  secret_string = random_password.plain.result
}

# (b)
ephemeral "random_password" "wo" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret_version" "wo" {
  secret_id                = aws_secretsmanager_secret.wo.id
  secret_string_wo         = ephemeral.random_password.wo.result
  secret_string_wo_version = var.secret_version
}
```


Ephemeral values can be referenced only from places that accept them: write-only arguments, provider configuration, other ephemeral resources, and `locals` or `ephemeral` outputs. Putting one in a normal argument is an error.

### 3. Initialize, validate, check formatting

```bash
terraform init          # [changes state] installs aws and random providers
terraform validate
terraform fmt -check
```

`validate` prints `Success! The configuration is valid.` and `fmt -check` prints nothing.

### 4. Apply

```bash
terraform apply         # [changes state] answer yes
```

```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:

key_alias = "alias/lab05-secrets"
key_arn = "arn:aws:kms:us-east-1:000000000000:key/KEY_ID"
plain_password = <sensitive>
plain_secret_name = "lab05/db-password-plain"
wo_secret_name = "lab05/db-password-wo"
```

Nine resources: two roles, the key, the alias, two secrets, two secret versions, and the state-stored `random_password`. The ephemeral password is not a resource and is not counted. In the apply log, look for `ephemeral.random_password.wo: Closing...` at the end: Terraform opened it, used it, and closed it within the run.

### 5. Find the secret in state

```bash
PW=$(terraform output -raw plain_password)
grep -n "$PW" terraform.tfstate | cut -c1-70
```

```
16:      "value": "<the password>",
490:            "secret_string": "<the password>",
627:            "result": "<the password>",
```

(Real output shows the actual 24 characters.) The password is in state three times: as the output value, as the `secret_string` of the secret version, and as the `result` of `random_password.plain`. `sensitive = true` hid it from the terminal but not from the file. Anyone with read access to the state file, or to the S3 bucket and key behind a remote backend, has the password. See [Runbook: Terraform state exposure](../../runbooks/terraform-state-exposure.md).

`terraform output -raw plain_password` prints the value with no quotes or newline, for use in scripts. A plain `terraform output plain_password` prints `<sensitive>`. Treat `-raw` output as a secret: do not paste it into a log.

Now do the same for the write-only secret:

```bash
WO=$(aws secretsmanager get-secret-value --secret-id lab05/db-password-wo --query SecretString --output text)
grep -c "$WO" terraform.tfstate
grep -n "secret_string_wo" terraform.tfstate
```

```
0
484:            "has_secret_string_wo": null,
491:            "secret_string_wo": null,
492:            "secret_string_wo_version": null,
514:                "value": "secret_string_wo"
550:            "has_secret_string_wo": true,
557:            "secret_string_wo": null,
558:            "secret_string_wo_version": 1,
580:                "value": "secret_string_wo"
```

The count is zero. State records `secret_string_wo` as `null` and keeps only the version (`1`) and the flag `has_secret_string_wo`. (Lines 484 to 514 belong to the other secret version; line numbers vary between runs.) The secret exists in AWS, and Terraform never kept it.

### 6. Rotate the write-only secret

Changing the generated value does not make Terraform notice, because it never saw the old one. Change the version instead:

```bash
terraform plan -var secret_version=2
```

The plan shows `secret_string_wo_version = 1 -> 2 # forces replacement` on `aws_secretsmanager_secret_version.wo`, and `Plan: 1 to add, 0 to change, 1 to destroy.` Applying it would generate a new ephemeral password and write it as a new secret version. The random password is not stored, so you cannot recover the new value from Terraform; whatever consumes the secret must read it from Secrets Manager. Compare this to (a), where rotating means tainting or replacing the `random_password` resource and the new value lands in state again.

### 7. Sensitive values and outputs

`outputs.tf` marks `plain_password` as `sensitive = true`. Terraform tracks this through expressions: anything derived from a sensitive value is sensitive. If you use one in an output that is not marked sensitive, it refuses. Try adding this to `outputs.tf`:

```hcl
output "leaky" {
  value = random_password.plain.result
}
```

Run `terraform validate`. Terraform should report `Error: Output refers to sensitive values` and tell you to add `sensitive = true`. Remove the output again. The flag is a guard against accidental display. It is not encryption: see step 5.

### 8. A word on Vault

HashiCorp Vault (and similar secret managers) is the other half of objective 4h. With Vault the secret lives outside Terraform: the `vault` provider can read secrets with an ephemeral resource or data source, and Vault can also issue short-lived dynamic credentials, so there is no long-lived password to leak from state. The lab's pattern, write-only arguments with a value generated or fetched at apply time, gets the same result for a single secret without running Vault. Vault is worth its operating cost when many systems need dynamic, audited, short-lived credentials.

## Verify

```bash
aws secretsmanager get-secret-value --secret-id lab05/db-password-plain --query SecretString --output text
aws secretsmanager get-secret-value --secret-id lab05/db-password-wo --query SecretString --output text
```

Each prints a 24-character password. Both secrets exist, so the write-only argument did deliver its value.

```bash
aws secretsmanager describe-secret --secret-id lab05/db-password-wo --query KmsKeyId --output text
aws kms describe-key --key-id alias/lab05-secrets --query 'KeyMetadata.[KeyState,KeyManager]' --output text
```

```
arn:aws:kms:us-east-1:000000000000:key/KEY_ID
Enabled	CUSTOMER
```

The `get-key-rotation-status` and `get-key-policy` calls do not accept an alias, so take the key ID from the output:

```bash
KEY_ID=$(terraform output -raw key_arn | sed 's|.*key/||')
aws kms get-key-rotation-status --key-id "$KEY_ID" --query KeyRotationEnabled --output text
aws kms get-key-policy --key-id "$KEY_ID" --policy-name default --query Policy --output text \
  | grep -o '"Sid" *: *"[A-Za-z]*"'
```

```
True
"Sid":"EnableIamPolicies"
"Sid":"KeyAdministrators"
"Sid":"KeyUsers"
```

## Break it

These have not been run end to end; the descriptions say what Terraform should report.

**1. Use an ephemeral value in a normal argument.** In `secrets.tf`, change the `wo` secret version to `secret_string = ephemeral.random_password.wo.result`. Run `terraform validate`. Expect an error saying ephemeral values are not allowed in that context. The rule is what protects state: only write-only arguments and a few other places accept ephemeral values. Revert.

**2. Forget to bump the version.** Change the `ephemeral` block's `length` to 32 and run `terraform plan`. Expect `No changes`: Terraform does not store the old value and `secret_string_wo_version` is unchanged, so it sees nothing to do. A write-only secret rotates only when you change the version. Revert.

**3. Lock the key out.** Delete the `EnableIamPolicies` statement from the key policy and plan. The key policy would then name only the two roles. On real AWS, this can leave a key nobody can manage through IAM, and `PutKeyPolicy` is refused if the new policy would make the key unmanageable. Do not apply it to a real key. Revert.

**4. Print the sensitive output.** Compare `terraform output plain_password`, `terraform output -raw plain_password`, and `terraform output -json`. The first prints `<sensitive>`; the other two print the value. `sensitive` limits display, not access.

**5. Check the state again after a bump.** Apply with `-var secret_version=2`, then repeat the `grep -c "$WO"` check with the new value. The expected count is still zero.

## Clean up

```bash
terraform destroy       # [changes state] Destroy complete! Resources: 9 destroyed.
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `lab05`)].Name' --output text    # prints nothing
```

The secrets use `recovery_window_in_days = 0` so they are deleted immediately. The key goes to pending deletion; on floci it stays `PendingDeletion` and still appears in `aws kms list-keys`. Delete `terraform.tfstate` afterward, since it holds the plaintext password from (a).

## What differs on real AWS

- **Key policy checks.** Real KMS rejects a key policy whose principal does not exist and rejects one that would lock out the account. The lab creates the two roles so the policy names real principals.
- **Key deletion.** A real key stays in `PendingDeletion` for the window (7 to 30 days) and then disappears. Anything it encrypted becomes unreadable.
- **Enforcement.** floci stores the key policy but does not enforce it, so the lab proves the policy is attached and correct in shape, not that the administrator is refused a `Decrypt`. Test that on AWS with an assumed-role session.
- **Ciphertext.** floci's KMS output cannot be decrypted by real KMS.
- **Rotation.** Real automatic rotation creates new key material on a schedule **(verify the period)**; the lab only shows the flag set.
- **Secret deletion.** A real secret defaults to a 30-day recovery window. `recovery_window_in_days = 0` is a lab convenience.
- **Where the secret really lives.** Your configuration still holds whatever feeds the secret. Here Terraform generates it, so no one knows it; in practice you often pass in a value, and then the variable or Vault lookup must be ephemeral as well.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
