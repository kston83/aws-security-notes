# Organization policies cheatsheet: SCPs, RCPs, declarative policies

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 6.1.3 · **Teaching note:** [Domain 6](../teaching/06-security-foundations-and-governance.md)

## Which policy for which job

| You want to | Use |
|---|---|
| Stop principals **in your accounts** from doing something, anywhere | **SCP** |
| Stop **anyone, including external principals**, from accessing resources in your accounts | **RCP** |
| Fix a **service configuration** in place so no API call can change it | **Declarative policy** |
| Standardize tags | Tag policy |
| Push backup plans | Backup policy |
| Opt out of AI service data use | AI services opt-out policy |

SCPs are principal-centric. RCPs are resource-centric. A data perimeter uses both.

## Side by side

| | SCP | RCP | Declarative policy |
|---|---|---|---|
| Evaluated against | Principals in member accounts | Resources in member accounts | Service configuration state |
| Grants permissions | Never | Never | n/a |
| Affects management account | No | No | Check per attribute **(verify)** |
| Affects service-linked roles | No | No | n/a (enforced by the service) |
| Affects member account root user | Yes | Yes | Yes |
| Affects principals outside the org | No | **Yes** | n/a |
| Service coverage | All services | Listed services only | EC2 and VPC attributes |
| Default policy | `FullAWSAccess` (detachable) | `RCPFullAWSAccess` (not detachable) | None |
| Statements you write | Allow or Deny | Deny only | Attribute settings |
| `Principal` element | Not used | Must be `"*"` | n/a |

Limits **(verify)**: 5,120 characters per policy; a small fixed number of policies of each type per attachment point; OU nesting up to five levels.

## SCP essentials

- **Inheritance:** an action must be allowed at every level from root to account. A deny at any level wins.
- **Deny-list strategy** (most common): keep `FullAWSAccess` everywhere and add deny statements.
- **Allow-list strategy:** replace `FullAWSAccess` with explicit allows. Must be repeated at every level down.
- Always exempt your automation and break-glass roles by condition, or you will lock yourself out.
- Test on a single account or a policy-staging OU before attaching at the root.

### SCP patterns

**Region restriction**

```json
{
  "Sid": "DenyOutsideApprovedRegions",
  "Effect": "Deny",
  "NotAction": [
    "iam:*", "organizations:*", "route53:*", "cloudfront:*", "sts:*",
    "support:*", "budgets:*", "ce:*", "globalaccelerator:*", "waf:*", "shield:*",
    "route53domains:*", "health:*", "account:*", "billing:*"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": { "aws:RequestedRegion": ["eu-west-1", "eu-central-1"] },
    "ArnNotLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/platform/*" }
  }
}
```

The list of global services to exempt changes over time; start from the current AWS example.

**Protect security tooling**

```json
{
  "Sid": "ProtectSecurityServices",
  "Effect": "Deny",
  "Action": [
    "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
    "guardduty:DeleteDetector", "guardduty:DisassociateFromAdministratorAccount", "guardduty:UpdateDetector",
    "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
    "securityhub:DisableSecurityHub", "securityhub:DisassociateFromAdministratorAccount",
    "access-analyzer:DeleteAnalyzer"
  ],
  "Resource": "*",
  "Condition": { "ArnNotLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/security/*" } }
}
```

**Deny leaving the organization**

```json
{ "Effect": "Deny", "Action": "organizations:LeaveOrganization", "Resource": "*" }
```

**Deny root user actions in member accounts**

```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": { "ArnLike": { "aws:PrincipalArn": "arn:aws:iam::*:root" } }
}
```

**Require IMDSv2 on launch**

```json
{
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": { "StringNotEquals": { "ec2:MetadataHttpTokens": "required" } }
}
```

**Require a tag at creation**

```json
{
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": { "Null": { "aws:RequestTag/owner": "true" } }
}
```

**Stop access to resources outside the organization (resource perimeter)**

```json
{
  "Effect": "Deny",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "*",
  "Condition": {
    "StringNotEqualsIfExists": { "aws:ResourceOrgID": "o-EXAMPLE" },
    "BoolIfExists": { "aws:ViaAWSService": "false" }
  }
}
```

**Quarantine (incident response)**

