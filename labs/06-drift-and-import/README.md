# Lab 06: Drift and import

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 6d, 7a, 7b, 7c · **SCS-C03:** 6.2.1 · **Time:** 75 minutes · **Related:** [Terraform fundamentals](../../teaching/terraform/02-terraform-fundamentals.md), [State management](../../teaching/terraform/06-state-management.md), [Maintaining infrastructure](../../teaching/terraform/07-maintaining-infrastructure.md), [Detection](../../teaching/01-detection.md), [Terraform CLI cheatsheet](../../cheatsheets/terraform-cli.md), [State and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [Logging sources](../../cheatsheets/logging-sources.md), [Unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md), [CloudTrail tampering runbook](../../runbooks/cloudtrail-tampering.md)

> **Test status:** smoke-tested on floci (init, validate, apply, Verify, destroy) on 2026-11-11. The step-by-step outputs and the "Break it" exercises have not been run end to end yet.

## Goal

You play two people: the operator who owns the Terraform configuration, and the person who changes things behind its back with the AWS CLI. You detect that **drift** (real infrastructure no longer matching state and configuration), decide whether to revert or accept it, then adopt an unmanaged resource with `import`, rename with `moved`, stop managing with `removed`, force a replacement, inspect state, and read debug logs. Afterward you can handle each case without destroying anything by accident.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) first.
- Read [Maintaining infrastructure](../../teaching/terraform/07-maintaining-infrastructure.md) and the drift section of [State management](../../teaching/terraform/06-state-management.md). Keep the [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md) open: step 1 is its first half.

| File | Holds |
|---|---|
| `main.tf` | A private S3 bucket with a public access block, a security group with one ingress rule, an IAM role |
| `outputs.tf` | Bucket name, security group ID, role ARN |
| `providers.tf` | Lab provider settings with `endpoints` for `ec2`, `iam`, `s3`, `sts` |

## Steps

### 1. Baseline, then drift

```bash
terraform init          # [changes state]
terraform validate
terraform fmt -check
terraform apply         # [changes state] answer yes
```

Expect `Apply complete! Resources: 4 added, 0 changed, 0 destroyed.` The four are the bucket, its public access block, the security group, and the role. The default VPC and the policy document are data sources.

Now be the person who changes things behind Terraform's back. Export the emulator endpoint if you have not (see the labs README), then loosen the bucket's public access block and add a tag:

```bash
aws s3api put-public-access-block --bucket lab06-data \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true   # [changes state]
aws s3api put-bucket-tagging --bucket lab06-data \
  --tagging 'TagSet=[{Key=Lab,Value=06-drift-and-import},{Key=ManagedBy,Value=terraform},{Key=Owner,Value=someone-else}]'   # [changes state]
```

Optionally add a second ingress rule to the security group with `aws ec2 authorize-security-group-ingress --group-id SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0` (get `SG_ID` from `terraform output security_group_id`). Not run in the smoke test; the plan should show it as a rule to remove, because the rules are inline.

Back as the operator, ask what changed without proposing any action:

```bash
terraform plan -refresh-only -no-color
```

A **refresh-only plan** reads the real objects, compares them with state, and reports the differences. It proposes no change to infrastructure. Real output from this lab:

```
Note: Objects have changed outside of Terraform

  # aws_s3_bucket.data has changed
  ~ resource "aws_s3_bucket" "data" {
      ~ tags                        = {
            "Lab"       = "06-drift-and-import"
            "ManagedBy" = "terraform"
          + "Owner"     = "someone-else"
        }
  ...
  # aws_s3_bucket_public_access_block.data has changed
  ~ resource "aws_s3_bucket_public_access_block" "data" {
      ~ block_public_acls       = true -> false
  ...
This is a refresh-only plan, so Terraform will not take any actions to undo
these.
```

Now the normal plan, which compares the configuration with the refreshed state:

```bash
terraform plan -detailed-exitcode -no-color; echo "exit=$?"
```

The plan ends `Plan: 0 to add, 2 to change, 0 to destroy.`, showing `Owner` removed (`"someone-else" -> null`) and `block_public_acls = false -> true`, then `exit=2`. **`-detailed-exitcode`** makes the exit status carry the result: 0 no changes, 1 error, 2 changes pending. A scheduled pipeline that runs this and alerts on 2 is the cheapest drift detector.

