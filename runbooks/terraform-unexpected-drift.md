# Unexpected Terraform drift

> **Last reviewed:** 2026-11-11 · **Severity:** Medium; High or Critical once the change is shown to be unauthorized or to weaken a security control · **SCS-C03:** 2.2.2, 2.2.3, 2.2.4, 6.2.1, 6.3.1 · **Terraform Associate (004):** 3d, 6d, 7a · **NIST 800-53:** CM-2, CM-3, CM-6, SI-7, AU-6, IR-4

**Drift** is a difference between live infrastructure and what Terraform's state and configuration say it should be. Drift nobody owns is an unauthorized change until shown otherwise. Background: [state management](../teaching/terraform/06-state-management.md), [maintaining infrastructure](../teaching/terraform/07-maintaining-infrastructure.md).

## Trigger

- A scheduled `terraform plan -refresh-only -detailed-exitcode` exits `2`
- HCP Terraform drift detection (a health assessment; Standard and Premium editions, remote or agent execution **(verify)**) flags a workspace
- An ordinary `terraform plan` proposes changes although no code changed
- An AWS Config rule turns noncompliant, or a configuration change notification arrives, for a resource Terraform manages
- No pull request, ticket, or change record explains it

## Triage

**1. Read the drift.** Save the plan and read it as JSON. The plan file contains secrets; keep it with the evidence.

```bash
terraform plan -refresh-only -out=drift.tfplan
terraform show -json drift.tfplan | jq -c '.resource_drift[]? | {address, actions: .change.actions}'
terraform show -json drift.tfplan | jq '.resource_drift[]? | select(.address=="RESOURCE_ADDRESS") | {before: .change.before, after: .change.after}'
```

`-refresh-only` reports only attributes of resources already in state. It does not see resources created outside Terraform (a new IAM user, a new security group). Also run a normal `terraform plan` to see the difference from configuration.

**2. Classify each drifted attribute.**

| Looks benign | Looks malicious |
|---|---|
| AWS-side default or computed value filled in after a provider upgrade | Security group rule opened, especially to `0.0.0.0/0` or `::/0` |
| Tags added by another automation (backup, cost allocation) | IAM policy attached, inline policy added, trust policy widened, access key created |
| Auto scaling changed a desired count | Trail, flow log, Config recorder, or GuardDuty setting disabled or narrowed |
| Managed service applied a minor version or rotated a certificate | Bucket policy, KMS key policy, or public access block loosened |
| A console hotfix by a named engineer during a known incident | Encryption turned off; snapshot or AMI shared with another account |

**3. Does the change widen access or reduce visibility right now?** If yes, go to Contain before attributing it. Otherwise attribute first (Investigate).

Stop when the change is attributed to an expected principal, with a reason, and reconciled (Recover). Escalate when the principal is unknown, the principal denies making it, or the change is in the right-hand column.

## Contain

**1. Capture the live resource first** (see Preserve evidence). It takes a minute, and reverting destroys the as-found configuration.

**2. Hold automatic applies** for the workspace, so that a scheduled run does not overwrite the change before it is captured. Do not hold them longer than the capture takes if the drift is an exposure.

**3. Close a dangerous exposure,** narrowly. Revert only the affected resource:

```bash
terraform plan -target=RESOURCE_ADDRESS -out=revert.tfplan      # review: only this resource changes
# [changes state] sets the live resource back to what the configuration says
terraform apply revert.tfplan
```

Side effect: if the change was a legitimate hotfix, this undoes it; the owner will tell you quickly. `-target` is for exceptional use and leaves the rest of the drift in place for investigation.

**4. Malicious change: contain the principal,** not just the resource. Route by what was changed:

| Change | Runbook |
|---|---|
| Any change by an unknown or unexpected principal | [Compromised IAM credentials](compromised-iam-credentials.md) |
| Logging or a detective service altered | [CloudTrail tampering](cloudtrail-tampering.md) |
| Bucket policy, ACL, or public access block loosened | [S3 data exposure](s3-data-exposure.md) |
| KMS key disabled or scheduled for deletion | [KMS key scheduled for deletion](kms-key-scheduled-deletion.md) |
| The deployment role itself made a change that is not in the repository | [Terraform pipeline compromise](terraform-pipeline-compromise.md) |
| State was edited to hide the change | [State lock and corruption](terraform-state-lock-and-corruption.md) |

## Preserve evidence

```bash
terraform show -json drift.tfplan > evidence/drift-$(date -u +%Y%m%dT%H%M%SZ).json
terraform state pull > evidence/state-as-found.json
aws configservice get-resource-config-history --resource-type RESOURCE_TYPE --resource-id RESOURCE_ID --limit 10 > evidence/RESOURCE_ID-config-history.json
```

