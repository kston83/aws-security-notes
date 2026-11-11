# IAM policy evaluation cheatsheet

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 4.2.1, 4.2.3, 4.2.4 · **Teaching note:** [Domain 4](../teaching/04-identity-and-access-management.md)

## The decision flow

```
Request arrives
   │
   ▼
1. Explicit DENY in ANY applicable policy?  ───────────── yes ──▶ DENY
   │ no
   ▼
2. SCPs: does every level (root, OUs, account) ALLOW it?  ─ no ──▶ DENY (implicit)
   │ yes  (skipped for management account and service-linked roles)
   ▼
3. RCPs: does every level ALLOW it?  ───────────────────── no ──▶ DENY (implicit)
   │ yes  (only for supported services; skipped for management account resources)
   ▼
4. Resource-based policy ALLOWS it?  ───────────────────── yes ─▶ ALLOW*  (same account)
   │ no
   ▼
5. Identity-based policy ALLOWS it?  ───────────────────── no ──▶ DENY (implicit)
   │ yes
   ▼
6. Permissions boundary ALLOWS it? (if one is set) ─────── no ──▶ DENY (implicit)
   │ yes
   ▼
7. Session policy ALLOWS it? (if one was passed) ───────── no ──▶ DENY (implicit)
   │ yes
   ▼
ALLOW
```