**Revert or accept?** Decide from the security side, not the Terraform side.

| Choice | Command | Effect | Pick it when |
|---|---|---|---|
| Revert | `terraform apply` # [changes state] | Reality is changed back to match the configuration | The configuration is the source of truth and the change was unauthorized or unsafe. Loosening a public access block is this case. |
| Accept | `terraform apply -refresh-only` # [changes state] | State is updated to match reality; infrastructure is untouched | The change was legitimate and urgent (an incident fix), and you will now edit the configuration to match |

Accepting only updates state. The next normal plan will still want to revert unless you also edit the `.tf` files. Before either, find out who made the change; CloudTrail has the answer. See the [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md) and [Detection](../../teaching/01-detection.md). Apply to revert, then re-run the exit-code plan and expect `exit=0`.

### 2. Adopt a resource with `import`

Create a bucket Terraform has never seen:

```bash
aws s3api create-bucket --bucket lab06-legacy     # [changes state]
```

Add to a new file `import.tf`:

```hcl
import {
  to = aws_s3_bucket.archive
  id = "lab06-legacy"
}
```

An **`import` block** tells Terraform to bind an existing real object to a resource address during the next apply. You have not written the resource yet, so have Terraform draft it:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform writes a `resource "aws_s3_bucket" "archive"` block into `generated.tf` with every attribute it read. Generated code is a draft: it lists computed and default values you do not want to pin, and it does not know your tag locals. Open it, delete read-only or noisy arguments, replace literals with references (`tags = local.tags`), and then plan again; a clean import plan says `1 to import, 0 to add, 0 to change, 0 to destroy`. Apply it.

```bash
terraform apply         # [changes state] answer yes
```

Importing creates state only. It never changes the real object. The older command is `terraform import aws_s3_bucket.archive lab06-legacy`: it needs the resource block to exist first, changes state immediately, and cannot be reviewed in a plan. Prefer the block. Either way, the `id` format differs per resource type; the provider documentation lists it on each resource's page.

### 3. Rename with `moved`

Rename `aws_s3_bucket.archive` to `aws_s3_bucket.legacy` in `generated.tf`, then plan with no other change. Terraform proposes to destroy the old address and create the new one, because it sees two unrelated resources. Tell it they are the same object:

```hcl
moved {
  from = aws_s3_bucket.archive
  to   = aws_s3_bucket.legacy
}
```

Plan again. The plan now reports the resource as having moved and shows no create or destroy. A **`moved` block** rewrites the address in state; nothing in AWS is touched. Keep the block until every copy of the state (teammates, pipelines) has applied it, then delete it.

### 4. Stop managing without destroying

Two ways to make Terraform forget a resource while the real bucket survives.

```hcl
removed {
  from = aws_s3_bucket.legacy

  lifecycle {
    destroy = false
  }
}
```

Delete the `resource "aws_s3_bucket" "legacy"` block (also its `moved` block), add the `removed` block, and plan. Expect the plan to say the resource will be removed from state and that it will not be destroyed. Apply, and confirm with `aws s3api head-bucket --bucket lab06-legacy`, which still succeeds.

| Method | Reviewable in a plan | Reproducible by others | Notes |
|---|---|---|---|
| `removed` block with `destroy = false` | Yes | Yes, it lives in the configuration | Preferred. Without `destroy = false` the real object is destroyed. |
| `terraform state rm ADDRESS` | No, it acts at once | No, it edits one state file | Fine for a one-off repair. Leave the resource block in place and the next plan wants to create it again. |

### 5. Force a replacement

Replace a healthy resource, for example when you suspect it was tampered with in a way Terraform cannot see:

```bash
terraform plan -replace=aws_iam_role.app
```

`-replace=ADDRESS` marks one resource for destroy-and-create in this plan. The plan shows `# aws_iam_role.app will be replaced, as requested` with `-/+`. It replaces the old `terraform taint` command, which edited state before you could review anything. Add `-replace` to `apply` to carry it out. Read what depends on the resource first: a replaced role gets a new unique ID, so anything that cached the old ID breaks.

### 6. Inspect state

```bash
terraform state list
```

Real output at the baseline:

