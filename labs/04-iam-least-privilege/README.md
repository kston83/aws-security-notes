# Lab 04: IAM least privilege

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 4a, 4b, 4f · **SCS-C03:** 4.2.1, 4.2.2, 4.2.3 · **Time:** 60 minutes · **Related:** [Terraform configuration](../../teaching/terraform/04-configuration.md), [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md), [Identity and access management](../../teaching/04-identity-and-access-management.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [AWS provider security](../../cheatsheets/terraform-aws-provider-security.md), [IAM policy evaluation](../../cheatsheets/iam-policy-evaluation.md)

## Goal

Build an application IAM role with a trust policy, a customer managed permissions policy scoped to one S3 prefix and one KMS key, and a permissions boundary, all written with `data "aws_iam_policy_document"`. Afterward you can say how a `data` block differs from a `resource` block, read the dependency graph Terraform derives from attribute references, and know when `depends_on` is needed because no reference exists.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Do [Lab 01](../01-first-apply/README.md) first.
- Read [Terraform configuration](../../teaching/terraform/04-configuration.md) (objectives 4a, 4b, 4f) and skim the [IAM policy evaluation cheatsheet](../../cheatsheets/iam-policy-evaluation.md).

| File | Holds |
|---|---|
| `main.tf` | Three `data` sources, `locals`, and the bucket, KMS key, and alias the role will use |
| `iam.tf` | Three policy documents (`trust`, `app`, `boundary`), two `aws_iam_policy` resources, the role, the attachment, the instance profile |
| `outputs.tf` | ARNs for the role, both policies, the bucket, the key |

## Steps

### 1. Tell `data` from `resource`

`main.tf` opens with data sources:

```hcl
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
```

A **data source** reads something that already exists (or computes something) and never creates, changes, or deletes anything. A **resource** is managed: Terraform creates it, tracks it in state, and destroys it. Address them differently: `data.aws_caller_identity.current.account_id` versus `aws_s3_bucket.data.arn`.

`data "aws_iam_policy_document"` is a pure computation. It calls no AWS API. It turns HCL statements into a JSON string in its `json` attribute, which is why it can be used to build policies without hand-writing JSON. The locals use the lookups to build an ARN for SSM parameters this configuration does not manage:

```hcl
parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/lab04/*"
```

No account ID or partition is typed in. The same code produces `arn:aws-us-gov:` in GovCloud.

### 2. Initialize, validate, check formatting

```bash
terraform init          # [changes state] writes .terraform/ and .terraform.lock.hcl
terraform validate
terraform fmt -check
```

```
...
- Installed hashicorp/aws v6.72.0 (signed by HashiCorp)
...
Terraform has been successfully initialized!
...
Success! The configuration is valid.
```

`fmt -check` prints nothing and exits 0.

### 3. Read the permissions policy

In `iam.tf`, the `app` document grants four things and nothing else:

| Statement | Allows | Scoped to |
|---|---|---|
| `ReadWriteAppPrefix` | `s3:GetObject`, `s3:PutObject` | objects under `app/` in one bucket |
| `ListAppPrefix` | `s3:ListBucket` | that bucket, only when `s3:prefix` matches `app/*` |
| `UseDataKey` | `kms:Decrypt`, `kms:GenerateDataKey` | one KMS key ARN |
| `ReadOwnProjectParameters` | `ssm:GetParameter`, `ssm:GetParametersByPath` | `/lab04/*` parameters whose `project` tag equals the caller's own `project` tag |

The last statement is **attribute-based access control** (ABAC). `&{aws:PrincipalTag/project}` is how this data source writes the IAM policy variable `${aws:PrincipalTag/project}`; a literal `${...}` would be read by Terraform as its own interpolation.

Two things make the policy least privilege: no action uses a wildcard, and every resource is a specific ARN or prefix. See [Identity and access management](../../teaching/04-identity-and-access-management.md) for why a prefix plus a `Condition` on `ListBucket` is needed (list permission applies to the bucket, not the objects).

### 4. Read the trust policy and the boundary

The `trust` document is the role's **trust policy**: it says who may assume the role. Here only `ec2.amazonaws.com`, and only for instances in this account (`aws:SourceAccount`), which narrows the confused-deputy risk.

The `boundary` document is a **permissions boundary**: a ceiling on what the role can ever be granted. The effective permissions are the intersection of the identity policy and the boundary. This boundary allows S3, three KMS actions, and SSM reads, and explicitly denies `iam:*` and key-admin actions. It grants nothing by itself, so a role with only a boundary can do nothing.

### 5. See how references create order

Four resources in `iam.tf` depend on each other through arguments:

```hcl
resource "aws_iam_role" "app" {
  name                 = "${local.name}-role"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}
```

Each reference is an **implicit dependency**. Terraform will not evaluate `aws_iam_role.app` until the boundary policy exists, because its ARN is not known until then. The `app` policy document references `aws_s3_bucket.data.arn` and `aws_kms_key.data.arn`, so the bucket and key are created before the policy. You never wrote an order.

### 6. Add an explicit dependency

The instance profile references only the role:

```hcl
resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-profile"
  role = aws_iam_role.app.name

  depends_on = [aws_iam_role_policy_attachment.app]
}
```

Nothing in its arguments mentions the attachment, so without `depends_on` Terraform could create the profile first. Software that boots with the profile would then run briefly with no permissions. `depends_on` is the explicit form: use it only when a dependency exists that no attribute reference expresses, because it also makes Terraform defer reading any data source that depends on the target.

### 7. Look at the graph

```bash
terraform graph
```

The output is DOT, a graph description language, not a picture. Each edge points from a node to what it depends on. Some of the edges:

```
...
  "data.aws_iam_policy_document.app" -> "aws_kms_key.data";
  "data.aws_iam_policy_document.app" -> "aws_s3_bucket.data";
...
  "aws_iam_instance_profile.app" -> "aws_iam_role_policy_attachment.app";
  "aws_iam_policy.app" -> "data.aws_iam_policy_document.app";
...
  "aws_iam_role.app" -> "aws_iam_policy.boundary";
  "aws_iam_role_policy_attachment.app" -> "aws_iam_policy.app";
  "aws_iam_role_policy_attachment.app" -> "aws_iam_role.app";
...
```

To draw it, pipe it into Graphviz if installed: `terraform graph | dot -Tsvg > graph.svg`. Find the profile's edge to the attachment: that edge is the `depends_on`. The profile's reference to the role has no edge of its own, because the graph omits edges already implied by a longer path (profile to attachment to role).

### 8. Apply

```bash
terraform apply         # [changes state] answer yes
```

```
...
aws_kms_key.data: Creation complete after 4s [id=143ec6cf-d32e-4ac9-ab0d-36f0fb18f841]
data.aws_iam_policy_document.app: Reading...
aws_kms_alias.data: Creating...
data.aws_iam_policy_document.app: Read complete after 0s [id=800738519]
aws_kms_alias.data: Creation complete after 0s [id=alias/lab04-app-data]
aws_iam_policy.app: Creating...
aws_iam_policy.app: Creation complete after 0s [id=arn:aws:iam::000000000000:policy/lab04-app-access]
aws_iam_role_policy_attachment.app: Creating...
aws_iam_role_policy_attachment.app: Creation complete after 0s [id=lab04-app-role/arn:aws:iam::000000000000:policy/lab04-app-access]
aws_iam_instance_profile.app: Creating...
aws_iam_instance_profile.app: Creation complete after 5s [id=lab04-app-profile]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

account_id = "000000000000"
boundary_arn = "arn:aws:iam::000000000000:policy/lab04-app-boundary"
bucket_arn = "arn:aws:s3:::lab04-app-data"
key_arn = "arn:aws:kms:us-east-1:000000000000:key/143ec6cf-d32e-4ac9-ab0d-36f0fb18f841"
policy_arn = "arn:aws:iam::000000000000:policy/lab04-app-access"
role_arn = "arn:aws:iam::000000000000:role/lab04-app-role"
```

The key ID differs on every run. The eight resources are the bucket, key, alias, two policies, role, attachment, and profile. The three policy documents and three lookups are data sources and are not counted. The log follows the graph: the `app` policy document is read only after the key exists (its inputs were unknown at plan time, so Terraform deferred the read to apply), the policy comes after the document, and the instance profile is created last.

## Verify

```bash
aws iam get-role --role-name lab04-app-role \
  --query 'Role.[RoleName,PermissionsBoundary.PermissionsBoundaryArn,AssumeRolePolicyDocument.Statement[0].Principal.Service]' --output text
```

```
lab04-app-role	arn:aws:iam::000000000000:policy/lab04-app-boundary	ec2.amazonaws.com
```

```bash
aws iam list-attached-role-policies --role-name lab04-app-role --output text
```

```
ATTACHEDPOLICIES	arn:aws:iam::000000000000:policy/lab04-app-access	lab04-app-access
```

```bash
aws iam get-policy-version --policy-arn arn:aws:iam::000000000000:policy/lab04-app-access \
  --version-id v1 --query 'PolicyVersion.Document.Statement[].[Sid,Resource]' --output json
```

```
[
    [
        "ReadWriteAppPrefix",
        "arn:aws:s3:::lab04-app-data/app/*"
    ],
...
    [
        "ReadOwnProjectParameters",
        "arn:aws:ssm:us-east-1:000000000000:parameter/lab04/*"
    ]
]
```

The two elided statements are `ListAppPrefix` on the bucket ARN and `UseDataKey` on the key ARN. The account ID and Region in the SSM ARN came from data sources.

Ask IAM's policy simulator what the role may do: one action the policy allows, one it does not.

```bash
ROLE=arn:aws:iam::000000000000:role/lab04-app-role
aws iam simulate-principal-policy --policy-source-arn $ROLE --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::lab04-app-data/app/report.csv \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
aws iam simulate-principal-policy --policy-source-arn $ROLE --action-names s3:DeleteObject \
  --resource-arns arn:aws:s3:::lab04-app-data/other/x \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
```

```
s3:GetObject	allowed
s3:DeleteObject	implicitDeny
```

`implicitDeny` means no statement allows the action, which is the default. An explicit `Deny` would show `explicitDeny`. See [IAM policy evaluation](../../cheatsheets/iam-policy-evaluation.md).

## Break it

**1. Create a dependency cycle.** In `iam.tf`, make the trust document refer to the role it belongs to: in its `condition`, replace `values = [data.aws_caller_identity.current.account_id]` with `values = [aws_iam_role.app.arn]` (a block takes one `values` argument, so replace it rather than add a second). Run `terraform validate`:

```
Error: Cycle:
  aws_iam_role.app
  data.aws_iam_policy_document.trust
```

The role needs the trust document, and the trust document now needs the role. It fails before any API call. Break a cycle by removing one reference, or by using a name you build in `locals` instead of the attribute. Revert the edit.

**2. Reference an attribute that does not exist.** Change `aws_iam_role.app.name` in the attachment to `aws_iam_role.app.nme`. Run `terraform validate`:

```
Error: Unsupported attribute

  on iam.tf line 107, in resource "aws_iam_role_policy_attachment" "app":
 107:   role       = aws_iam_role.app.nme

This object has no argument, nested block, or exported attribute named "nme".
Did you mean "name"?
```

Validation checks references against the provider schema without calling AWS. Revert.

**3. Widen the policy.** In the `ReadWriteAppPrefix` statement, set `actions = ["s3:*"]` and `resources = ["*"]`, then run `terraform plan`. Only `aws_iam_policy.app` changes:

```
  # aws_iam_policy.app will be updated in-place
...
                      ~ Action   = [
                          - "s3:PutObject",
                          - "s3:GetObject",
                        ] -> "s3:*"
                      ~ Resource = "arn:aws:s3:::lab04-app-data/app/*" -> "*"
...
Plan: 0 to add, 1 to change, 0 to destroy.
```

Plan does not judge the policy. Run `terraform apply` **[changes state]**, and Terraform applies it happily. Re-run the simulator command for `s3:DeleteObject` on `other/x`; it now prints `s3:DeleteObject	allowed`. This is why policies need review or an automated check such as IAM Access Analyzer policy validation in the pipeline. The boundary still allows `s3:*`, so it does not stop this one. Each update stores a new default policy version (`v2` here), so the Verify command's `--version-id v1` still shows the original document. Revert and apply again.

**4. Remove `depends_on`.** Delete the `depends_on` line from the instance profile and run `terraform graph | grep '"aws_iam_instance_profile.app" ->'`. The edge to the attachment is gone; only the edge to the role is left:

```
  "aws_iam_instance_profile.app" -> "aws_iam_role.app";
```

`terraform plan` prints `No changes. Your infrastructure matches the configuration.`, which is the danger: `depends_on` changes only ordering, so nothing fails, and the guarantee is simply gone the next time the profile is created. Restore the line.

**5. Hit the boundary.** First simulate `iam:PassRole` with the policy as it is:

```bash
aws iam simulate-principal-policy --policy-source-arn $ROLE --action-names iam:PassRole \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output text
```

```
iam:PassRole	explicitDeny
```

Then add `"iam:PassRole"` to the `app` policy's `UseDataKey` actions, apply **[changes state]**, and simulate again. The answer is still `iam:PassRole	explicitDeny`: the boundary's `Deny` on `iam:*` wins over the new `Allow`, so adding the action to the identity policy gained nothing. That matches AWS policy evaluation logic, in which an explicit deny anywhere overrides any allow, but the emulator does not enforce it on real calls (see "What differs on real AWS"). Revert and apply again.

## Clean up

```bash
KEY_ID=$(terraform output -raw key_arn | cut -d/ -f2)    # save it before the output is gone
terraform destroy       # [changes state] answer yes
aws iam list-roles --query 'Roles[?starts_with(RoleName, `lab04`)].RoleName' --output text
aws kms describe-key --key-id $KEY_ID --query 'KeyMetadata.[KeyState,DeletionDate]' --output text
```

`destroy` ends with `Destroy complete! Resources: 8 destroyed.`, `list-roles` prints nothing, and the key is not gone:

```
PendingDeletion	2026-11-18T13:32:53-06:00
```

A KMS key goes into pending deletion for `deletion_window_in_days` (7 here) rather than disappearing immediately.

## What differs on real AWS

- **Policy enforcement.** floci does not enforce IAM on API calls by default, so neither the trust policy, the permissions policy, nor the boundary blocks anything. In this lab's test run, `aws sts assume-role` on `lab04-app-role` with the `test` credentials succeeded even though the trust policy names only EC2, and that session then wrote `s3://lab04-app-data/other/x` and called `iam:ListRoles`, both of which AWS would deny. `simulate-principal-policy` is the only place the policies are evaluated in this lab. On AWS, also test with a real assumed-role session. floci has an opt-in `FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true` setting **(verify)**; with it, the same `assume-role` call failed with `AccessDenied`. The lab was not otherwise run in that mode.
- **Simulator coverage.** The emulator's simulator applied the boundary's `Deny` (Break it 5) and the `s3:prefix` condition on `ListBucket` (`allowed` with `--context-entries` for `app/x`, `implicitDeny` for `other/`). Do not assume it models every feature of the real one, such as service control policies, session policies, and resource policies.
- **Trust.** Real EC2 instances assume this role through the instance profile. Nothing in the lab launches an instance.
- **Bucket and key.** S3 bucket names are global, so `lab04-app-data` would collide; add an account ID or random suffix. A real key needs an explicit key policy that names the role, which is [Lab 05](../05-kms-and-secrets/README.md).
- **IAM propagation.** A new role or policy can take seconds to be usable on AWS; the profile's `depends_on` does not cover that delay.
- **Least privilege proof.** On AWS, run IAM Access Analyzer policy validation and generate a policy from CloudTrail activity before trusting a hand-written policy. See the [KMS cheatsheet](../../cheatsheets/kms.md) for key-policy pairing and [Securing Terraform on AWS](../../teaching/terraform/09-securing-terraform-on-aws.md).
- **Provider settings.** Remove the fake keys, `skip_*` flags, `s3_use_path_style`, and `endpoints` from `providers.tf`, as [labs/README.md](../README.md#the-lab-provider-block) describes.
