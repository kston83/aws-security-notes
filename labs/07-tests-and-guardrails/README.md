# Lab 07: Tests and guardrails

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4g · **SCS-C03:** 6.2.1 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Terraform modules](../../teaching/terraform/05-modules.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md)

## Goal

Put four kinds of Terraform-native guardrail around a small configuration (an encrypted, versioned S3 bucket, an IAM policy, and a security group), then prove they work with `terraform test`. Afterward you can pick the right guardrail for a rule, say when each runs and whether it stops the apply, and write tests that pass with no cloud at all.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 03](../03-variables-and-modules/README.md) first (variable `validation`). Read objective 4g in [Terraform configuration](../../teaching/terraform/04-configuration.md).

## Steps

### 1. Find the four guardrails

| Guardrail | In this lab | Rule it enforces | Runs | On failure |
|---|---|---|---|---|
| Variable **`validation`** | `variables.tf` | Encryption algorithm must be `aws:kms`; no ingress from `0.0.0.0/0` on port 22 | First, on the input value | Error. Nothing is created. |
| **`precondition`** | `main.tf`, `aws_iam_policy.reader` | Policy must not contain Action `*` with Resource `*` | Before the resource is created or changed, once its inputs are known | Error. That resource and everything after it is not applied. |
| **`postcondition`** | `main.tf`, `aws_s3_object.canary` | Bucket must have versioning enabled (the object came back with a version ID) | After the resource is created, once `self` is known | Error, but the resource already exists and is in state. |
| **`check`** block | `checks.tf` | SSH ranges no wider than /16; credentials belong to the expected account | End of every plan and apply | Warning only. The run continues. |

Preconditions and postconditions sit in a resource's `lifecycle` block:

```hcl
  lifecycle {
    postcondition {
      condition     = !contains(["", "null"], coalesce(self.version_id, "null"))
      error_message = "Bucket must have versioning enabled: the canary object came back without a version ID."
    }
  }
```

A `check` block stands alone and may hold one **scoped data source**, used only by its assertions:

```hcl
check "expected_account" {
  data "aws_caller_identity" "current" {}

  assert {
    condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
    error_message = "Credentials are for account ${data.aws_caller_identity.current.account_id}, not ${var.expected_account_id}."
  }
}
```

### 2. Apply the secure defaults

```bash
terraform init          # [changes state] writes .terraform/ and .terraform.lock.hcl
terraform validate      # Success! The configuration is valid. (also parses the tests/ files)
terraform apply         # [changes state] answer yes
```

```
...
aws_s3_object.canary: Creation complete after 0s [id=lab07-data/guardrail-canary.txt]
data.aws_caller_identity.current: Reading...
data.aws_caller_identity.current: Read complete after 0s [id=000000000000]

Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
...
canary_version_id = "3bbdf316-140e-4b40-80b0-fe46bdb2eda7"
...
```

No warnings means every guardrail passed. The scoped data source is read last, because checks run last.

### 3. See what a scoped data source does to the plan

```bash
terraform plan -detailed-exitcode; echo "exit=$?"
```

```
  # data.aws_caller_identity.current will be read during apply
  # (config will be reloaded to verify a check block)
 <= data "aws_caller_identity" "current" {
      + account_id = "000000000000"
...
Plan: 0 to add, 0 to change, 0 to destroy.
exit=2
```

Nothing is changing, yet the plan is not `No changes` and `-detailed-exitcode` returns 2, because Terraform plans to re-read the check's data source at apply. Observed with Terraform 1.17.1 **(verify)**. A drift job keyed on exit code 2 would fire on every run. A check with only an `assert` (like `ssh_ranges_are_narrow`) does not do this.

### 4. Trip the two guardrails that stop a plan

```bash
terraform plan -var sse_algorithm=AES256
```

```
Error: Invalid value for variable
...
    │ var.sse_algorithm is "AES256"

Encryption algorithm must be aws:kms or aws:kms:dsse. SSE-S3 (AES256) is not
allowed.
...
```

```bash
terraform plan -var 'policy_actions=["*"]' -var 'policy_resources=["*"]'
```

```
Error: Resource precondition failed

  on main.tf line 78, in resource "aws_iam_policy" "reader":
  78:       condition     = !(contains(var.policy_actions, "*") && contains(local.policy_resources, "*"))
    ├────────────────
    │ local.policy_resources is list of string with 1 element
    │ var.policy_actions is list of string with 1 element

Policy must not allow Action "*" on Resource "*".
```

Both fail during `plan`, so there is nothing to apply. A validation sees its variable (plus, since Terraform 1.9 **(verify)**, other values it refers to). A precondition can combine variables, locals, and other resources, and names the resource it protects.

