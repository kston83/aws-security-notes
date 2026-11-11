# Domain 4: Identity and Access Management

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 4.1.1–4.1.3, 4.2.1–4.2.5 (20%) · **Related:** [policy evaluation cheatsheet](../cheatsheets/iam-policy-evaluation.md), [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md), [compromised credentials runbook](../runbooks/compromised-iam-credentials.md), [identity mappings](../control-mappings/services/identity.md)

## Why this matters

Every AWS API call is authenticated and authorized. The network can be bypassed by a valid credential; IAM cannot. This is the heaviest exam domain and the one every other domain leans on. KMS key policies, S3 bucket policies, SCPs, and VPC endpoint policies are all the same policy language evaluated by the same engine.

## Mental model

Every request carries four things. Authorization is a function of them and nothing else.

```
  PRINCIPAL        ACTION           RESOURCE              CONTEXT
  who is asking    what they want   what it acts on       conditions of the request
  (role session,   (s3:GetObject)   (arn:aws:s3:::b/k)    (source IP, VPC endpoint, MFA,
   user, service)                                          tags, org ID, time, TLS)
```

Authentication establishes the principal. Authorization evaluates every applicable policy against the request:

1. **Any explicit deny, in any policy, ends it.** Denied.
2. Otherwise, every policy type that acts as a **limit** must allow it: SCPs, RCPs, permissions boundaries, session policies.
3. And something must **grant** it: an identity-based policy, or a resource-based policy.
4. If nothing grants it, the answer is an implicit deny.

Grants are a union. Limits are an intersection. Deny beats everything. The full flow with edge cases is in the [policy evaluation cheatsheet](../cheatsheets/iam-policy-evaluation.md).

## Task 4.1: Authentication

### Choosing an identity solution

| Who is authenticating | Use | Why |
|---|---|---|
| Workforce users reaching AWS accounts | **IAM Identity Center**, connected to your IdP | One sign-on, short-lived credentials, centrally managed permission sets |
| Workforce users, single account, legacy | SAML 2.0 federation directly to IAM roles | Works without Organizations |
| Customers of your application | **Amazon Cognito** user pools | Sign-up, sign-in, MFA, social and enterprise federation, JWTs |
| Application users who need AWS credentials | Cognito **identity pools** | Exchanges a token for temporary AWS credentials |
| Workloads on AWS | **IAM roles** (instance profile, task role, execution role, pod identity) | No stored credentials |
| Workloads outside AWS with X.509 certificates | **IAM Roles Anywhere** | Temporary credentials from a certificate issued by your CA |
| CI/CD systems and other clouds | OIDC federation with `AssumeRoleWithWebIdentity` | No stored AWS keys in the pipeline |
| Nothing else works | IAM user with access keys | Last resort. Rotate, scope tightly, monitor. |

The direction is always the same: **no long-term credentials**. If an answer creates an IAM user where a role or federation would work, it is probably wrong.

### IAM Identity Center

- Lives in the management account or a delegated administrator account. One organization instance per organization.
- **Identity source:** the built-in directory, Active Directory (through AWS Managed Microsoft AD or AD Connector), or an external IdP using SAML 2.0 for sign-in and SCIM for provisioning.
- **Permission sets** are templates. Assigning a permission set to a user or group in an account creates an IAM role there (named `AWSReservedSSO_...`) with the set's policies. Change the set and it re-provisions everywhere.
- Permission sets can include AWS managed policies, customer managed policies (which must already exist by name in each account), an inline policy, and a permissions boundary.
- **ABAC:** user attributes from the IdP become session tags, usable as `aws:PrincipalTag` in policies.
- **Trusted identity propagation** carries the user's identity through to data services so access is authorized per user, not per application role.

### Cognito

| | User pool | Identity pool |
|---|---|---|
| Purpose | Authenticate users; a user directory | Authorize users to call AWS |
| Output | JWTs: ID token, access token, refresh token | Temporary AWS credentials from STS |
| Federation | Social, SAML, OIDC providers | User pools, social, SAML, OIDC, developer-authenticated |
| Extras | MFA, hosted sign-in, Lambda triggers, threat protection (compromised credentials, adaptive authentication) | Authenticated and unauthenticated roles; rule-based role mapping; principal tags for ABAC |

API Gateway and ALB can validate user pool tokens directly. For fine-grained application permissions beyond what token scopes express, use Verified Permissions.

### MFA

- Supported types: passkeys and FIDO security keys (phishing-resistant), authenticator apps (TOTP), hardware TOTP tokens.
- AWS requires MFA for root users. Member account root credentials can be removed entirely with centralized root access management.
- Enforce in policy with `aws:MultiFactorAuthPresent` and `aws:MultiFactorAuthAge`. These keys exist only on temporary credentials obtained with MFA. Long-term access key requests do not carry them, so write the deny with `BoolIfExists`:

