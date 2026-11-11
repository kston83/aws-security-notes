# Terraform 8: HCP Terraform

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 8a–8d · **SCS-C03:** 6.2.1 · **Related:** [state management](06-state-management.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md), [drift runbook](../../runbooks/terraform-unexpected-drift.md), [IaC mappings](../../control-mappings/services/iac-terraform.md)

## Why this matters

Terraform on a laptop has no access control, no approval step, no audit trail, and needs cloud credentials on that laptop. **HCP Terraform** is HashiCorp's hosted service that runs Terraform for a team: it stores state, runs plans and applies on its own workers, and puts permissions, policy checks, and logging around every run. For a security team it is one implementation of the controls any Terraform pipeline needs. The exam tests what it offers and how a configuration connects to it.

Naming: HCP Terraform was called Terraform Cloud until 2024, and older material and the `TFC_` variable prefixes still use that name. **Terraform Enterprise** is the self-hosted product with a similar feature set.

## Mental model

**A workspace is one state plus everything needed to change it.** Runs are queued against a workspace and pass through fixed stages. Controls attach at those stages.

```
   Organization ── teams, policy sets, variable sets, private registry, audit trail
        │
     Project  ── groups workspaces; team access, variable sets, and policy sets can be scoped here
        │
    Workspace ── configuration version · variables · state (versioned) · run history · lock

   A run:
   Pending → Fetching → Pre-plan → Plan → Post-plan → OPA policy → Cost estimation → Sentinel policy → Pre-apply → Apply → Post-apply
                         run task          run task    check                         check             run task            run task
                                                                      (confirm here unless auto-apply is on)
```

Stages appear only if the feature is configured. A workspace runs one run at a time; later runs wait in **Pending**. That queue is the workspace's state lock.

| Local Terraform | HCP Terraform |
|---|---|
| Working directory | Workspace |
| State file or remote backend | State stored and versioned in the workspace, encrypted at rest |
| `.tfvars` files and shell environment | Workspace variables and variable sets |
| Credentials in your shell | Workspace variables, or dynamic credentials issued per run |
| Whoever has the credentials can apply | Team permissions decide who can plan, apply, and approve |

## Objective 8a: Creating infrastructure with HCP Terraform

### Three run workflows

| Workflow | A run starts when | Typical use |
|---|---|---|
| **VCS-driven** | A commit lands on the workspace's tracked branch. A pull request triggers a speculative plan. | The default for teams. The repository is the source of truth and nobody applies from a laptop. |
| **CLI-driven** | Someone runs `terraform plan` or `terraform apply` in a directory with a `cloud` block. The run executes remotely and its output streams to the terminal. | Development, or an existing CI system that calls the CLI |
| **API-driven** | A tool uploads a configuration version and creates a run through the API | Custom pipelines and platforms. The most flexible, and it needs tooling you build. |

A **speculative plan** is plan-only: it can never be applied, and it does not wait in the run queue. Pull requests and a CLI `terraform plan` produce speculative plans. In a VCS-driven workspace, `terraform apply` from the CLI is refused: applies come from the repository.

**Execution mode** decides where Terraform runs:

| Mode | Where Terraform runs | State |
|---|---|---|
| Remote (default) | HCP Terraform's disposable workers | HCP Terraform |
| Local | Your machine or CI runner | HCP Terraform, used only as a state store |
| Agent | An **HCP Terraform agent** you run inside your network, which polls outward for work | HCP Terraform. For private networks that allow no inbound access. A paid feature **(verify)**. |

### The cloud block

```hcl
terraform {
  required_version = ">= 1.12"

  cloud {
    organization = "ORGANIZATION_NAME"

    workspaces {
      name    = "network-prod"
      project = "PROJECT_NAME"
    }
  }
}
```

