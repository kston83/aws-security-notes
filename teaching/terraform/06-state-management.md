# Terraform 6: State Management

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 6a–6d · **SCS-C03:** 6.2.1 · **Related:** [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [state exposure runbook](../../runbooks/terraform-state-exposure.md), [lock and corruption runbook](../../runbooks/terraform-state-lock-and-corruption.md), [drift runbook](../../runbooks/terraform-unexpected-drift.md), [lab 02](../../labs/02-remote-state/README.md), [IaC mappings](../../control-mappings/services/iac-terraform.md)

## Why this matters

State is the only record of which real resources Terraform owns. Lose it and Terraform no longer knows what it built. Corrupt it and the next apply may destroy or duplicate things. Leak it and you have leaked every secret that passed through a resource attribute, because state stores them in plaintext. For a security team the state file is a crown-jewel data store, and where it lives, who can read it, and who can write it are access-control decisions, not tooling details.

## Mental model

**State maps configuration addresses to real objects.** `aws_s3_bucket.logs` in your code is bound to one bucket in one account by an entry in state. Every plan compares three things.

```
   Configuration (.tf)          State (terraform.tfstate)        Real infrastructure
   what you want                what Terraform last saw          what exists now
          │                              │                              │
          │                              │◄───────── refresh ───────────┤   read each object through the provider
          └────────── diff ──────────────┤
                                         ▼
                                       plan       actions that make reality match configuration

   Backend: where state is stored and how it is locked.   local (default) · s3 · HCP Terraform · others
   Lock:    one writer at a time. Taken before any operation that could write state, released after.
```

Three terms carry the whole domain:

- A **backend** defines where Terraform stores state and whether it can lock it. It is configured in the `terraform` block, and there is one per configuration.
- A **lock** is a marker that says "someone is writing this state." It prevents two runs from writing at once.
- **Drift** is a difference between what state records and what really exists, caused by a change made outside Terraform.

What state contains, and why it matters to a defender:

| In state | Consequence |
|---|---|
| Every attribute of every managed resource, including ones marked `sensitive` | Database passwords, generated private keys, and access keys are readable by anyone who can read state. `sensitive` hides values in CLI output, not in state. |
| Resource IDs, ARNs, account IDs, network layout | A reconnaissance map of the environment |
| Output values, including sensitive ones | Same exposure |
| Dependency metadata and a `serial` counter and `lineage` ID | Terraform uses these to refuse stale or unrelated state |

Ephemeral resources and write-only arguments keep some values out of state entirely. See [securing Terraform on AWS](09-securing-terraform-on-aws.md) and [configuration](04-configuration.md).

## Objective 6a: The local backend

With no `backend` block, Terraform uses the **local backend**: state is a JSON file on the disk of whoever ran the command.

| File | Purpose |
|---|---|
| `terraform.tfstate` | Current state, in the working directory |
| `terraform.tfstate.backup` | The previous state, written before each change |
| `terraform.tfstate.d/WORKSPACE/terraform.tfstate` | State for each non-default CLI workspace |
| `.terraform/terraform.tfstate` | Not your state. It records the backend configuration for this working directory. |
| `.terraform.tfstate.lock.info` | Lock marker that exists only while an operation is running |

```hcl
terraform {
  backend "local" {
    path = "state/terraform.tfstate"
  }
}
```

The block above is optional. It only matters when you want a path other than the default.

The local backend is fine for learning and for throwaway experiments. It fails for teams on every count:

- **No sharing.** A colleague with a different copy of the file will plan to recreate everything.
- **Locking is local only.** It stops two processes on the same machine, not two people on two laptops.
- **No access control, audit trail, or versioning** beyond what the laptop's disk provides.
- **Easy to leak.** State committed to Git is one of the most common ways secrets escape. Put `*.tfstate`, `*.tfstate.*`, and `.terraform/` in `.gitignore`.

## Objective 6b: State locking

If the backend supports it, Terraform locks state automatically for every operation that could write state (`plan`, `apply`, `destroy`, `import`, `state mv`, and so on). You do not configure anything in the workflow. If the lock cannot be acquired, Terraform stops.

Without a lock, two applies can each read the same state, each make changes, and each write back. The second write silently discards the first run's record. The resources from the first run still exist but are now unmanaged.

| Flag or command | Effect |
|---|---|
| `-lock-timeout=DURATION` | Keep retrying for the lock for this long, for example `-lock-timeout=5m`. The default is `0s`: fail immediately. Useful in pipelines. |
| `-lock=false` | Skip locking. Dangerous if anyone else might run against the same state. Not recommended. |
| `terraform force-unlock LOCK_ID` | Remove a lock that was left behind. It does not touch infrastructure or state contents. |

**Stale locks** happen when a run dies before releasing: a killed CI job, a dropped network connection, a crashed laptop. The failed lock attempt prints the lock ID, who holds it, and when it was taken.

`force-unlock` is the dangerous command in this domain. It requires the lock ID so that you cannot remove a lock blindly, but nothing checks that the holder is really dead. Removing a live lock creates exactly the two-writer problem locking exists to prevent. Use it only on your own lock, after confirming the process that took it has ended. In a pipeline, the permission to force-unlock (deleting the lock object) should be rarer than the permission to apply. Procedure: [lock and corruption runbook](../../runbooks/terraform-state-lock-and-corruption.md).

Not every backend supports locking. Check the backend's documentation. The S3 backend supports it only if you turn it on (next section). HCP Terraform locks the workspace for the length of each run.

## Objective 6c: Remote state with the backend block

A **remote backend** stores state in a shared service. The team gets one copy, with locking, encryption, versioning, and access control supplied by the service.

### The backend block

```hcl
terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "STATE_BUCKET_NAME"
    key          = "network/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-1:111122223333:key/KMS_KEY_ID"
    use_lockfile = true
  }
}
```

Rules that apply to every backend:

- One `backend` block per configuration, inside the `terraform` block, in the root module only.
- A backend block **cannot refer to named values**: no variables, locals, or data sources. Values are literal or supplied at `init` time.
- Changing anything in the block requires `terraform init` again.
- The backend does not create its own storage. The bucket and key must exist before the first `init`, created by a separate bootstrap configuration or by hand.
- `backend` and `cloud` blocks are mutually exclusive. See [HCP Terraform](08-hcp-terraform.md).

### The S3 backend

| Argument | Purpose |
|---|---|
| `bucket`, `key`, `region` | Where the state object lives |
| `encrypt` | Server-side encryption of the state and lock files |
| `kms_key_id` | Use this KMS key (SSE-KMS). The caller needs `kms:Encrypt`, `kms:Decrypt`, and `kms:GenerateDataKey` on it. |
| `use_lockfile` | Turn on S3-native locking. Optional, default `false` **(verify)** |
| `dynamodb_table` | Locking through a DynamoDB table. **Deprecated.** |
| `workspace_key_prefix` | Prefix for non-default workspaces, default `env:` **(verify)**. Their state lives at `env:/WORKSPACE/KEY`. |
| `assume_role` | An object with `role_arn` and optional settings, so the backend can use a different role or account than the provider |

**S3-native locking.** With `use_lockfile = true`, Terraform writes a lock object named `KEY.tflock` next to the state object, using an S3 conditional write so that only one writer can create it, and deletes it when the run ends. No second service is involved. It arrived in Terraform 1.10 and was declared generally available in 1.11, the release that also deprecated the DynamoDB arguments, so it is in scope for the 1.12 exam.

**Status of DynamoDB locking.** Before 1.10, locking needed a DynamoDB table with a partition key named `LockID` (type String), named in `dynamodb_table`. Since 1.11 the documentation marks that argument deprecated and says DynamoDB-based locking will be removed in a future minor version, with no version named yet **(verify)**. Until then it still works. Both arguments can be set together during migration, and Terraform then takes both locks. New configurations should use `use_lockfile` only. Expect older material, and older exam questions, to assume DynamoDB.

Locking is opt-in on S3. A backend block with neither argument has **no locking at all**.

Minimum IAM permissions, which make a good least-privilege exercise:

| Resource | Actions |
|---|---|
| The bucket | `s3:ListBucket` |
| The state object | `s3:GetObject`, `s3:PutObject` |
| The `.tflock` object | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` |
| The KMS key, if used | `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` |

Terraform never deletes the state object in the default workspace, so `s3:DeleteObject` on it is not needed. Withholding it stops a compromised pipeline role from deleting state outright.

### Securing the state bucket

| Control | Why |
|---|---|
| **Versioning** on | Recover from a corrupted or overwritten state by restoring a prior version. HashiCorp calls this highly recommended. |
| **SSE-KMS** with a customer managed key | Reading state then needs both S3 and KMS permission, and key use is logged in CloudTrail |
| **Block Public Access**, all four settings | State must never be public |
| **Bucket policy** that denies requests without TLS and limits principals to the pipeline role and a break-glass role | State readers can read every secret in it. State writers can change what Terraform believes it manages. |
| **CloudTrail data events** or server access logging on the bucket | Evidence of who read or wrote state. Needed in any exposure investigation. |
| One key (or bucket) per environment, with separate roles | A dev pipeline should not be able to read prod state |
| Dedicated account for state, where the organization is large enough | Keeps state out of reach of workload-account administrators |

Bucket hardening details are in the [S3 security cheatsheet](../../cheatsheets/s3-security.md), the Terraform for it is in [lab 02](../../labs/02-remote-state/README.md), and the control view is in the [IaC mappings](../../control-mappings/services/iac-terraform.md). If state has been exposed, treat every secret in it as compromised: [state exposure runbook](../../runbooks/terraform-state-exposure.md).

### Partial configuration

A **partial configuration** leaves some backend arguments out of the block and supplies them at `init`. It keeps environment-specific or sensitive values out of the code, and lets one configuration target several backends.

```hcl
terraform {
  backend "s3" {}
}
```

| Way to supply the rest | Example |
|---|---|
| A file | `terraform init -backend-config=prod.s3.tfbackend` |
| Key and value pairs | `terraform init -backend-config="bucket=STATE_BUCKET_NAME" -backend-config="key=network/prod/terraform.tfstate"` |
| Interactive prompt | Terraform asks for required arguments that are still missing |

The merged backend configuration is written in plaintext to `.terraform/terraform.tfstate` and into saved plan files. So do not pass credentials through `-backend-config`; give the backend credentials through environment variables or a role. Command-line pairs also end up in shell history.

### Changing backends

When the backend block changes, `terraform init` refuses to continue until you choose one of two flags.

| Command | Does | Use when |
|---|---|---|
| `terraform init -migrate-state` | Copies existing state to the new backend, after a prompt | Moving state: local to S3, or one bucket to another |
| `terraform init -reconfigure` | Ignores the previously configured backend and does **not** migrate state | The old backend is gone or irrelevant and you want to start against the new one as it is |
| `terraform init -migrate-state -force-copy` | Migrates and answers yes to the prompts | Automation |

Removing the `backend` block and running `terraform init -migrate-state` moves state back to the local backend. After any migration, check the old location: the old copy is not deleted, and a stale copy of state is a stale copy of your secrets.

## Objective 6d: Drift and state management

### Finding and accepting drift

By default `terraform plan` and `terraform apply` refresh first: they read every managed object and compare. If someone changed a resource in the console, the plan proposes to change it back to match the configuration.

| Command | What it does |
|---|---|
| `terraform plan` | Refresh, then propose changes that make reality match configuration. Drift shows up as an update or replacement you did not expect. |
| `terraform plan -refresh-only` | Show only what changed outside Terraform. Proposes no infrastructure changes. Safe to run at any time. |
| `terraform apply -refresh-only` | Update state to match reality, after showing the differences and asking for approval. Changes no infrastructure. |
| `terraform plan -refresh=false` | Skip the refresh. Faster, but the plan may be wrong. |
| `terraform refresh` | Deprecated. Behaves like `terraform apply -refresh-only -auto-approve`, so it writes state with no review. |

Refresh-only updates **state**. It does not update your **configuration**. If the out-of-band change should stay, edit the `.tf` files to match, or the next normal plan will propose reverting it.

Two ways to resolve drift:

- **Revert it.** Run a normal `apply`. Terraform puts the resource back to what the code says.
- **Adopt it.** Change the code to match, and confirm the plan is empty.

Drift is also a security signal. A security group rule, IAM policy attachment, or bucket policy that Terraform did not create means someone with credentials changed it by hand. That may be an engineer fixing an outage or an attacker opening a door. Do not apply over it before you know which: the apply destroys the evidence of what was changed. Find the CloudTrail event first. Procedure: [drift runbook](../../runbooks/terraform-unexpected-drift.md). Hands-on: [lab 06](../../labs/06-drift-and-import/README.md).

### Forcing replacement

```bash
terraform apply -replace="aws_instance.web"   # changes infrastructure: destroys and recreates this one instance
```

`-replace=ADDRESS` plans a destroy and recreate of one resource instance even though its configuration has not changed. Use it for a resource that is degraded or suspected compromised. It replaces `terraform taint`, which is deprecated: `taint` changed state immediately with no plan to review.

### Refactoring without destroying

Renaming a resource in code changes its address. Without help, Terraform sees one resource deleted and one created. Declarative blocks tell it otherwise, and because they are code, they go through review and show in the plan.

```hcl
# Rename: the object in state at the old address is re-bound to the new one. Nothing is destroyed.
moved {
  from = aws_s3_bucket.logs
  to   = aws_s3_bucket.audit_logs
}

# Stop managing a resource but leave it running. Delete the resource block and add this.
removed {
  from = aws_s3_bucket.legacy

  lifecycle {
    destroy = false
  }
}
```

| Block | Effect | Notes |
|---|---|---|
| `moved` | Changes an address in state | Works for renames, moves into or out of modules, and moves to `count` or `for_each` instances. Available since Terraform 1.1. |
| `removed` | Removes a resource from state | `destroy = false` forgets it and leaves it running. `destroy = true` also destroys it. Do not include an instance key in `from`. Available since Terraform 1.7. |
| `import` | Adds an existing object to state | Covered in [maintaining infrastructure](07-maintaining-infrastructure.md) |

### State subcommands that change state

The imperative equivalents act immediately, with no plan and no review. Prefer the blocks above. When you must use these, take a backup first with `terraform state pull > backup.tfstate`.

| Command | Changes state? | Does |
|---|---|---|
| `terraform state list` | No | Lists resource addresses |
| `terraform state show ADDRESS` | No | Shows one resource's attributes |
| `terraform state pull` | No | Prints raw state to stdout, secrets included |
| `terraform state mv SOURCE DESTINATION` | **Yes** | Changes an address. The `moved` block is the reviewed alternative. |
| `terraform state rm ADDRESS` | **Yes** | Forgets a resource without destroying it. The `removed` block is the reviewed alternative. |
| `terraform state replace-provider FROM TO` | **Yes** | Rewrites which provider owns resources |
| `terraform state push FILE` | **Yes** | Overwrites remote state with a local file. Last resort for recovery. |
| `terraform force-unlock LOCK_ID` | Lock only | Removes a stale lock |

Subcommands that modify state write a backup file, and that cannot be turned off. They work the same against remote state as local state. None of them touches real infrastructure: `state rm` leaves the resource running and unmanaged, which is how orphaned, untracked resources are born.

Never edit a state file by hand. If you must repair one, pull it, fix it, increase `serial`, and push it, under a lock, with a second person watching. The full flag reference is in the [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md).

## Worked examples

**1. A team keeps state on one engineer's laptop and wants it in S3 with locking.**
Create a versioned, KMS-encrypted bucket with Block Public Access from a separate bootstrap configuration. Add a `backend "s3"` block with `encrypt = true` and `use_lockfile = true`. Run `terraform init -migrate-state` and approve the copy. Run `terraform plan` and confirm it shows no changes. Then delete the local `terraform.tfstate` and its backup, which still hold every secret.

**2. A pipeline job was cancelled mid-apply. Every later run fails with a lock error.**
Read the lock info in the error: ID, who, when. Confirm in the CI system that the job is really dead and nothing else is running. Run `terraform force-unlock LOCK_ID`. Run `terraform plan` to see what the interrupted apply left half-done. If state will not load, restore the previous object version from the bucket.

**3. A plan unexpectedly wants to remove an ingress rule allowing `0.0.0.0/0` on port 22.**
That rule is drift: it exists in AWS but not in code. Do not apply yet. Run `terraform plan -refresh-only` to see the full extent, then find the `AuthorizeSecurityGroupIngress` event in CloudTrail to learn who added it and when. If it was unauthorized, follow the [drift runbook](../../runbooks/terraform-unexpected-drift.md), and then apply to remove it.

**4. A module refactor renames forty resources. The plan shows forty destroys and forty creates.**
Add a `moved` block for each rename (or one for the module call if a whole module moved). The plan then shows the moves and no destroy or create actions. Leave the blocks in place for a release or two so every environment and every consumer of the module picks them up.

**5. One configuration deploys to dev and prod, with state in different buckets.**
Use a partial configuration: `backend "s3" {}` in code, and a `dev.s3.tfbackend` and `prod.s3.tfbackend` file passed with `-backend-config`. Switching a working directory between them needs `terraform init -reconfigure`, not `-migrate-state`, or you will copy dev state over prod.

## Pitfalls and exam traps

- `sensitive = true` hides values from CLI output. It does not encrypt or remove them from state.
- S3 locking is opt-in. No `use_lockfile` and no `dynamodb_table` means no lock.
- `dynamodb_table` is deprecated, not removed. `use_lockfile` is the current answer.
- Backend blocks cannot use variables. Use partial configuration.
- `-migrate-state` copies state. `-reconfigure` ignores the old backend and copies nothing. Mixing them up either loses state or overwrites the wrong one.
- `-backend-config` values are stored in plaintext under `.terraform/` and in plan files.
- `.terraform/terraform.tfstate` is backend metadata, not your state.
- `terraform plan -refresh-only` and `apply -refresh-only` never change infrastructure. They do not update `.tf` files either.
- `terraform refresh` and `terraform taint` are deprecated. Use `-refresh-only` and `-replace`.
- `terraform state rm` and `removed` with `destroy = false` do not delete the resource. `removed` with `destroy = true` does.
- `force-unlock` removes the lock only, and only helps when the lock holder is really gone.
- `terraform state mv` and `moved` do the same job. The block is preferred because it is reviewed and repeatable.
- The backend does not create the bucket.
- Versioning on the bucket is the recovery mechanism for state. Without it, a bad write is permanent.
- CLI workspaces share one backend and one set of credentials. They are not a security boundary between environments.

## Self-check

1. Where does Terraform store state when there is no `backend` block, and what are two reasons that is unsuitable for a team?
2. Which S3 backend argument enables locking today, what does it create, and what is the status of `dynamodb_table`?
3. A backend block needs a different bucket per environment. Why can you not use a variable, and what do you use instead?
4. What is the difference between `terraform init -migrate-state` and `terraform init -reconfigure`?
5. Someone changed a tag in the console. Which command shows that change without proposing to revert it, and which command records it in state?
6. You rename `aws_iam_role.app` to `aws_iam_role.app_runtime`. How do you stop Terraform from destroying and recreating the role?
7. When is `terraform force-unlock` appropriate, and what can go wrong?
8. Name four controls you would put on an S3 bucket that holds Terraform state, and say what each protects against.

<details>
<summary>Answers</summary>

1. In `terraform.tfstate` in the working directory (the local backend). It is not shared, so teammates work from different state. Locking only works on one machine, and there is no access control, versioning, or audit trail. It is also easily committed to Git with its secrets.
2. `use_lockfile = true`, which creates a `KEY.tflock` object beside the state object for the length of the operation. `dynamodb_table` is deprecated and due for removal in a future minor version. It still works, and both can be set together while migrating.
3. Backend blocks cannot refer to named values, because the backend is initialized before variables are evaluated. Use a partial configuration and pass the values with `terraform init -backend-config=FILE` or `-backend-config="KEY=VALUE"`.
4. `-migrate-state` copies existing state to the newly configured backend. `-reconfigure` discards the saved backend configuration and initializes against the new one without migrating anything.
5. `terraform plan -refresh-only` shows it. `terraform apply -refresh-only` writes it to state after approval. Neither changes infrastructure or configuration.
6. Add a `moved` block with `from = aws_iam_role.app` and `to = aws_iam_role.app_runtime`. (`terraform state mv` also works, without review.)
7. Only to clear your own stale lock after the process that held it has certainly ended. If the holder is still running, two writers can corrupt state or lose changes.
8. Any four of: versioning (recover from corruption or deletion), SSE-KMS with a customer managed key (a second permission check and a key-use log), Block Public Access (no public exposure), a bucket policy limiting principals and requiring TLS (least privilege, no interception), CloudTrail data events or access logs (who read or wrote state), no `s3:DeleteObject` on the state key for the pipeline role (no deletion by a compromised pipeline).

</details>

## Further reading

- [Backend block configuration](https://developer.hashicorp.com/terraform/language/backend)
- [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [State locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [terraform init](https://developer.hashicorp.com/terraform/cli/commands/init)
- [terraform plan: planning modes and options](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [terraform state commands](https://developer.hashicorp.com/terraform/cli/commands/state)
- [moved block](https://developer.hashicorp.com/terraform/language/block/moved) and [removed block](https://developer.hashicorp.com/terraform/language/block/removed)
- [Remove a resource from state](https://developer.hashicorp.com/terraform/language/state/remove)
