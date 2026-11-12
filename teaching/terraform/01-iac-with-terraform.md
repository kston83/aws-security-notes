# Terraform 1: Infrastructure as Code with Terraform

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 1a–1c · **SCS-C03:** 6.2.1 · **Related:** [fundamentals](02-terraform-fundamentals.md), [core workflow](03-core-workflow.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [lab 01: first apply](../../labs/01-first-apply/README.md), [IaC control mappings](../../control-mappings/services/iac-terraform.md)

## Why this matters

A security group edited in the console leaves one CloudTrail event and no explanation. The same change made in code leaves a diff, a reviewer, a pipeline run, and a commit that can be reverted. Infrastructure as code turns configuration into something you can review before it exists and reproduce after it is gone. For a security team that is the difference between inspecting what was built and controlling what gets built.

It also concentrates risk. The pipeline that applies the code holds broad permissions, and the code repository becomes the real change-control system. Both need protecting: see [securing Terraform on AWS](09-securing-terraform-on-aws.md).

## Mental model

**You describe the end state. Terraform works out the API calls.**

```
   Configuration (.tf files)          State                     Real infrastructure
   "what should exist"                "what Terraform           "what does exist"
                                       believes it manages"
            │                               │                            │
            └───────────────┬───────────────┘                            │
                            ▼                                            │
                     Terraform core  ── builds a dependency graph,       │
                            │           compares desired with actual     │
                            ▼                                            │
                        Providers  ── plugins that translate ────────────┘
                     (aws, azurerm,      resources into API calls
                      vault, github…)
```

Three things are compared on every run: the configuration, the state, and the real infrastructure as read through the provider. The difference is the **plan**. Applying the plan makes the real infrastructure match the configuration and records the result in state.

Two styles of automation:

| Style | You write | Example | Running it twice |
|---|---|---|---|
| **Imperative** | The steps to take | A shell script of `aws ec2 create-…` calls | Creates duplicates or fails, unless you add checks yourself |
| **Declarative** | The result you want | Terraform, CloudFormation | Does nothing the second time, because the result already exists |

Terraform is declarative. The property that a second run changes nothing is **idempotence**.

## Objective 1a: What IaC is

**Infrastructure as code (IaC)** is managing infrastructure (networks, IAM, keys, compute, DNS, SaaS settings) through machine-readable definition files instead of consoles and one-off commands. The files are the source of truth and are handled like application code: version control, review, automated tests, a pipeline.

Terraform configuration is written in **HCL** (HashiCorp Configuration Language) in `.tf` files. A JSON variant (`.tf.json`) exists for generated configuration.

```hcl
resource "aws_kms_key" "logs" {
  description         = "Encrypts the audit log bucket"
  enable_key_rotation = true
}
```

This block does not say "call `kms:CreateKey`". It says a key with these settings exists. Terraform creates it if absent, updates it if different, and leaves it alone if it matches.

Terms that go with IaC:

| Term | Meaning |
|---|---|
| **Provisioning** | Creating and changing the infrastructure itself. This is Terraform's job. |
| **Configuration management** | Installing and configuring software inside a machine (Ansible, Chef, Puppet). Terraform can hand off to these tools but is not one. |
| **Drift** | The real infrastructure no longer matches the code, usually because someone changed it by hand. |
| **Mutable infrastructure** | Change resources in place. |
| **Immutable infrastructure** | Replace resources instead of changing them, for example a new AMI and a new instance rather than patching the old one. Terraform supports both and tells you in the plan which one will happen. |

## Objective 1b: Advantages of IaC patterns

| Advantage | What it means in practice | Security angle |
|---|---|---|
| **Versioned** | Every change is a commit with an author and a message | Change history that does not depend on log retention; supports NIST CM-3 |
| **Reviewable** | Changes go through pull requests; the plan shows the effect before anything happens | A second person sees the IAM policy before it is live |
| **Repeatable and consistent** | The same code builds dev, test, and prod; no step is forgotten | Encryption, logging, and tagging are identical everywhere |
| **Automated** | A pipeline applies changes, not a person with console access | Humans can lose standing write access to production |
| **Testable** | Static analysis and policy checks run on code and on the plan | A **proactive** control: noncompliant resources are rejected before deployment |
| **Reusable** | Modules package a known-good pattern | One hardened S3 bucket module instead of forty hand-built buckets |
| **Self-documenting** | The code states what exists and how it is wired | An inventory that is at least as current as the last apply |
| **Recoverable** | An environment can be rebuilt from code | Faster recovery after a destructive incident |
| **Faster** | Minutes rather than tickets | Security fixes roll out to every environment in one change |

Version control, review, and pipeline automation are IaC *patterns*: practices around the tool, not features of it. Terraform run by hand from a laptop with no review gives you repeatability and little else.

Terraform-specific advantages the exam expects you to know:

- **Execution plan.** Terraform shows what it will create, change, and destroy before it acts. See [core workflow](03-core-workflow.md).
- **Dependency graph.** Terraform reads references between resources, orders operations correctly, and runs independent operations in parallel.
- **State.** Terraform tracks what it manages, so it can detect drift and knows what to delete. See [fundamentals](02-terraform-fundamentals.md).
- **One workflow for many platforms.** Covered next.

## Objective 1c: Multi-cloud, hybrid, and service-agnostic workflows

Terraform core knows nothing about AWS. All platform knowledge lives in **providers**: separately released plugins that map resource types onto an API. Anything with an API can have a provider.

| Scenario | Meaning | Example |
|---|---|---|
| **Multi-cloud** | More than one public cloud in one workflow | AWS workloads with DNS in Cloudflare and identity in Microsoft Entra ID |
| **Hybrid cloud** | Public cloud plus on-premises or private cloud | AWS VPCs alongside VMware vSphere or a Kubernetes cluster in a data center |
| **Service-agnostic** | Not only infrastructure: any service with an API | GitHub repositories and branch protection, Datadog monitors, Vault policies, PagerDuty schedules |

What Terraform gives you across platforms is **one language, one workflow, and one dependency graph**. A single configuration can create an AWS load balancer and then a DNS record at another vendor that points to it, in the right order.

What it does **not** give you is abstraction. There is no generic "virtual machine" resource. `aws_instance` and `azurerm_linux_virtual_machine` are different resources with different arguments, and moving a workload between clouds means rewriting it.

For AWS practitioners, the usual comparison:

| | Terraform | CloudFormation |
|---|---|---|
| Scope | Any platform with a provider | AWS (plus third-party types through the registry) |
| Language | HCL | JSON or YAML |
| State | A state file you must store and protect | Held by the service inside AWS |
| Preview | Plan | Change set |
| Multi-account rollout | Provider aliases with assumed roles, or one pipeline run per account | StackSets |
| Runs where | Wherever you run the CLI, or HCP Terraform | Inside AWS |

The state row matters most for security. CloudFormation keeps its record of what it manages inside the service. Terraform writes it to a file, and that file can contain secrets. Where it lives and who can read it is your problem: see [state management](06-state-management.md).

## Worked examples

**1. A team opens SSH to the internet "temporarily" from the console, and nobody notices for a month.**
With the security group in Terraform, the next plan shows the rule as a change to be reverted, which is drift detection for free. Better, remove console write access so the change has to arrive as a pull request, and scan the plan for `0.0.0.0/0` on port 22 before apply. Procedure when drift does appear: [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md).

**2. An auditor asks who approved a change to a KMS key policy last quarter.**
With IaC the answer is the pull request: author, reviewer, the plan output attached to it, and the pipeline run that applied it. CloudTrail then confirms the pipeline role made the call and nobody else did.

**3. A company runs workloads on AWS, manages DNS at a third-party registrar, and stores secrets in Vault. It wants one change process for all three.**
One Terraform configuration with three providers. A new service creates its AWS resources, its DNS record, and its Vault policy in one reviewed change, ordered by the dependency graph.

**4. A team wants to move from AWS to another cloud and expects to change the provider name and re-apply.**
That will not work. The workflow carries over; the resource definitions do not. Every resource must be rewritten for the new provider.

## Pitfalls and exam traps

- Terraform is **declarative**, not imperative. You do not write the order of operations; the dependency graph decides it.
- Terraform is a **provisioning** tool, not a configuration management tool.
- Terraform is **cloud-agnostic in workflow, not in code**. Resources are provider-specific.
- Terraform needs no agent on the target and no server of its own. It is a single binary that calls APIs.
- IaC does not prevent drift. It makes drift visible at the next plan. Prevention takes access control.
- Idempotent means applying the same configuration again changes nothing. It does not mean every change is safe to apply.
- Putting infrastructure in code does not make it secure. A public bucket defined in HCL is still public; it is just reviewable.
- Version control holds the configuration. It must **not** hold state files or secrets.
- HCL is the usual syntax, but JSON is also accepted.

## Self-check

1. What is the difference between declarative and imperative infrastructure automation, and which is Terraform?
2. Name four advantages of IaC over console changes.
3. What does idempotent mean for `terraform apply`?
4. Which component gives Terraform its knowledge of a specific platform's API?
5. A configuration targets AWS. Can it be pointed at another cloud by swapping the provider block? Why?
6. Give one example each of a multi-cloud, a hybrid, and a service-agnostic use of Terraform.
7. Where does Terraform record what it manages, and how does that differ from CloudFormation?

<details>
<summary>Answers</summary>

1. Declarative describes the desired end state and lets the tool work out the steps. Imperative lists the steps. Terraform is declarative.
2. Any four of: versioned history, peer review before change, repeatable and consistent environments, automation in place of manual access, testable with policy checks, reusable modules, self-documenting, faster recovery and delivery.
3. Applying a configuration that already matches the real infrastructure makes no changes.
4. The provider plugin.
5. No. Resource types and arguments are specific to each provider. The workflow is portable; the resource definitions are not.
6. Multi-cloud: AWS compute with DNS at another cloud vendor. Hybrid: AWS plus on-premises vSphere. Service-agnostic: managing GitHub repositories or Vault policies.
7. In the state file, which you store and protect yourself (locally or in a backend such as S3 or HCP Terraform). CloudFormation keeps the equivalent record inside the AWS service.

</details>

## Further reading

- [What is Terraform?](https://developer.hashicorp.com/terraform/intro)
- [Terraform use cases](https://developer.hashicorp.com/terraform/intro/use-cases)
- [What is Infrastructure as Code with Terraform?](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/infrastructure-as-code)
- [Terraform Associate (004) exam content list](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004)
- [Terraform Registry: providers](https://registry.terraform.io/browse/providers)
- Background in this repo: [Domain 6, Task 6.2: Deployment](../06-security-foundations-and-governance.md#task-62-deployment)
