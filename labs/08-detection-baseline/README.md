# Lab 08: Detection baseline

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2c · **SCS-C03:** 1.1.4, 1.2.2 · **Time:** 60 minutes · **Related:** [Terraform fundamentals](../../teaching/terraform/02-terraform-fundamentals.md), [State management](../../teaching/terraform/06-state-management.md), [Maintaining infrastructure](../../teaching/terraform/07-maintaining-infrastructure.md), [Detection](../../teaching/01-detection.md), [Terraform CLI cheatsheet](../../cheatsheets/terraform-cli.md), [State and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [Logging sources](../../cheatsheets/logging-sources.md), [Unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md), [CloudTrail tampering runbook](../../runbooks/cloudtrail-tampering.md)

> **Test status:** smoke-tested on floci (init, validate, apply, Verify, destroy) on 2026-11-11. The step-by-step outputs and the "Break it" exercises have not been run end to end yet.

## Goal

Build a small audit and alerting baseline as code: a CloudTrail trail with log file validation writing to a locked-down bucket, an EventBridge rule that fires on attempts to stop or weaken that trail, an SNS topic as the alert target, and a CloudWatch Logs metric filter. Along the way, use **two configurations of the same provider** (one per Region), select between them on a resource, and pass one into a module. Afterward you can say which Region a resource lands in and why.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) first.
- Read the provider sections of [Terraform fundamentals](../../teaching/terraform/02-terraform-fundamentals.md) and skim [Logging sources](../../cheatsheets/logging-sources.md).

| File | Holds |
|---|---|
| `providers.tf` | Two `provider "aws"` blocks: the default (us-east-1) and `alias = "west"` (us-west-2), each with the full lab settings |
| `main.tf` | Log bucket and policy, trail, alert topic, EventBridge rule and target, log group and metric filter, two us-west-2 topics |
| `modules/regional-topic/main.tf` | A module that creates one SNS topic in whatever provider it is handed |
| `outputs.tf` | Trail ARN, alerts topic ARN, the two us-west-2 topic ARNs |

## Steps

### 1. Read the two provider blocks

`providers.tf` declares `provider "aws"` twice. The first has no `alias`, so it is the **default provider configuration**: any resource that does not name a provider uses it. The second has `alias = "west"` and `region = "us-west-2"`. A resource uses it only if it says so. Both carry the lab settings and an `endpoints` entry for every service used (`cloudtrail`, `events`, `logs`, `s3`, `sns`, `sts`), because each configuration is separate and nothing is inherited from the default.

Why have two? A provider configuration is bound to one Region (and one account and role). To manage resources in a second Region, or a second account, you need a second configuration. Terraform provider version and source are declared once in `required_providers`; only the configuration is repeated.

### 2. Initialize and check

```bash
terraform init          # [changes state]
terraform validate
terraform fmt -check -recursive
```

`validate` prints `Success! The configuration is valid.`, and `fmt -check` prints nothing and exits 0. `init` also installs the local module from `modules/regional-topic`.

### 3. Choose a provider on a resource

At the bottom of `main.tf`:

```hcl
resource "aws_sns_topic" "west_alerts" {
  provider = aws.west
  name     = "lab08-west-alerts"
}
```

`provider = aws.west` is the **provider** meta-argument: `TYPE.ALIAS`, with no quotes. Every other resource in the file omits it and goes to us-east-1. The topic's ARN will contain `us-west-2`. The setting is stored in state, so you cannot change which configuration a resource uses without a replace or a move.

### 4. Pass a provider into a module

```hcl
module "west_topic" {
  source = "./modules/regional-topic"

  providers = {
    aws = aws.west
  }

  name = "lab08-module-west"
}
```

A module does not see the root's aliased providers automatically. It inherits only the **default** configuration, unless the caller passes others in with `providers`. The left side of each pair (`aws`) is the name the module uses internally; the right side (`aws.west`) is the root's configuration. Inside the module the topic resource has no `provider` argument and never mentions a Region: the caller decides. Open `modules/regional-topic/main.tf` and see that it declares only `required_providers`, which says what it needs. If the module needed two configurations (say a primary and a replica), it would declare `configuration_aliases = [aws.replica]` in `required_providers` and the caller would pass `aws.replica = aws.west`.

### 5. Read the detection resources

| Resource | What it does |
|---|---|
| `aws_s3_bucket.trail` and `aws_s3_bucket_policy.trail` | Log bucket. The policy lets the `cloudtrail.amazonaws.com` service principal read the ACL and write objects under `AWSLogs/ACCOUNT_ID/`, and requires `bucket-owner-full-control`. |
| `aws_cloudtrail.main` | The trail: `is_multi_region_trail = true` and `enable_log_file_validation = true`. `depends_on` the bucket policy, since nothing in its arguments references it. |
| `aws_sns_topic.security_alerts` | Where alerts go. |
| `aws_cloudwatch_event_rule.trail_tampering` | Matches CloudTrail-recorded API calls named `StopLogging`, `DeleteTrail`, or `PutBucketPolicy`. |
| `aws_cloudwatch_event_target.alert` | Sends matches to the topic. |
| `aws_cloudwatch_log_group.trail` and `aws_cloudwatch_log_metric_filter.root_usage` | Counts log events where the root user acted. A CloudWatch alarm on the metric would complete the pattern. |