### 5. Run the tests

Test files end in `.tftest.hcl` and live in the root or `tests/`. Each `run` block is one `plan` or `apply` followed by its `assert` blocks. `terraform test` needs Terraform 1.6 or later; mocks need 1.7.

| File | Technique | Needs floci |
|---|---|---|
| `tests/plan.tftest.hcl` | `command = plan`, asserts on planned values | Yes, for the check's STS call |
| `tests/guardrails.tftest.hcl` | `expect_failures`: passes only if the named variable, resource, or check rejects bad input | Yes, same reason |
| `tests/mocked.tftest.hcl` | `mock_provider`, `mock_data`, `mock_resource` | No |
| `tests/mocked_postcondition.tftest.hcl` | `override_resource` to fake what S3 returns, with `expect_failures` | No |
| `tests/apply.tftest.hcl` | `command = apply`: creates `lab07-test-*` resources, asserts, destroys them | Yes |

```bash
terraform test          # [changes state] creates and destroys the lab07-test-* resources
```

```
tests/apply.tftest.hcl... in progress
  run "creates_real_resources"... pass
...
tests/guardrails.tftest.hcl... in progress
  run "rejects_sse_s3"... pass
  run "rejects_ssh_from_anywhere"... pass
  run "rejects_admin_policy"... pass
  run "warns_on_wide_ssh_range"... pass
tests/guardrails.tftest.hcl... tearing down
tests/guardrails.tftest.hcl... pass
...
Success! 9 passed, 0 failed.
```

Each test file keeps its own in-memory state, separate from `terraform.tfstate`, and destroys what it created while "tearing down". A negative test:

```hcl
run "rejects_admin_policy" {
  command = plan

  variables {
    policy_actions   = ["*"]
    policy_resources = ["*"]
  }

  expect_failures = [aws_iam_policy.reader]
}
```

Run the mocked files with the endpoint pointed at a port where nothing listens, to prove they call no API:

```bash
terraform test -filter=tests/mocked.tftest.hcl -filter=tests/mocked_postcondition.tftest.hcl -var floci_endpoint=http://localhost:9
```

```
tests/mocked.tftest.hcl... in progress
  run "applies_offline"... pass
...
Success! 2 passed, 0 failed.
```

`-verbose` prints the plan or state behind each run, including what a mock invented:

```bash
terraform test -filter=tests/mocked.tftest.hcl -verbose
```

```
# aws_s3_bucket.data:
resource "aws_s3_bucket" "data" {
    acceleration_status         = "tpm6uxrb"
    acl                         = "88z1kotk"
    arn                         = "2m8gibsn"
    bucket                      = "lab07-data"
...
```

Values you set (`bucket`) are kept; computed ones (`arn`, `id`) are random strings. A mocked test can assert on your logic, never on what AWS returns. That is why `mocked.tftest.hcl` supplies a JSON policy document, an account ID, and a version ID: the provider still validates the policy JSON, and the check and postcondition would otherwise see random text.

## Verify

```bash
aws s3api get-bucket-encryption --bucket lab07-data --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm'    # "aws:kms"
aws s3api get-bucket-versioning --bucket lab07-data --query Status                                                                                          # "Enabled"
aws ec2 describe-security-group-rules --filters Name=group-id,Values=$(terraform output -raw security_group_id) \
  --query 'SecurityGroupRules[?!IsEgress].[CidrIpv4,FromPort,ToPort]' --output text
aws iam get-policy-version --policy-arn $(terraform output -raw policy_arn) --version-id v1 --query 'PolicyVersion.Document.Statement[0].Action'
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab07-`)].Name' --output text    # lab07-data only: the test's lab07-test-data is gone
```

```
10.7.0.0/16	22	22
[
    "s3:ListBucket",
    "s3:GetObject"
]
```

## Break it

**1. Fail a check and watch the apply finish.** `10.0.0.0/8` passes validation (it is not `0.0.0.0/0`) but is wider than /16:

```bash
terraform apply -var 'ssh_ingress_cidrs=["10.0.0.0/8"]'     # [changes state]
```

```
aws_vpc_security_group_ingress_rule.ssh["10.0.0.0/8"]: Creation complete after 0s [id=sgr-b3b027d9ddfbf43b1]
...
Warning: Check block assertion failed

  on checks.tf line 6, in check "ssh_ranges_are_narrow":
   6:     condition     = alltrue([for cidr in var.ssh_ingress_cidrs : tonumber(split("/", cidr)[1]) >= 16])