```
data.aws_iam_policy_document.assume_ec2
data.aws_vpc.default
aws_iam_role.app
aws_s3_bucket.data
aws_s3_bucket_public_access_block.data
aws_security_group.app
```

Then try the others and compare what each shows:

```bash
terraform state show aws_s3_bucket.data       # every attribute of one resource, human readable
terraform show -json | head -c 600             # the whole state as JSON, for scripts and policy tools
terraform output                               # the root module's outputs
terraform output -raw bucket_name              # one value, unquoted, safe to use in a shell
```

These read the state, not AWS. After the drift in step 1, and before you refresh, they show the old values. Anything stored in state is visible here, secrets included; see [State and backends](../../cheatsheets/terraform-state-and-backends.md).

### 7. Read debug logs

```bash
TF_LOG=DEBUG TF_LOG_PATH=debug.log terraform plan -refresh-only
grep -c . debug.log
grep -i 'x-amz\|Authorization' debug.log | head
```

`TF_LOG` sets the level (`TRACE` is the most verbose, then `DEBUG`, `INFO`, `WARN`, `ERROR`). `TF_LOG_PATH` writes to a file instead of the terminal. The log records each provider API request and response. Expect many hundred lines even for a small plan.

Treat the file like state. Request and response bodies, and on real AWS some header values and session tokens, can land in it, and it often ends up attached to tickets and pasted into chats. Scope `TF_LOG` to one command, never export it in a CI job, delete the file when done, and add `*.log` to `.gitignore`. `TF_LOG_PROVIDER` and `TF_LOG_CORE` set the two levels separately.

## Verify

```bash
aws s3api get-public-access-block --bucket lab06-data --query PublicAccessBlockConfiguration --output json
```

After a fresh apply or after reverting the drift:

```
{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
}
```

```bash
terraform plan -detailed-exitcode; echo "exit=$?"     # exit=0 once configuration, state, and reality agree
terraform state list                                    # matches the list in step 6
```

## Break it

None of these have been run end to end; the descriptions say what you should see.

**1. Import the same object twice.** Add a second `import` block with a different `to` address and the same `id`. Plan should refuse or warn that the object is already managed at another address. Two addresses must never own one real object, or each apply fights the other. Remove the extra block.

**2. Forget `destroy = false`.** Write the `removed` block with an empty `lifecycle {}`. The plan should show the bucket being destroyed. Read plans before applying; a `removed` block is a delete unless you say otherwise.

**3. Skip the `moved` block.** Rename a resource and plan. Expect one destroy and one create. For a stateful resource such as a database this is data loss, and it is the reason `moved` exists.

**4. Hand-edit the state.** Back up `terraform.tfstate`, change a bucket tag value in it, and plan. Terraform should refresh and report no drift for that tag when reality still matches the configuration, because refresh overwrites state from the real object. State is a cache of reality, not the authority. Restore the backup.

**5. Run `state rm` and plan.** `terraform state rm aws_iam_role.app` then `terraform plan`. The plan should want to create `aws_iam_role.app`, which fails on a name collision when applied, since the role still exists. Fix it with an `import` block.

## Clean up

```bash
terraform destroy       # [changes state] removes everything Terraform manages
aws s3api delete-bucket --bucket lab06-legacy     # only if step 4 left it unmanaged
rm -f debug.log generated.tf import.tf
```

Smoke-test run: `terraform destroy` reported `Destroy complete! Resources: 4 destroyed.` and no bucket or role named `lab06...` remained.

## What differs on real AWS

- **Who changed it.** Here the "other person" is you. On AWS, find the actor in CloudTrail (`PutPublicAccessBlock`, `PutBucketTagging`, `AuthorizeSecurityGroupIngress`) before deciding to revert. See [CloudTrail tampering](../../runbooks/cloudtrail-tampering.md) for log integrity.
- **Detection latency.** Drift is only found when something runs a plan. Real estates add AWS Config rules, or EventBridge on the API calls, so the alert arrives in minutes rather than at the next pipeline run **(verify)**.
- **Import ids and generated config.** Formats differ per resource, and generated config on real AWS carries many more attributes. Review it as code.
- **S3 bucket names** are global; `lab06-data` would collide. Add an account ID or random suffix.
- **Debug logs.** Real logs contain real credentials' signed headers. Never share them unredacted.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