```json
{
  "Effect": "Deny",
  "NotAction": ["iam:CreateVirtualMFADevice", "iam:EnableMFADevice", "iam:ListMFADevices", "sts:GetSessionToken"],
  "Resource": "*",
  "Condition": { "BoolIfExists": { "aws:MultiFactorAuthPresent": "false" } }
}
```

- For federated users, MFA happens at the IdP. AWS does not see it unless the IdP passes it along.

### Temporary credentials

| STS API | Caller | Use | Notes |
|---|---|---|---|
| `AssumeRole` | IAM principal | Cross-account access, privilege separation | Can pass session policies, session tags, external ID, source identity |
| `AssumeRoleWithSAML` | Anyone holding a SAML assertion | Workforce federation | Unsigned call |
| `AssumeRoleWithWebIdentity` | Anyone holding an OIDC token | Pipelines, Kubernetes service accounts, mobile apps | Unsigned call. Trust policy conditions on the token's claims are essential. |
| `GetSessionToken` | IAM user or root | MFA-protected API access for a user | Same permissions as the user |
| `GetFederationToken` | IAM user | Custom identity broker | Legacy pattern |

Things to remember:

- Role session duration is 15 minutes up to the role's maximum (1 to 12 hours). **Role chaining** caps the session at one hour.
- **External ID** solves the cross-account confused deputy problem: a third party that assumes roles in many customers' accounts must present the ID unique to your relationship, checked with `sts:ExternalId` in your trust policy.
- **Source identity** is set once at the first assume and persists through role chaining. It appears in CloudTrail, so you can tie activity to a person.
- **Session tags** become principal tags for the session. Marked transitive, they persist through chaining.
- Temporary credentials cannot be revoked individually. Revoke by denying sessions issued before a timestamp. See [teaching/02](02-incident-response.md#containment-techniques).
- For AWS service principals calling into your resources, the confused deputy guard is `aws:SourceArn` and `aws:SourceAccount` in the resource or trust policy.

**S3 presigned URLs** let someone without AWS credentials perform one S3 operation. The URL carries the signer's authority:

- It works only while the signer still has permission and the signing credentials are valid. A URL signed with role credentials dies when that session expires, whatever expiry was requested.
- Maximum lifetime with SigV4 is seven days, and only with long-term credentials.
- Anyone holding the URL can use it. Limit the damage with short expiry and bucket policy conditions such as `aws:SourceIp`, `aws:SourceVpce`, or `s3:signatureAge`.

### Troubleshooting authentication

| Symptom | Look at |
|---|---|
| `AssumeRole` denied | Both sides: the caller's identity policy must allow `sts:AssumeRole` on the role, **and** the role's trust policy must name the caller. Then SCPs, external ID, MFA condition, and session duration above the role maximum. |
| SAML federation fails | Assertion attributes (`Role`, `RoleSessionName`), the provider ARN in the trust policy, metadata or certificate expiry at the IdP, clock skew |
| OIDC federation fails | The `aud` and `sub` conditions in the trust policy against the actual token claims; the provider's thumbprint or audience list |
| Identity Center user sees no accounts | No assignment for that user or group; SCIM not syncing group membership |
| Identity Center role lacks expected permissions | Permission set not re-provisioned after a change; referenced customer managed policy missing in that account; permissions boundary; SCP |
| Cognito token rejected | Wrong user pool or app client ID in the authorizer; expired token; using the ID token where the access token is expected |
| AD users cannot sign in | AD Connector reachability to domain controllers, service account credentials, DNS, trust relationship for AWS Managed Microsoft AD |
| Signature or expired token errors | Clock skew; using credentials in the wrong partition or a Region where the STS endpoint is not enabled |

CloudTrail records `AssumeRole*`, `ConsoleLogin`, and Identity Center events, including failures with an error code. Start there.

## Task 4.2: Authorization

### Policy types

| Policy | Attached to | Grants? | Purpose |
|---|---|---|---|
| Identity-based | User, group, role | Yes | What this principal may do |
| Resource-based | Resource (bucket, key, queue, role trust) | Yes | Who may act on this resource; enables cross-account without assuming a role |
| Permissions boundary | User or role | No | Maximum an identity policy can grant this principal |
| Session policy | A session, at assume time | No | Narrows one session |
| SCP | Organization root, OU, account | No | Maximum for principals in member accounts |
| RCP | Organization root, OU, account | No | Maximum for access to resources in member accounts |
| VPC endpoint policy | VPC endpoint | No | Limits what can be done through that endpoint |

### Cross-account access

Two ways for a principal in account A to reach a resource in account B:

1. **Assume a role in B.** B's role trust policy names A (or a principal in A). A's principal needs `sts:AssumeRole` on that role. The caller gives up its own permissions and acts as the role.
2. **Resource-based policy in B** names the principal in A. A's principal also needs an identity policy allowing the action. The caller keeps its own identity and permissions, which matters when one operation needs access to resources in both accounts, such as copying between buckets.

Within one account, a grant from either the identity policy or the resource policy is enough. Across accounts, **both** are required.

A trust policy that names `arn:aws:iam::111122223333:root` trusts the *account*, delegating the decision to that account's IAM policies. It does not mean the root user.

### Other authorization building blocks

- **Permissions boundaries** enable safe delegation. Let developers create roles, but require through a condition (`iam:PermissionsBoundary`) that every role they create carries a boundary. They cannot then create a role more powerful than the boundary allows.
- **IAM paths** (`/app/payments/`) put structure into ARNs so policies can use wildcards: allow `iam:PassRole` on `arn:aws:iam::*:role/app/payments/*`.
- **IAM Roles Anywhere:** register your CA as a trust anchor, create a profile listing the roles, and the role's trust policy names `rolesanywhere.amazonaws.com`, usually with conditions on certificate attributes.
- **Amazon Verified Permissions** externalizes application authorization. Policies are written in Cedar, stored in a policy store, and your application asks `IsAuthorized` for each action. It handles what your application's users can do in your application, not what they can do in AWS.
- **Service-linked roles** are predefined by a service, cannot be edited, and are not restricted by SCPs.

### ABAC and RBAC

**RBAC** on AWS: a role per job function, with policies listing specific resources. Simple to audit, but the number of roles and policy edits grows with every project.

**ABAC:** permissions depend on matching attributes, normally tags.

```json
{
  "Effect": "Allow",
  "Action": ["ec2:StartInstances", "ec2:StopInstances"],
  "Resource": "*",
  "Condition": {
    "StringEquals": { "aws:ResourceTag/project": "${aws:PrincipalTag/project}" }
  }
}
```

One policy serves every project. New projects need tags, not policy changes.

| Condition key | Refers to |
|---|---|
| `aws:PrincipalTag/key` | Tag on the calling principal or session |
| `aws:ResourceTag/key` | Tag on the resource being acted on |
| `aws:RequestTag/key` | Tag being applied in this request |
| `aws:TagKeys` | The set of tag keys in this request |

ABAC is only as strong as tag governance. You must also control who can set or change the tags that policies rely on: restrict tagging actions with `aws:RequestTag` and `aws:TagKeys`, and protect principal tags. Not every service or action supports resource-tag authorization; check the Service Authorization Reference.

### Least privilege in practice

1. Start from what the workload does. **Access Analyzer policy generation** builds a policy from CloudTrail activity.
2. Scope resources by ARN and add conditions.
3. Validate with Access Analyzer policy validation and custom policy checks in the pipeline.
4. Set outer limits with boundaries, SCPs, and RCPs.
5. Remove what goes unused, guided by last-accessed data and unused access findings.

Condition keys worth knowing cold:

| Key | Use |
|---|---|
| `aws:PrincipalOrgID` | Only principals from my organization (in resource policies) |
| `aws:ResourceOrgID` | Only resources in my organization (in identity policies, SCPs) |
| `aws:SourceVpce`, `aws:SourceVpc` | Request came through this endpoint or VPC |
| `aws:SourceIp` | Public source IP. Not present for requests through VPC endpoints. |
| `aws:SecureTransport` | Request used TLS |
| `aws:RequestedRegion` | Region of the request |
| `aws:PrincipalArn` | ARN of the caller's role or user |
| `aws:PrincipalIsAWSService` | Call made directly by an AWS service principal |
| `aws:ViaAWSService`, `aws:CalledVia` | Call made by a service on the principal's behalf |
| `aws:SourceArn`, `aws:SourceAccount` | The resource a service is acting for. Confused deputy protection. |

A **data perimeter** combines these: trusted identities (`aws:PrincipalOrgID`), trusted resources (`aws:ResourceOrgID`), and expected networks (`aws:SourceVpce`, `aws:SourceIp`), enforced with RCPs, SCPs, and endpoint policies.

### Access Analyzer

| Capability | What it does |
|---|---|
| **External access findings** | Finds resources whose policies grant access outside your zone of trust (account or organization). Uses automated reasoning over policies, not logs. |
| **Internal access findings** | Shows which principals inside the organization can reach specified critical resources |
| **Unused access findings** | Unused roles, access keys, passwords, and granted-but-unused services and actions |
| **Policy validation** | Checks grammar, security warnings, and suggestions against best practices |
| **Custom policy checks** | `CheckNoNewAccess`, `CheckAccessNotGranted`, `CheckNoPublicAccess`: pass or fail answers for CI/CD |
| **Policy generation** | Drafts a least-privilege policy from CloudTrail history |

An organization-level analyzer is created from the management account or delegated administrator. External access analyzers are Regional; create one per Region.

### Troubleshooting authorization

1. **Read the error.** Access denied messages state the policy type responsible where possible ("with an explicit deny in a service control policy", "because no identity-based policy allows"). Encoded messages decode with `aws sts decode-authorization-message`.
2. **Find the event in CloudTrail** for the exact principal ARN, action, resource, and error.
3. **Walk the evaluation order:** explicit deny anywhere, then SCP, RCP, resource policy, identity policy, boundary, session policy.
4. **Check the context.** Conditions fail silently: wrong Region, no MFA, request not through the expected endpoint, missing tag, `aws:SourceIp` used for a request arriving through a VPC endpoint.
5. **Check the other half.** For KMS-encrypted data, the caller needs the KMS permission as well as the data permission. For cross-account, both accounts' policies.
6. **Simulate.** The IAM Policy Simulator evaluates identity policies, boundaries, and optionally a resource policy against chosen actions. It does not make real requests, and it does not reproduce every condition or organization policy nuance.

## Worked examples

**1. A role has `AdministratorAccess` and a permissions boundary allowing only `s3:*`. It calls `ec2:DescribeInstances`.**
Denied. The effective permission is the intersection of the identity policy and the boundary.

**2. A user in account A is allowed `s3:GetObject` on a bucket in account B by their identity policy. The bucket has no bucket policy. The object is owned by the bucket owner.**
Denied. Cross-account access needs the resource policy in B to allow it as well.

**3. A GitHub Actions workflow assumes a role with OIDC. The trust policy checks only `aud`.**
Any repository on GitHub can assume the role. The trust policy must also condition on the `sub` claim to pin the organization, repository, and ideally the branch or environment.

**4. A team lead must be able to create roles for their Lambda functions without being able to escalate privileges.**
Grant `iam:CreateRole` and `iam:AttachRolePolicy` with a condition requiring `iam:PermissionsBoundary` to equal the team boundary policy ARN. Deny changing or deleting the boundary policy and deny removing the boundary. Scope `iam:PassRole` to the team's path.

## Pitfalls and exam traps

- An SCP never grants. An account under a full-access SCP still needs identity policies.
- SCPs do not apply to the management account, or to service-linked roles.
- A boundary limits identity-based policies. A resource-based policy that names the **role session or IAM user ARN directly** can grant access the boundary does not include. One that names the role ARN is still subject to the boundary.
- `NotPrincipal` with `Deny` is fragile. Prefer `Deny` with a condition on `aws:PrincipalArn`.
- `"Principal": "*"` with a condition is not automatically public, but Access Analyzer and Block Public Access judge it by whether the condition restricts to fixed, trusted values.
- IAM is eventually consistent. A change may take seconds to apply everywhere.
- Group membership cannot be a principal in a resource policy. Groups are not principals.
- `iam:PassRole` is not an API call and never appears in CloudTrail as an event.
- Deleting and recreating a role with the same name breaks trust and resource policies that referenced it, because they stored the role's unique ID.
- `aws:SourceIp` is absent when the request arrives through a VPC endpoint; use `aws:SourceVpce` or `aws:VpcSourceIp`.

## Self-check

1. A principal has an identity policy allowing an action and an SCP on its account that does not mention the action (the SCP is an allow list of other services). Result?
2. What two policies must both allow for `sts:AssumeRole` to succeed across accounts?
3. Why use `BoolIfExists` instead of `Bool` when denying requests without MFA?
4. What is the maximum session duration when a role assumes another role?
5. A SaaS vendor asks you to create a role they will assume. What do you add to the trust policy, and why?
6. Which Access Analyzer feature would you put in a pipeline to fail a build if a policy change grants any new access?
7. What does a permission set become in a member account?
8. A presigned URL was generated with a seven-day expiry by code running on EC2. It stops working after a few hours. Why?

<details>
<summary>Answers</summary>

1. Denied. With allow-list SCPs, anything not allowed by the SCP is implicitly denied.
2. The caller's identity-based policy (allowing `sts:AssumeRole` on the role) and the role's trust policy (naming the caller or their account).
3. `aws:MultiFactorAuthPresent` is missing from requests made with long-term access keys. `Bool` would not match a missing key, so those requests would escape the deny.
4. One hour.
5. A condition on `sts:ExternalId` with a value unique to your relationship, to prevent the confused deputy problem where another of the vendor's customers tricks the vendor into acting on your account.
6. The `CheckNoNewAccess` custom policy check.
7. An IAM role (prefixed `AWSReservedSSO_`) with the permission set's policies attached.
8. It was signed with the instance role's temporary credentials. The URL is valid only while those credentials are.

</details>

## Further reading

- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [AWS global condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/)
- [Data perimeters on AWS](https://aws.amazon.com/identity/data-perimeters-on-aws/)