...
An SSH ingress range is wider than /16. Allowed, but confirm it is intended.

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

The rule now exists (`describe-security-group-rules` shows `10.0.0.0/8	22	22`). A check reports; it does not prevent, so never use one for a rule that must hold. `terraform plan -var expected_account_id=111122223333` likewise warns `Credentials are for account 000000000000, not 111122223333.` and carries on. Inside `terraform test` a failed check does count as a failure, which is why `expect_failures = [check.ssh_ranges_are_narrow]` works. Put it back with `terraform apply`.

**2. Fail a postcondition and find the resource already built.** Suspend versioning and force a new canary:

```bash
terraform apply -var versioning_enabled=false -replace=aws_s3_object.canary     # [changes state]
```

```
...
aws_s3_object.canary: Creation complete after 0s [id=lab07-data/guardrail-canary.txt]

Error: Resource postcondition failed

  on main.tf line 56, in resource "aws_s3_object" "canary":
  56:       condition     = !contains(["", "null"], coalesce(self.version_id, "null"))
    ├────────────────
    │ self.version_id is ""

Bucket must have versioning enabled: the canary object came back without a
version ID.
```

The plan was accepted because `version_id` is known only after creation. By the error, the bucket is unversioned and the object exists (`terraform state list` shows `aws_s3_object.canary`). A postcondition stops dependents; it does not roll back. A plain `terraform apply` now fails the same way during planning, because the stored object still breaks the rule. Fix the cause and replace the object:

```bash
terraform apply -replace=aws_s3_object.canary     # [changes state] Apply complete! Resources: 1 added, 1 changed, 1 destroyed.
```

**3. Write a wrong assertion.** In `tests/plan.tftest.hcl`, change the first condition's `"aws:kms"` to `"AES256"`, then:

```bash
terraform test -filter=tests/plan.tftest.hcl
```

```
  run "secure_defaults"... fail

Error: Test assertion failed
...
    │ Diff:
    │ --- actual
    │ +++ expected
    │ - "aws:kms"
    │ + "AES256"

Default encryption must be aws:kms.
  run "one_rule_per_range"... pass
tests/plan.tftest.hcl... tearing down
tests/plan.tftest.hcl... fail

Failure! 1 passed, 1 failed.
```

Exit code 1 fails a pipeline. A failed assertion does not skip later runs in the file. Change it back.

**4. Find the gap in a guardrail.** The precondition rejects `*` on `*`. Give it `*` on the bucket only:

```bash
terraform plan -var 'policy_actions=["*"]'
```

```
Plan: 0 to add, 1 to change, 0 to destroy.
```

No error, and the plan grants every action on the bucket. A guardrail enforces exactly the condition you wrote. Tighten it (and add an `expect_failures` run for the new case) rather than assuming a passing plan is a safe one.

## Clean up

```bash
terraform destroy       # [changes state] Destroy complete! Resources: 9 destroyed.
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab07-`)].Name' --output text                              # prints nothing
aws iam list-policies --scope Local --query 'Policies[?starts_with(PolicyName, `lab07`)].PolicyName' --output text    # prints nothing
```

An interrupted test run can leave `lab07-test-*` resources behind. `terraform test` prints what it could not destroy; remove those with the AWS CLI or restart the emulator.

## What differs on real AWS

- **The canary sets `server_side_encryption` itself.** floci stores a bucket's default encryption but does not apply it to new objects, so `head-object` shows no encryption unless the upload asks for it. On AWS the bucket default applies, and a stronger postcondition would leave the argument off and assert that `self.server_side_encryption` came back as `aws:kms`.
- **Version ID on an unversioned bucket.** floci returns an empty string; AWS returns the string `null`. The postcondition accepts neither.
- **`terraform test` with `command = apply` creates real, billable resources** in whatever account the credentials reach, and needs permission to create and delete them all. Use a sandbox account, keep names distinct (this lab's `name_prefix`), and check for leftovers after an interrupted run. Run mocked and plan-only tests on every commit.
- **The `expected_account` check is the real guardrail here.** On floci it fails only if you change the variable; on AWS it catches a pipeline using the wrong profile. For a hard stop, use `allowed_account_ids` in the provider block; see [AWS provider security](../../cheatsheets/terraform-aws-provider-security.md).
- **A real security group and IAM policy take effect.** floci enforces neither, so nothing here proves traffic is blocked or access denied.
- **These guardrails only see Terraform.** They do not stop a console change. Pair them with detective controls (AWS Config, Security Hub) and preventive ones (SCPs); see [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md) and, for drift, [Lab 06](../06-drift-and-import/README.md).
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