| Argument | Notes |
|---|---|
| `organization` | Or set `TF_CLOUD_ORGANIZATION` |
| `workspaces` `name` | Binds the directory to one workspace. Or set `TF_WORKSPACE`. |
| `workspaces` `tags` | Binds the directory to every workspace carrying those tags; pick one with `terraform workspace select`. Mutually exclusive with `name`. |
| `workspaces` `project` | The project to use or to create new workspaces in. Or set `TF_CLOUD_PROJECT`. |
| `hostname` | Defaults to `app.terraform.io`. Set it for Terraform Enterprise. Or `TF_CLOUD_HOSTNAME`. |
| `token` | Supported but should be left out. Use `terraform login`. |

Rules:

- One `cloud` block per configuration, and it cannot be combined with a `backend` block.
- Like a backend block, it cannot refer to variables, locals, or data sources.
- After adding or changing it, run `terraform init`. If local state exists, `init` offers to migrate it into the workspace.
- `terraform login` gets a user API token and stores it in plaintext in the CLI credentials file in your home directory. Protect that file, and in CI supply a token through the `TF_TOKEN_app_terraform_io` environment variable instead.
- The older `backend "remote"` block does the same job with fewer features. The `cloud` block is the current form.

## Objective 8b: Collaboration and governance

### Teams and permissions

Users belong to **teams**, and teams are granted permissions at three scopes: organization, project, and workspace. Permissions are additive: a user gets the highest level granted by any of their teams at any scope.

The **owners** team has full control of the organization. Keep it small.

| Workspace permission set | Allows |
|---|---|
| **Read** | View runs, variables (not sensitive values), and state |
| **Plan** | Read, plus queue plans. Cannot apply. |
| **Write** | Plan, plus apply runs, edit variables, read and write state, lock and unlock the workspace |
| **Admin** | Write, plus workspace settings, team access, run tasks, and deletion |

Custom permission sets let you grant, for example, plan and apply without access to state. That matters because **state read access is secret read access** (see [state management](06-state-management.md)).

### Policy enforcement

**Policy as code** checks every plan against rules before apply. Policies are grouped into **policy sets** that apply globally or to chosen projects and workspaces.

| Framework | Language | Enforcement levels |
|---|---|---|
| **Sentinel** | HashiCorp's own policy language | **Advisory**: failure is reported, run continues. **Soft mandatory**: failure stops the run, and permitted users can override. **Hard mandatory**: failure stops the run, with no override unless the policy set is configured to allow one. |
| **OPA** (Open Policy Agent) | Rego | **Advisory**, or **mandatory**: failure stops the run, and users with the override permission can override. |

Sentinel checks run after cost estimation, so a policy can refuse a run that costs too much. OPA checks run before it. The current documentation also lists a native HCL-based Terraform policy framework that needs Terraform 1.17 or later **(verify)**; it is newer than the 1.12 exam target.

