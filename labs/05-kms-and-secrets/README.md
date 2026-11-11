# Lab 05: KMS and secrets

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4h · **SCS-C03:** 5.2.1, 5.3.2 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [Data protection](../../teaching/05-data-protection.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [AWS provider security](../../cheatsheets/terraform-aws-provider-security.md), [KMS cheatsheet](../../cheatsheets/kms.md), [Runbook: Terraform state exposure](../../runbooks/terraform-state-exposure.md)

## Goal

Create a KMS key with an explicit key policy (separate administrator and user statements), automatic rotation, and an alias, then store two generated passwords in Secrets Manager encrypted with that key. One password is a normal resource and ends up in plaintext in `terraform.tfstate`. The other is **ephemeral** and passed through a **write-only argument**, and never reaches state. Afterward you can show the difference with `grep`, rotate a write-only secret by bumping a version number, and handle sensitive values without leaking them in CLI output.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 02](../02-remote-state/README.md) first; it shows why state is a secret store.
- Terraform 1.11 or later (write-only arguments and ephemeral resources; the lab's `required_version` asks for 1.12) and the `random` provider 3.7 or later **(verify)**. `terraform init` installs the provider.
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

Password (a) is a `resource "random_password" "plain"` fed to `secret_string`, an ordinary argument. Password (b) is ephemeral and goes in through write-only arguments:

```hcl
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

Ephemeral values can be referenced only from places that accept them: write-only arguments, provider configuration, other ephemeral resources, and `locals` or `ephemeral` outputs. Putting one in a normal argument is an error (Break it 1).

### 3. Initialize, validate, check formatting

```bash
terraform init          # [changes state] installs aws and random providers
terraform validate
terraform fmt -check
```

```
...
- Installed hashicorp/random v3.9.1 (signed by HashiCorp)
...
- Installed hashicorp/aws v6.72.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
...
Success! The configuration is valid.
```

`fmt -check` prints nothing and exits 0.

### 4. Apply

```bash
terraform apply         # [changes state] answer yes
```

The plan already shows how Terraform treats the two passwords: `secret_string = (sensitive value)` on (a), `secret_string_wo = (write-only attribute)` on (b). The end of the apply log:

```
...
ephemeral.random_password.wo: Closing...
ephemeral.random_password.wo: Closing complete after 0s

Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:

key_alias = "alias/lab05-secrets"
key_arn = "arn:aws:kms:us-east-1:000000000000:key/6aa1c4a8-e9ca-4cdb-9274-7d11cbb95713"
plain_password = <sensitive>
plain_secret_name = "lab05/db-password-plain"
wo_secret_name = "lab05/db-password-wo"
```

The key ID differs on every run. Nine resources: two roles, the key, the alias, two secrets, two secret versions, and the state-stored `random_password`. The ephemeral password is not a resource and is not counted. Terraform opens it once during the plan and again during the apply, and closes it within each run.

### 5. Find the secret in state

```bash
PW=$(terraform output -raw plain_password)
grep -n "$PW" terraform.tfstate | cut -c1-70
```

```
16:      "value": "haOKEqJ92aSmZSbWuTht0pCQ",
490:            "secret_string": "haOKEqJ92aSmZSbWuTht0pCQ",
627:            "result": "haOKEqJ92aSmZSbWuTht0pCQ",
```

Your password differs. It is in state three times: as the output value, as the `secret_string` of the secret version, and as the `result` of `random_password.plain`. `sensitive = true` hid it from the apply summary but not from the file, and `terraform output -raw` read it straight back (Break it 4 shows every `terraform output` form). Anyone with read access to the state file, or to the S3 bucket and key behind a remote backend, has the password. See [Runbook: Terraform state exposure](../../runbooks/terraform-state-exposure.md).

Now do the same for the write-only secret:

```bash
WO=$(aws secretsmanager get-secret-value --secret-id lab05/db-password-wo --query SecretString --output text)
grep -c "$WO" terraform.tfstate
grep -n "secret_string_wo" terraform.tfstate
```

```
0
...
550:            "has_secret_string_wo": true,
557:            "secret_string_wo": null,
558:            "secret_string_wo_version": 1,
...
```

The count is zero, and `grep -rl "$WO" .` finds it in no file in the working directory. State records `secret_string_wo` as `null` and keeps only the version and the flag `has_secret_string_wo`. (The elided lines are the same three attributes, all `null`, on the other secret version, and the attribute's name, `"value": "secret_string_wo"`, in two path lists.) The secret exists in AWS, and Terraform never kept it.

### 6. Rotate the write-only secret

Changing the generated value does not make Terraform notice, because it never saw the old one (Break it 2). Change the version instead:

```bash
terraform plan -var secret_version=2
```

```
...
  # aws_secretsmanager_secret_version.wo must be replaced
-/+ resource "aws_secretsmanager_secret_version" "wo" {
...
      ~ secret_string_wo_version = 1 -> 2 # forces replacement
...
Plan: 1 to add, 0 to change, 1 to destroy.
```

Applying it generates a new ephemeral password and writes it as a new secret version (Break it 5). The new value is not stored, so you cannot recover it from Terraform; whatever consumes the secret must read it from Secrets Manager. Compare this to (a), where rotating means replacing the `random_password` resource and the new value lands in state again.

### 7. Sensitive values and outputs

`outputs.tf` marks `plain_password` as `sensitive = true`. Terraform tracks this through expressions: anything derived from a sensitive value is sensitive. If you use one in an output that is not marked sensitive, it refuses. Add this to `outputs.tf`:

```hcl
output "leaky" {
  value = random_password.plain.result
}
```

`terraform validate` still prints `Success! The configuration is valid.`, because the check needs the values. Run `terraform plan`:

```
Error: Output refers to sensitive values

  on outputs.tf line 27:
  27: output "leaky" {
...
```

The rest of the message tells you to add `sensitive = true`.

Remove the output again. The flag is a guard against accidental display. It is not encryption: see step 5.

### 8. A word on Vault

HashiCorp Vault (and similar secret managers) is the other half of objective 4h. With Vault the secret lives outside Terraform: the `vault` provider can read secrets with an ephemeral resource or data source, and Vault can also issue short-lived dynamic credentials, so there is no long-lived password to leak from state. The lab's pattern, write-only arguments with a value generated or fetched at apply time, gets the same result for a single secret without running Vault. Vault is worth its operating cost when many systems need dynamic, audited, short-lived credentials.

## Verify

```bash
aws secretsmanager get-secret-value --secret-id lab05/db-password-plain --query SecretString --output text
aws secretsmanager get-secret-value --secret-id lab05/db-password-wo --query SecretString --output text
aws secretsmanager describe-secret --secret-id lab05/db-password-wo --query KmsKeyId --output text
aws kms describe-key --key-id alias/lab05-secrets --query 'KeyMetadata.[KeyState,KeyManager]' --output text
```

```
haOKEqJ92aSmZSbWuTht0pCQ
m5YyqAUQqD6V8SpIgV6OqqAl
arn:aws:kms:us-east-1:000000000000:key/6aa1c4a8-e9ca-4cdb-9274-7d11cbb95713
Enabled	CUSTOMER
```

Each secret holds a 24-character password; the first matches the one in state, and the second shows the write-only argument delivered its value. The secret is encrypted with the lab's customer managed key.

`get-key-rotation-status` and `get-key-policy` refuse an alias (`InvalidArnException ... Key Aliases are not supported for this operation.`), so take the key ID from the output:

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

**1. Use an ephemeral value in a normal argument.** In `secrets.tf`, change `secret_string_wo` in the `wo` secret version to `secret_string` (same value, `ephemeral.random_password.wo.result`). Run `terraform validate`:

```
Error: Invalid use of ephemeral value
...
Ephemeral values are not valid for "secret_string", because it is not a
write-only attribute and must be persisted to state.

Error: Missing required argument
...
`secret_string_wo,secret_string_wo_version` must be specified
```

The first error is the rule that protects state; the second is the provider noting that the version argument now has no write-only partner. Revert. The same rule covers outputs: an output with `value = ephemeral.random_password.wo.result` fails `validate` with `Error: Ephemeral value not allowed` (`This output value is not declared as returning an ephemeral value`), even with `sensitive = true`.

**2. Forget to bump the version.** Change the `ephemeral` block's `length` to 32 and run `terraform plan`. It ends with `No changes. Your infrastructure matches the configuration.` Terraform does not store the old value and `secret_string_wo_version` is unchanged, so it sees nothing to do. A write-only secret rotates only when you change the version. Revert.

**3. Lock the key out.** Delete the `EnableIamPolicies` statement from the key policy and run `terraform plan`:

```
  # aws_kms_key.secrets will be updated in-place
...
                      - Action    = "kms:*"
...
                      - Sid       = "EnableIamPolicies"
...
Plan: 0 to add, 1 to change, 0 to destroy.
```

The policy would name only the two roles, so no IAM policy could grant access to the key any more. On real AWS, `PutKeyPolicy` refuses a policy that would stop the caller from changing the policy again, unless you set `bypass_policy_lockout_safety_check`; if it went through, only the named roles (or AWS Support) could recover the key. Never apply this to a real key. floci applied it without complaint (`Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`), and the `test` credentials could still encrypt with the key afterward. Revert, and apply again if you applied it.

**4. Print the sensitive output.** Run each `terraform output` form. Only the first redacts the value:

| Command | Prints for `plain_password` |
|---|---|
| `terraform output` | `plain_password = <sensitive>` (in the list of all outputs) |
| `terraform output plain_password` | `"haOKEqJ92aSmZSbWuTht0pCQ"` |
| `terraform output -raw plain_password` | `haOKEqJ92aSmZSbWuTht0pCQ` (no quotes, no trailing newline) |
| `terraform output -json` | Every output as a JSON object; under `"plain_password"` the lines `"sensitive": true,` and `"value": "haOKEqJ92aSmZSbWuTht0pCQ"` |
| `terraform output -json plain_password` | `"haOKEqJ92aSmZSbWuTht0pCQ"` |

Naming an output is taken as asking for it, and `-json` prints the value next to its own `"sensitive": true` flag. `sensitive` limits display in plans, applies, and the output list, not access. Treat any of the last four as a secret: do not run them where a CI log captures them.

**5. Rotate and check the state again.** Run `terraform apply -var secret_version=2` **[changes state]**. It replaces the secret version and ends with `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.` Repeat the `WO=...` and `grep -c "$WO" terraform.tfstate` commands from step 5. `get-secret-value` now returns a new password, the count is still `0`, and state holds only `"secret_string_wo_version": 2`. The old value is not gone from AWS:

```bash
aws secretsmanager list-secret-version-ids --secret-id lab05/db-password-wo \
  --query 'Versions[].[VersionId,join(`,`,VersionStages)]' --output text
```

```
terraform-DarwG7DJftWMlFVwWhgUShJK3d	AWSPREVIOUS
terraform-MLUmBaE2Ye8ACBP1mdSVsiWgrM	AWSCURRENT
```

Terraform's "destroy" of the old version did not delete it: when the new version took `AWSCURRENT`, Secrets Manager relabelled the old one `AWSPREVIOUS`, and its password is still readable. Until you change the default in `variables.tf`, a plan without `-var` shows `secret_string_wo_version = 2 -> 1 # forces replacement` and would rotate again.

## Clean up

```bash
KEY_ID=$(terraform output -raw key_arn | cut -d/ -f2)    # save it before the output is gone
terraform destroy       # [changes state] answer yes
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `lab05`)].Name' --output text
aws kms describe-key --key-id $KEY_ID --query 'KeyMetadata.[KeyState,DeletionDate]' --output text
```

`destroy` ends with `Destroy complete! Resources: 9 destroyed.` and `list-secrets` prints nothing: `recovery_window_in_days = 0` deletes the secrets immediately. The key goes to pending deletion for `deletion_window_in_days` (the offset is your local time zone):

```
PendingDeletion	2026-11-18T13:48:51-06:00
```

Then run `rm terraform.tfstate terraform.tfstate.backup`. The emptied `terraform.tfstate` no longer holds the password, but `terraform.tfstate.backup` does, three times, because destroy saved the previous state there.

## What differs on real AWS

- **Key policy enforcement.** floci stores the key policy but does not enforce it. In this lab's test run, an `assume-role` session for `lab05-key-admin` decrypted a ciphertext from the key, which the policy does not allow it to do. The lab proves the policy is attached and correct in shape, not that the administrator is refused a `Decrypt`; test that on AWS with an assumed-role session. floci's opt-in `FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true` setting **(verify)** was not used for this lab.
- **Key policy checks.** Real KMS rejects a key policy whose principal does not exist, and `PutKeyPolicy` rejects one that would lock the caller out (Break it 3); floci accepted the lockout policy. The lab creates the two roles so the policy names real principals.
- **Key deletion.** A real key stays in `PendingDeletion` for the window (7 to 30 days) and then disappears. Anything it encrypted becomes unreadable.
- **Ciphertext.** floci's KMS output cannot be decrypted by real KMS.
- **Rotation.** Real automatic rotation creates new key material on a schedule (365 days by default, configurable with `rotation_period_in_days`) **(verify)**, and real `get-key-rotation-status` also returns the period and next rotation date. floci returned only `KeyRotationEnabled`; the lab only shows the flag set.
- **Secret versions.** floci created an extra, empty version (labelled `AWSPREVIOUS`, no value) when each secret was created. On AWS a `CreateSecret` call with no value creates no version **(verify)**.
- **Secret deletion.** A real secret defaults to a 30-day recovery window. `recovery_window_in_days = 0` is a lab convenience.
- **Where the secret really lives.** Your configuration still holds whatever feeds the secret. Here Terraform generates it, so no one knows it; in practice you often pass in a value, and then the variable or Vault lookup must be ephemeral as well.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