`RESOURCE_TYPE` is the Config type, for example `AWS::EC2::SecurityGroup`. Also save the service's own describe output for the resource (`aws ec2 describe-security-groups --group-ids GROUP_ID`, `aws iam get-role --role-name ROLE_NAME`, and so on). All of these files can hold secrets.

## Investigate

**1. Attribute each change to a principal.** Event history covers 90 days of management events per Region:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=RESOURCE_ID \
  --start-time START_TIME --end-time END_TIME \
  --query 'Events[].[EventTime,EventName,Username]' --output table
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=RESOURCE_ID \
  --start-time START_TIME --end-time END_TIME --query 'Events[].CloudTrailEvent' --output text \
  | jq -c 'select(.readOnly == false) | {eventTime, eventName, arn: .userIdentity.arn, sourceIPAddress, userAgent, requestParameters}'
```

`RESOURCE_ID` is the ID CloudTrail records (security group ID, role name, bucket name), not the Terraform address. IAM events are global and are recorded in `us-east-1`. Bracket the time with Config history: the change lies between the last compliant configuration item and the first drifted one.

**2. Judge the principal.**

| Principal | Reading |
|---|---|
| Deployment role, Terraform user agent | Another workspace or configuration manages the same resource, or the pipeline applied something unreviewed |
| AWS service or service-linked role | AWS-side change. Usually benign; adjust the configuration. |
| Another automation role | Two tools fight over one attribute. Decide which owns it. |
| A person through the console or CLI | Ask them. A hotfix has a ticket; no ticket and no memory of it means compromised credentials. |
| Unknown role, unfamiliar IP, or root | Malicious until disproved |

**3. What else did that principal do?** One drifted resource is the one Terraform happens to manage. Search the whole account and all Regions for the principal's write calls: [CLI one-liners](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail).

**4. Was the change used?** An opened security group: flow logs for accepted connections on the new rule. An attached policy: calls it newly allowed. A loosened bucket policy: data events from outside the organization.

## Eradicate

- Remove what the unauthorized principal created outside Terraform (it is not in state, so `apply` will not remove it).
- Rotate anything the change exposed.
- Benign causes: fix the cause, not the symptom. Make one tool the owner of the attribute, or record the AWS-side value in configuration.

## Recover

Decide per resource. Do not run a blanket `terraform apply` before the change is understood and captured: it erases the as-found configuration. Do not run `terraform apply -refresh-only` before then either: it writes the drifted values into state, the scheduled check goes quiet, and a malicious change now looks accepted.

| Situation | Action |
|---|---|
| Unauthorized or unwanted | Revert: `terraform plan`, review, **[changes state]** `terraform apply` (state and infrastructure) |
| Legitimate and should stay | Adopt into code: edit the configuration to match, open a pull request, and confirm `terraform plan` shows no changes for it |
| AWS-side value that Terraform should stop managing | `lifecycle { ignore_changes = [ATTRIBUTE] }`, narrowly, with a comment saying why |
| Computed attribute changed and configuration is unaffected | **[changes state]** `terraform apply -refresh-only` (state only), after reading every line it proposes |
| Resource created outside Terraform that should be kept | `import` block and matching configuration. [Lab 06](../labs/06-drift-and-import/README.md) |

Finish with `terraform plan -detailed-exitcode` returning `0`, the Config rule compliant, and the drift check re-enabled.

## Follow up

| Gap | Fix |
|---|---|
| People can change managed resources by hand | Read-only access for humans in production; changes only through the deployment role; SCP denying sensitive actions except for that role. [Org policies](../cheatsheets/org-policies-scp-rcp.md#scp-patterns) |
| Hotfixes never reach code | Break-glass procedure that requires a follow-up pull request |
| Drift found days later | Scheduled `plan -refresh-only -detailed-exitcode` per workspace, alerting on exit `2`; HCP Terraform health assessments. [HCP Terraform](../teaching/terraform/08-hcp-terraform.md), [Terraform CLI cheatsheet](../cheatsheets/terraform-cli.md) |
| Security-relevant drift waits for the next plan | EventBridge rules and Config rules on the specific changes (security group ingress, IAM policy attachment, logging changes). [Lab 08](../labs/08-detection-baseline/README.md) |
| Resources outside Terraform are invisible to it | Config recording everywhere; periodic inventory of unmanaged resources |
| `ignore_changes` used to silence drift | Review every `ignore_changes` in code review. [AWS provider security cheatsheet](../cheatsheets/terraform-aws-provider-security.md) |
| Controls not mapped | [IaC control mapping](../control-mappings/services/iac-terraform.md); [securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md) |