Typical security policies: no security group open to `0.0.0.0/0` on administrative ports, every S3 bucket encrypted with a customer managed key, modules only from the private registry, mandatory tags. This is the same proactive-control idea as CloudFormation Guard and hooks in [governance](../06-security-foundations-and-governance.md#task-62-deployment).

### Other governance features

| Feature | What it does |
|---|---|
| **Run tasks** | Send run data to an external service at the pre-plan, post-plan, pre-apply, or post-apply stage and get pass or fail back. Used for security scanners, cost tools, and change-management systems. Advisory or mandatory. |
| **Private registry** | Hosts your organization's modules and providers with versions and documentation. Reference a module as `app.terraform.io/ORGANIZATION_NAME/MODULE_NAME/PROVIDER`. Lets a security team publish approved, hardened modules, and a policy can require them. |
| **Audit trails** | An API stream of who did what in the organization: runs, state versions, variable changes, team membership, tokens. Retained for a short period, so export it to your log platform **(verify)**. |
| **Health assessments** | Scheduled checks on a workspace. **Drift detection** finds differences between real infrastructure and configuration. **Continuous validation** re-evaluates preconditions, postconditions, and `check` blocks. Results can raise notifications. Needs remote or agent execution. |
| **Cost estimation** | Estimates the monthly cost change of a plan for supported resources |
| **Run approvals** | Without auto-apply, a run pauses after plan and policy checks until someone with apply permission confirms |
| **Single sign-on and two-factor authentication** | Tie access to your identity provider |

Drift detection here is the hosted version of `terraform plan -refresh-only` on a schedule. A drift alert on a security group or IAM policy is a detection signal, not housekeeping: see the [drift runbook](../../runbooks/terraform-unexpected-drift.md).

### Dynamic provider credentials

The obvious way to give a workspace AWS access is to store an IAM user's access key as a sensitive variable. That is a long-lived key, in a third-party service, with enough permission to build your infrastructure. **Dynamic provider credentials** remove it.

HCP Terraform acts as an OpenID Connect (OIDC) identity provider. For each run it issues a signed token describing the run. AWS STS exchanges that token for temporary credentials for a role, valid for the plan or apply only.

1. In the AWS account, create an IAM OIDC provider for `https://app.terraform.io` with audience `aws.workload.identity`.
2. Create a role whose trust policy allows `sts:AssumeRoleWithWebIdentity` from that provider, conditioned on the token's claims.
3. In the workspace or a variable set, set environment variables `TFC_AWS_PROVIDER_AUTH=true` and `TFC_AWS_RUN_ROLE_ARN=ROLE_ARN`.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::111122223333:oidc-provider/app.terraform.io" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "app.terraform.io:aud": "aws.workload.identity" },
      "StringLike": { "app.terraform.io:sub": "organization:ORGANIZATION_NAME:project:PROJECT_NAME:workspace:WORKSPACE_NAME:run_phase:*" }
    }
  }]
}
```

The `sub` condition is the control. Without it, any organization on HCP Terraform could assume the role. Always pin at least the audience and the organization, and normally the project and workspace. `TFC_AWS_PLAN_ROLE_ARN` and `TFC_AWS_APPLY_ROLE_ARN` give the plan phase a read-only role and the apply phase a write role. The full pattern, with the same idea for other CI systems, is in [securing Terraform on AWS](09-securing-terraform-on-aws.md).

### What each edition includes

HCP Terraform is sold as Free, Essentials, Standard, and Premium editions **(verify)**. Availability changes often and HashiCorp's own pages are not always consistent with each other, so check before you design around a feature.

| Fact | Value |
|---|---|
| Free edition size limit | 500 managed resources **(verify)** |
| Policy enforcement on Free | One policy set of up to five policies **(verify)** |
| Run tasks on Free | One run task, attached to up to ten workspaces **(verify)** |
| Health assessments (drift detection, continuous validation) | Standard and Premium **(verify)** |
| Audit trails | Standard and Premium, 14 days of retention **(verify)** |
| Remote state, remote runs, VCS connection, private registry, dynamic credentials | All editions **(verify)** |

The exam asks what the features do, not which edition has them.

## Objective 8c: Workspaces and projects

An HCP Terraform **workspace** holds one configuration's state, variables, run history, and settings. It is not the same thing as a CLI workspace.

| | CLI workspace | HCP Terraform workspace |
|---|---|---|
| What it is | A named state file inside one working directory and backend | A managed unit with its own state, variables, credentials, permissions, and run history |
| Access control | None of its own | Per workspace, through teams |
| Created with | `terraform workspace new NAME` | UI, API, CLI, or the `tfe` provider |

Design guidance:

- **Split by blast radius.** One workspace per component per environment, such as `network-prod` and `app1-prod`, not one workspace for everything. Smaller state means smaller plans, narrower credentials, and less damage from a bad run.
- **Separate credentials per environment.** A dev workspace should hold a role that cannot touch prod.
- Each workspace keeps every **state version**, so you can inspect or roll back to an earlier one.
- A workspace can be **locked** by hand to stop all runs, for example during an incident.
- Sharing data between workspaces: the `tfe_outputs` data source reads another workspace's outputs, and access is off unless the source workspace shares its state with the consumer. Prefer it to `terraform_remote_state`, which needs access to the whole state.

A **project** groups workspaces. Every workspace belongs to exactly one project, and new workspaces land in the **Default Project** unless you say otherwise. Team access granted on a project applies to every workspace in it, which is how you delegate: the payments team administers the payments project and sees nothing else. Policy sets and variable sets can also be scoped to projects.

**Stacks** are a newer way to deploy the same components repeatedly across environments, accounts, or Regions, using `.tfcomponent.hcl` and `.tfdeploy.hcl` files. They sit beside workspaces inside projects. They are not named in the 004 objectives.

### Variables and variable sets

| Kind | Used for |
|---|---|
| **Terraform variable** | A value for an input variable declared in the configuration |
| **Environment variable** | Set in the run's shell: provider credentials, `TF_LOG`, `TFC_` settings |

Either kind can be marked **sensitive**: the value is write-only afterward, hidden in the UI and API, and still available to runs. Sensitive only hides the value from people. Code in a run can still read it and print it.

A **variable set** is a reusable group of variables applied to many workspaces: globally, to projects, or to selected workspaces. Typical use: one set holding the dynamic-credential variables for an AWS account. A variable set should carry the narrowest scope that works. A global set with production credentials hands them to every workspace, including a sandbox where anyone can run arbitrary code.

Precedence, simplified: a workspace's own variable overrides the same key from a variable set, and a narrower-scoped set overrides a wider one. A variable set marked **priority** reverses that and overrides workspace values. The full order is in the HashiCorp reference under Further reading.

## Objective 8d: Integrations

| Integration | What it connects |
|---|---|
| **VCS providers** | GitHub, GitLab, Bitbucket, and Azure DevOps. Commits trigger runs; pull requests get speculative plans with the result posted back as a status check. |
| **`cloud` block and `terraform login`** | The Terraform CLI |
| **API and tokens** | Everything the UI does is in the API. Tokens are **user**, **team**, or **organization** tokens; use a team token for a pipeline so it has only that team's access. |
| **`tfe` provider** | Manage HCP Terraform itself (workspaces, teams, variables, policy sets) as Terraform code |
| **Run tasks** | Third-party scanners and tools inside the run |
| **Notifications** | Run and health events to Slack, Microsoft Teams, email, or a generic webhook |
| **Run triggers** | A successful apply in one workspace queues a run in another, for example network then application |
| **Agents** | Run inside private networks |
| **OIDC dynamic credentials** | AWS, Azure, Google Cloud, Vault, and Kubernetes |
| **Single sign-on** | SAML identity providers |

The VCS connection deserves the scrutiny you would give any pipeline. Whoever can merge to the tracked branch can change infrastructure, so branch protection and required reviews on that repository are part of your access control. A pull request from an untrusted fork that triggers a plan can run code during planning (through external data sources and provider behavior), which is why speculative plans from forks are off by default. If the pipeline itself is suspect, see the [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md).

## Worked examples

**1. A team applies from laptops with a shared IAM user key. Move them to HCP Terraform with no stored AWS keys.**
Create a workspace per component and environment. Connect it to the repository (VCS-driven). Create the OIDC provider and a role in AWS with a trust policy pinned to the organization, project, and workspace. Set `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` in a project-scoped variable set. Add the `cloud` block, run `terraform init` to migrate state, confirm an empty plan, then delete the IAM user's key.

**2. No run may create a security group open to the world on port 22, with no exceptions.**
A Sentinel policy at **hard mandatory** (or an OPA policy at mandatory with override permission granted to nobody), in a policy set applied globally. A soft mandatory level would let an authorized user click through it.

**3. Developers should see what a change will do, but only the platform team may apply to production.**
Give the developer team **Plan** on the production project and the platform team **Write**. Leave auto-apply off so each run waits for confirmation. Developers' pull requests still get speculative plans.

**4. The security team wants to know within a day when production infrastructure is changed by hand.**
Enable health assessments on the production workspaces and send drift notifications to the security channel. Pair it with CloudTrail-based detection, which is faster and names the actor.

**5. A third-party scanner must check every plan before apply.**
Add it as a **run task** at the post-plan stage with mandatory enforcement, scoped to the relevant workspaces. A failed scan blocks the run before the confirmation step.

## Pitfalls and exam traps

- HCP Terraform and Terraform Cloud are the same service. Terraform Enterprise is the self-hosted product.
- `cloud` and `backend` blocks cannot both appear in a configuration.
- The `cloud` block cannot use variables. Use the `TF_CLOUD_ORGANIZATION`, `TF_WORKSPACE`, and related environment variables.
- `workspaces` takes `name` or `tags`, not both.
- A CLI workspace is a second state file. An HCP Terraform workspace is a managed unit with its own access control.
- A speculative plan cannot be applied.
- In a VCS-driven workspace you cannot `terraform apply` from the CLI.
- With remote execution, `terraform plan` on your laptop runs in HCP Terraform, using the workspace's variables, not your shell's.
- Sentinel has three enforcement levels. OPA has two.
- Advisory policies and advisory run tasks never stop a run.
- Sensitive variables are write-only in the UI but readable by the run.
- Every workspace is in exactly one project.
- Dynamic credentials need a trust policy condition on `sub`. Checking only `aud` trusts every HCP Terraform customer.
- Drift detection reports drift. It does not fix it.
- `terraform login` stores the token unencrypted on disk.

## Self-check

1. Name the three run workflows and what starts a run in each.
2. What does the `cloud` block need at minimum, and which block can it not coexist with?
3. What is a speculative plan, and name two things that produce one.
4. List the Sentinel enforcement levels and say which can be overridden.
5. How does an HCP Terraform workspace differ from a CLI workspace?
6. Explain how dynamic provider credentials work with AWS and what they replace.
7. What is a variable set, and what is the risk of a global one that holds credentials?
8. Which feature tells you that someone changed managed infrastructure outside Terraform, and what does it not do?

<details>
<summary>Answers</summary>

1. VCS-driven: a commit to the tracked branch (pull requests get speculative plans). CLI-driven: `terraform plan` or `terraform apply` from a directory with a `cloud` block. API-driven: a tool uploads a configuration version and creates a run through the API.
2. An organization and a `workspaces` block with `name` or `tags` (either may come from environment variables). It cannot be used together with a `backend` block.
3. A plan-only run that can never be applied and does not block the run queue. Produced by a pull request on a VCS-connected workspace, by `terraform plan` from the CLI, or by an API run on a speculative configuration version.
4. Advisory (never blocks), soft mandatory (blocks; permitted users can override), hard mandatory (blocks; no override unless the policy set is explicitly configured to allow overrides).
5. A CLI workspace is an additional named state within one working directory and backend, with no access control of its own. An HCP Terraform workspace holds state, variables, credentials, run history, and team permissions for one configuration.
6. HCP Terraform issues an OIDC token for each run. An IAM role trusts HCP Terraform's OIDC provider, conditioned on the token's audience and subject (organization, project, workspace, run phase). STS returns temporary credentials for that plan or apply. They replace long-lived IAM user access keys stored as workspace variables.
7. A reusable group of variables applied to many workspaces, scoped globally, to projects, or to chosen workspaces. A global set gives its credentials to every workspace, so anyone who can run code in any workspace can use them.
8. Health assessments (drift detection). It reports and notifies; it does not revert the change, and it does not tell you who made it.

</details>

## Further reading

- [HCP Terraform overview and editions](https://developer.hashicorp.com/terraform/cloud-docs/overview)
- [Remote operations and run workflows](https://developer.hashicorp.com/terraform/cloud-docs/run/remote-operations)
- [Run states and stages](https://developer.hashicorp.com/terraform/cloud-docs/run/states)
- [terraform block reference: cloud](https://developer.hashicorp.com/terraform/language/block/terraform)
- [Workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces) and [projects](https://developer.hashicorp.com/terraform/cloud-docs/projects)
- [Variables and variable sets](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/variables)
- [Permissions](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/permissions)
- [Policy enforcement](https://developer.hashicorp.com/terraform/cloud-docs/policy-enforcement) and [run tasks](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings/run-tasks)
- [Health assessments](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/health)
- [Dynamic credentials with the AWS provider](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [Audit trails API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/audit-trails)