\* Step 4 has conditions; see [Resource policy shortcuts](#resource-policy-shortcuts).

## What each policy type does

| Policy | Grants | Limits | Scope |
|---|---|---|---|
| Identity-based | ✔ | | The principal it is attached to |
| Resource-based | ✔ | | The resource; names principals |
| Permissions boundary | | ✔ | Identity-based grants for that user or role |
| Session policy | | ✔ | One session |
| SCP | | ✔ | All principals in member accounts under the attachment point |
| RCP | | ✔ | All access to supported resources in member accounts under the attachment point |
| VPC endpoint policy | | ✔ | Requests through that endpoint |
| Explicit deny in any of the above | | Overrides everything | |

## Same account vs cross account

| Scenario | Needed for allow |
|---|---|
| Same account | Identity policy **or** resource policy allows (and no limit blocks it) |
| Cross account | Identity policy in caller's account **and** resource policy in resource's account both allow |
| Cross account by assuming a role | Caller's identity policy allows `sts:AssumeRole` **and** role trust policy allows the caller; then the role's own policies apply in the target account |

KMS is special even in the same account: the **key policy must allow**, either directly or by delegating to IAM with the account-root statement. See [KMS cheatsheet](kms.md#key-policy).

## Resource policy shortcuts

Who the resource policy names as principal changes what else is evaluated (same account):

| Resource policy principal | Identity policy needed? | Permissions boundary applies? | Session policy applies? |
|---|---|---|---|
| IAM user ARN | No | No | n/a |
| IAM role ARN | No | **Yes** | **Yes** |
| Role **session** ARN (`assumed-role/...`) | No | No | No |
| Account (`:root`) | Yes, delegates to IAM | Yes | Yes |

An explicit deny in the boundary or session policy still wins in every row.

## Policy element quick reference

| Element | Notes |
|---|---|
| `Effect` | `Allow` or `Deny` |
| `Principal` / `NotPrincipal` | Resource-based and trust policies only. Avoid `NotPrincipal` with `Deny`; use a condition on `aws:PrincipalArn` instead. |
| `Action` / `NotAction` | `NotAction` with `Deny` = "deny everything except". `NotAction` with `Allow` grants far more than people expect. |
| `Resource` / `NotResource` | ARNs, wildcards allowed |
| `Condition` | All operators in a block are ANDed. Multiple keys under one operator are ANDed. Multiple values for one key are ORed. |

### Condition operators

| Operator | Use |
|---|---|
| `StringEquals`, `StringNotEquals`, `StringLike` | Exact and wildcard string match |
| `ArnEquals`, `ArnLike` | ARN match |
| `IpAddress`, `NotIpAddress` | CIDR match |
| `Bool` | true / false |
| `NumericLessThan`, `DateGreaterThan`, ... | Numbers and dates |
| `Null` | `"true"` = key is absent; `"false"` = key is present |
| `...IfExists` | Condition passes if the key is absent |
| `ForAllValues:`, `ForAnyValue:` | Multi-valued keys such as `aws:TagKeys` |

**Trap:** negated operators (`StringNotEquals`) evaluate to true when the key is **absent**. A deny with `StringNotEquals` on `aws:SourceVpce` blocks requests that did not come through any endpoint, which is usually what you want, and also AWS service calls, which often is not.

**Trap:** `ForAllValues` evaluates to true when the key is absent or empty. Pair it with a `Null` check in allow statements.

## Policy variables

| Variable | Resolves to |
|---|---|
| `${aws:username}` | IAM user name |
| `${aws:userid}` | Unique ID (for roles: `ROLEID:session-name`) |
| `${aws:PrincipalTag/key}` | Tag on the principal or session |
| `${aws:PrincipalAccount}` | Caller's account ID |
| `${cognito-identity.amazonaws.com:sub}` | Cognito identity ID |
| `${saml:sub}`, `${iot:Connection.Thing.ThingName}` | Federation and IoT values |

## Patterns

**Require MFA for everything except setting up MFA**

```json
{
  "Effect": "Deny",
  "NotAction": ["iam:CreateVirtualMFADevice", "iam:EnableMFADevice", "iam:ListMFADevices", "iam:GetUser", "sts:GetSessionToken"],
  "Resource": "*",
  "Condition": { "BoolIfExists": { "aws:MultiFactorAuthPresent": "false" } }
}
```

**Delegate role creation safely (permissions boundary required)**

```json
{
  "Effect": "Allow",
  "Action": ["iam:CreateRole", "iam:AttachRolePolicy", "iam:PutRolePolicy"],
  "Resource": "arn:aws:iam::111122223333:role/app/*",
  "Condition": { "StringEquals": { "iam:PermissionsBoundary": "arn:aws:iam::111122223333:policy/AppBoundary" } }
}
```

Also deny `iam:DeleteRolePermissionsBoundary`, and deny changes to the boundary policy itself.

**Scope PassRole**

```json
{
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": "arn:aws:iam::111122223333:role/app/*",
  "Condition": { "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" } }
}
```

**Cross-account trust with external ID**

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::444455556666:root" },
  "Action": "sts:AssumeRole",
  "Condition": { "StringEquals": { "sts:ExternalId": "UNIQUE_PER_CUSTOMER_VALUE" } }
}
```

**OIDC trust for a CI pipeline, pinned to one repository and branch**

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
    }
  }
}
```

**Service confused-deputy guard (resource or trust policy)**

```json
"Condition": {
  "StringEquals": { "aws:SourceAccount": "111122223333" },
  "ArnLike": { "aws:SourceArn": "arn:aws:cloudtrail:*:111122223333:trail/*" }
}
```

**Revoke all sessions issued before a time**

```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": { "DateLessThan": { "aws:TokenIssueTime": "2026-11-10T14:00:00Z" } }
}
```

## Privilege escalation actions to watch

A principal with any of these on broad resources can usually become admin:

| Action | Path |
|---|---|
| `iam:CreatePolicyVersion`, `iam:SetDefaultPolicyVersion` | Rewrite a policy attached to self |
| `iam:AttachUserPolicy`, `iam:AttachRolePolicy`, `iam:PutUserPolicy`, `iam:PutRolePolicy` | Attach admin to self |
| `iam:CreateAccessKey`, `iam:CreateLoginProfile`, `iam:UpdateLoginProfile` | Take over another user |
| `iam:UpdateAssumeRolePolicy` | Add self to a privileged role's trust |
| `iam:PassRole` + `lambda:CreateFunction`, `ec2:RunInstances`, `cloudformation:CreateStack`, `glue:CreateDevEndpoint`, and similar | Run code as a more privileged role |
| `iam:AddUserToGroup` | Join an admin group |
| `sts:AssumeRole` on `*` | Assume anything whose trust allows the account |

## Troubleshooting order

1. Read the access denied message; it names the policy type when it can.
2. CloudTrail event: exact principal ARN, action, resource, `errorCode`.
3. Explicit deny anywhere (SCP, RCP, boundary, identity, resource, endpoint policy).
4. Is there a grant at all? Check both sides for cross-account.
5. Conditions: Region, MFA, tags, source network, encryption context, TLS.
6. Dependent permissions: KMS for encrypted data, `iam:PassRole`, service-linked role creation.
7. Eventual consistency: wait a few seconds and retry after a change.