```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": { "ArnNotLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/security/IncidentResponder" } }
}
```

## RCP essentials

- Apply to resources in **member accounts** for a list of supported services. At last review the list included S3, STS, KMS, SQS, Secrets Manager, DynamoDB, ECR, CloudWatch Logs, Cognito, OpenSearch, EventBridge, and several dozen more. It grows; check the [current list](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html#rcp-supported-services) **(verify)**.
- Apply to every caller, inside or outside the organization, including root users.
- Do **not** apply to: resources in the management account, service-linked roles, AWS managed KMS keys, `kms:RetireGrant`.
- You write only `Deny` statements with `"Principal": "*"`.
- An RCP on STS restricts who can assume roles in your accounts: an organization-wide control over role trust.

### RCP patterns

**Identity perimeter: only my organization's principals and AWS services**

```json
{
  "Sid": "EnforceOrgIdentities",
  "Effect": "Deny",
  "Principal": "*",
  "Action": ["s3:*", "sqs:*", "kms:*", "secretsmanager:*", "sts:*"],
  "Resource": "*",
  "Condition": {
    "StringNotEqualsIfExists": { "aws:PrincipalOrgID": "o-EXAMPLE" },
    "BoolIfExists": { "aws:PrincipalIsAWSService": "false" }
  }
}
```

Add an exception (for example by `aws:PrincipalAccount` or a resource tag) for trusted third parties that legitimately need access.

**Confused deputy protection: AWS services may only act for my organization**

```json
{
  "Sid": "EnforceConfusedDeputyProtection",
  "Effect": "Deny",
  "Principal": "*",
  "Action": ["s3:*", "sqs:*", "kms:*", "secretsmanager:*", "sts:*"],
  "Resource": "*",
  "Condition": {
    "StringNotEqualsIfExists": { "aws:SourceOrgID": "o-EXAMPLE" },
    "Null": { "aws:SourceAccount": "false" },
    "Bool": { "aws:PrincipalIsAWSService": "true" }
  }
}
```

**Require TLS on all supported resources**

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": ["s3:*", "sqs:*", "kms:*", "secretsmanager:*", "sts:*"],
  "Resource": "*",
  "Condition": { "BoolIfExists": { "aws:SecureTransport": "false" } }
}
```

## Declarative policies

Enforce the desired configuration of a service at the organization, OU, or account level. The service itself maintains the setting, so it holds even for new APIs and for callers an SCP might miss. A custom error message tells users why an action failed.

EC2 attributes covered at last review **(verify)**:

| Attribute | Effect |
|---|---|
| VPC Block Public Access | Blocks internet gateway traffic |
| Serial console access | Allows or blocks EC2 serial console |
| Image block public access | Stops AMIs being made public |
| Allowed images settings | Restricts which AMIs can be discovered and launched |
| Instance metadata defaults | Sets IMDSv2 and hop limit defaults for new instances |
| Snapshot block public access | Stops EBS snapshots being shared publicly |

Generate an account status report before attaching, to see the current state across the organization.

## Data perimeter summary

| Perimeter | Objective | Control | Key condition |
|---|---|---|---|
| Identity | Only trusted identities access my resources | RCP, resource policies | `aws:PrincipalOrgID`, `aws:PrincipalIsAWSService` |
| Identity | Only trusted identities use my networks | VPC endpoint policy | `aws:PrincipalOrgID` |
| Resource | My identities access only trusted resources | SCP | `aws:ResourceOrgID` |
| Resource | Only trusted resources reachable from my networks | VPC endpoint policy | `aws:ResourceOrgID` |
| Network | My identities act only from expected networks | SCP | `aws:SourceIp`, `aws:SourceVpc`, `aws:SourceVpce`, `aws:ViaAWSService` |
| Network | My resources are accessed only from expected networks | RCP, resource policies | Same |

## Rollout checklist

1. Write the policy with exemptions for automation, security, and break-glass roles.
2. Check CloudTrail for existing activity the policy would block.
3. Attach to one sandbox account. Exercise real workflows.
4. Attach to a policy-staging OU.
5. Attach to non-production OUs, then production.
6. Watch for `AccessDenied` in CloudTrail with the policy named in the message.
7. Record the policy in version control, with the reason and owner.