**Log file validation** makes CloudTrail write signed digest files so you can later prove log files were not altered or removed. See [Detection](../../teaching/01-detection.md) and the [CloudTrail tampering runbook](../../runbooks/cloudtrail-tampering.md) for why those three API calls are the ones to alert on.

### 6. Apply

```bash
terraform apply         # [changes state] answer yes
```

```
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

alerts_topic_arn = "arn:aws:sns:us-east-1:000000000000:lab08-security-alerts"
trail_arn = "arn:aws:cloudtrail:us-east-1:000000000000:trail/lab08-trail"
west_topic_arns = [
  "arn:aws:sns:us-west-2:000000000000:lab08-west-alerts",
  "arn:aws:sns:us-west-2:000000000000:lab08-module-west",
]
```

The ten resources are the bucket, bucket policy, trail, alert topic, rule, target, log group, metric filter, and the two us-west-2 topics. The module's topic appears in `terraform state list` as `module.west_topic.aws_sns_topic.this`. Note the Region in the last two ARNs: one from `provider = aws.west`, one from the module.

## Verify

```bash
aws cloudtrail describe-trails \
  --query 'trailList[].[Name,IsMultiRegionTrail,LogFileValidationEnabled,S3BucketName]' --output text
```

```
lab08-trail	True	True	lab08-trail-logs
```

```bash
aws events list-rules --name-prefix lab08 --query 'Rules[].[Name,State]' --output text
aws events list-targets-by-rule --rule lab08-trail-tampering --query 'Targets[].Arn' --output text
```

```
lab08-trail-tampering	ENABLED
arn:aws:sns:us-east-1:000000000000:lab08-security-alerts
```

```bash
aws sns list-topics --region us-west-2 --query 'Topics[].TopicArn' --output text
```

```
arn:aws:sns:us-west-2:000000000000:lab08-module-west	arn:aws:sns:us-west-2:000000000000:lab08-west-alerts
```

The default-Region topic list (no `--region`) shows only `lab08-security-alerts`, confirming the west topics are not in us-east-1.

```bash
aws logs describe-metric-filters --log-group-name lab08-trail-events \
  --query 'metricFilters[].[filterName,metricTransformations[0].metricName]' --output text
```

```
lab08-root-account-usage	RootAccountUsage
```

## Break it

None of these have been run end to end; the descriptions say what you should see.

**1. Remove `provider = aws.west`.** Delete the line from `aws_sns_topic.west_alerts` and run `terraform plan`. Terraform should propose to replace the topic: the name is unchanged, but the resource now belongs to the default configuration, so the plan shows it destroyed and recreated in us-east-1. Read the ARN change (`us-west-2` to `us-east-1`) in the plan. Nothing errors; a missing `provider` line silently moves the resource to the wrong Region. Restore the line.

**2. Reference an alias that does not exist.** Change `aws.west` to `aws.east` on the resource. `terraform validate` or `plan` should fail with an error that the provider configuration `aws.east` is not declared. Declare the alias or fix the name. Restore.

**3. Omit `providers` on the module call.** Delete the `providers` block from `module "west_topic"`. Plan should succeed and place the module's topic in us-east-1, because the module inherits the default configuration. This is the module version of Break it 1, and it is just as quiet. Restore.

**4. Leave out `depends_on` on the trail.** Remove it and apply on a fresh state. On floci, which does not enforce bucket policies, the apply should still succeed. On real AWS it can fail with an `InsufficientS3BucketPolicyException` because CloudTrail validates the bucket policy at creation. Restore.

**5. Drop an endpoint.** Delete `events` from one provider's `endpoints` block and plan. With `AWS_ENDPOINT_URL` exported the call still reaches floci; unset it and the call goes to real AWS and fails on the fake credentials. Restore.

## Clean up

```bash
terraform destroy       # [changes state] Destroy complete! Resources: 10 destroyed.
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `lab08`)].Name' --output text    # prints nothing
```

The bucket sets `force_destroy = true` so destroy empties it first. Do not do that with a real audit log bucket.

## What differs on real AWS

- **The pipeline does not alert yet.** The rule matches events, but this lab does not test whether the emulator delivers CloudTrail events to EventBridge **(verify)**. Also, SNS delivers to nothing until you add a subscription (email, chat webhook, or a function), and the topic needs a resource policy that lets `events.amazonaws.com` publish to it. Add both.
- **No log delivery to CloudWatch Logs.** A real trail sends events to a log group through `cloud_watch_logs_group_arn` and an IAM role that CloudTrail assumes. The group and metric filter here are unconnected to the trail, and there is no alarm on the metric.
- **Bucket and key.** Real audit buckets are encrypted with a KMS key (CloudTrail needs permission on it), block public access, and often live in a separate log-archive account. See [Lab 05](../05-kms-and-secrets/README.md). Bucket names are global; add a suffix.
- **Bucket policy is not enforced** by floci, so a wrong policy here still "works".
- **Event source for management events** in us-east-1 only: global services such as IAM log in that Region, and EventBridge rules are Regional, so a rule in one Region does not see calls recorded in another **(verify)**. This is the practical reason for multiple provider configurations in a detection baseline.
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from both provider blocks, as [labs/README.md](../README.md#the-lab-provider-block) describes. Credentials come from the environment or an assumed role.
