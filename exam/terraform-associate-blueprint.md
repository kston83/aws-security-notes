# Terraform Associate (004) blueprint map

> **Last reviewed:** 2026-11-11 · **Source:** [Exam content list – Terraform Associate 004](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-review-004)

Every objective in HashiCorp's exam content list, mapped to where this repo covers it. Objective wording is taken from the content list. The plan for working through it is in the [Terraform study plan](terraform-study-plan.md).

## Exam facts

Taken from HashiCorp's [Terraform Associate (004) page](https://developer.hashicorp.com/certifications/terraform-associate) and [sample questions](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-questions-004) on 2026-11-11. All of it is exam logistics, so confirm before you book **(verify)**.

| Item | Value |
|---|---|
| Exam name | HashiCorp Certified: Terraform Associate (004) |
| Product version tested | Terraform 1.12. Features added in later releases are not exam content. |
| Assessment type | Multiple choice |
| Question types | True or false, multiple choice (one correct answer), multiple answer (the question says how many to pick) |
| Duration | 1 hour |
| Delivery | Online proctored |
| Language | English |
| Price | $70.50 USD plus local taxes and fees; no free retake included |
| Credential expiration | 2 years |
| Prerequisites | Basic terminal skills; understanding of on-premises and cloud architecture. Production experience is recommended, not required. |
| Recertification | Pass the 004 exam again from 6 months before expiration, or pass the Terraform Infrastructure Engineer Professional exam or a Terraform Authoring and Operations Advanced exam; each extends the Associate expiration date |

HashiCorp's pages do not state the number of questions, the pass mark, or the scoring method, so none is given here. **HCP Terraform** is HashiCorp's hosted Terraform service (formerly Terraform Cloud); the exam covers it alongside the Terraform CLI.

## Domains

HashiCorp does not publish per-domain weights for this exam. The content list gives eight domains and their objectives and nothing about how many questions each carries, so plan by objective count and by your own gaps.

| Domain | Objectives | Teaching note |
|---|---|---|
| 1. Infrastructure as Code (IaC) with Terraform | 1a–1c | [terraform/01-iac-with-terraform](../teaching/terraform/01-iac-with-terraform.md) |
| 2. Terraform fundamentals | 2a–2d | [terraform/02-terraform-fundamentals](../teaching/terraform/02-terraform-fundamentals.md) |
| 3. Core Terraform workflow | 3a–3g | [terraform/03-core-workflow](../teaching/terraform/03-core-workflow.md) |
| 4. Terraform configuration | 4a–4h | [terraform/04-configuration](../teaching/terraform/04-configuration.md) |
| 5. Terraform modules | 5a–5d | [terraform/05-modules](../teaching/terraform/05-modules.md) |
| 6. Terraform state management | 6a–6d | [terraform/06-state-management](../teaching/terraform/06-state-management.md) |
| 7. Maintain infrastructure with Terraform | 7a–7c | [terraform/07-maintaining-infrastructure](../teaching/terraform/07-maintaining-infrastructure.md) |
| 8. HCP Terraform | 8a–8d | [terraform/08-hcp-terraform](../teaching/terraform/08-hcp-terraform.md) |

## Domain 1: Infrastructure as Code (IaC) with Terraform

| Objective | Statement | Covered in |
|---|---|---|
| 1a | Explain what IaC is | [terraform/01](../teaching/terraform/01-iac-with-terraform.md#objective-1a-what-iac-is) |
| 1b | Describe the advantages of IaC patterns | [terraform/01](../teaching/terraform/01-iac-with-terraform.md#objective-1b-advantages-of-iac-patterns) |
| 1c | Explain how Terraform manages multi-cloud, hybrid cloud, and service-agnostic workflows | [terraform/01](../teaching/terraform/01-iac-with-terraform.md#objective-1c-multi-cloud-hybrid-and-service-agnostic-workflows) |

## Domain 2: Terraform fundamentals

| Objective | Statement | Covered in |
|---|---|---|
| 2a | Install and version Terraform providers | [terraform/02](../teaching/terraform/02-terraform-fundamentals.md#objective-2a-install-and-version-providers), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 2b | Describe how Terraform uses providers | [terraform/02](../teaching/terraform/02-terraform-fundamentals.md#objective-2b-how-terraform-uses-providers), [AWS provider security](../cheatsheets/terraform-aws-provider-security.md) |
| 2c | Write Terraform configuration using multiple providers | [terraform/02](../teaching/terraform/02-terraform-fundamentals.md#objective-2c-multiple-provider-configurations), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 08](../labs/08-detection-baseline/README.md) |
| 2d | Explain how Terraform uses and manages state | [terraform/02](../teaching/terraform/02-terraform-fundamentals.md#objective-2d-what-state-is-and-why-terraform-needs-it), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 02](../labs/02-remote-state/README.md), [state exposure runbook](../runbooks/terraform-state-exposure.md) |

## Domain 3: Core Terraform workflow

| Objective | Statement | Covered in |
|---|---|---|
| 3a | Describe the Terraform workflow | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3a-the-core-workflow), [lab 01](../labs/01-first-apply/README.md) |
| 3b | Initialize a Terraform working directory | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3b-init), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 3c | Validate a Terraform configuration | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3c-validate), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 3d | Generate and review an execution plan for Terraform | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3d-plan), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 3e | Apply changes to infrastructure with Terraform | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3e-apply), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 3f | Destroy Terraform-managed infrastructure | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3f-destroy), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |
| 3g | Apply formatting and style adjustments to a configuration | [terraform/03](../teaching/terraform/03-core-workflow.md#objective-3g-format), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 01](../labs/01-first-apply/README.md) |

## Domain 4: Terraform configuration

| Objective | Statement | Covered in |
|---|---|---|
| 4a | Use and differentiate `resource` and `data` blocks | [terraform/04](../teaching/terraform/04-configuration.md#objective-4a-resource-and-data-blocks), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 04](../labs/04-iam-least-privilege/README.md) |
| 4b | Refer to resource attributes and create cross-resource references | [terraform/04](../teaching/terraform/04-configuration.md#objective-4b-references), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 04](../labs/04-iam-least-privilege/README.md) |
| 4c | Use variables and outputs | [terraform/04](../teaching/terraform/04-configuration.md#objective-4c-variables-and-outputs), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md) |
| 4d | Understand and use complex types | [terraform/04](../teaching/terraform/04-configuration.md#objective-4d-complex-types), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md) |
| 4e | Write dynamic configuration using expressions and functions | [terraform/04](../teaching/terraform/04-configuration.md#objective-4e-expressions-and-functions), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md) |
| 4f | Define resource dependencies in configuration | [terraform/04](../teaching/terraform/04-configuration.md#objective-4f-dependencies-and-lifecycle), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 04](../labs/04-iam-least-privilege/README.md) |
| 4g | Validate configuration using custom conditions | [terraform/04](../teaching/terraform/04-configuration.md#objective-4g-custom-conditions), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md), [lab 07](../labs/07-tests-and-guardrails/README.md) |
| 4h | Understand best practices for managing sensitive data, including secrets management with Vault | [terraform/04](../teaching/terraform/04-configuration.md#objective-4h-sensitive-data-and-vault), [AWS provider security](../cheatsheets/terraform-aws-provider-security.md), [lab 05](../labs/05-kms-and-secrets/README.md), [state exposure runbook](../runbooks/terraform-state-exposure.md) |

## Domain 5: Terraform modules

| Objective | Statement | Covered in |
|---|---|---|
| 5a | Explain how Terraform sources modules | [terraform/05](../teaching/terraform/05-modules.md#objective-5a-module-sources), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md) |
| 5b | Describe variable scope within modules | [terraform/05](../teaching/terraform/05-modules.md#objective-5b-variable-scope-in-modules), [lab 03](../labs/03-variables-and-modules/README.md) |
| 5c | Use modules in configuration | [terraform/05](../teaching/terraform/05-modules.md#objective-5c-using-modules), [HCL cheatsheet](../cheatsheets/terraform-hcl.md), [lab 03](../labs/03-variables-and-modules/README.md) |
| 5d | Manage module versions | [terraform/05](../teaching/terraform/05-modules.md#objective-5d-module-versions), [lab 03](../labs/03-variables-and-modules/README.md) |

## Domain 6: Terraform state management

| Objective | Statement | Covered in |
|---|---|---|
| 6a | Describe the local backend | [terraform/06](../teaching/terraform/06-state-management.md#objective-6a-the-local-backend), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 02](../labs/02-remote-state/README.md) |
| 6b | Describe state locking | [terraform/06](../teaching/terraform/06-state-management.md#objective-6b-state-locking), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 02](../labs/02-remote-state/README.md), [state lock and corruption runbook](../runbooks/terraform-state-lock-and-corruption.md) |
| 6c | Configure remote state using the backend block | [terraform/06](../teaching/terraform/06-state-management.md#objective-6c-remote-state-with-the-backend-block), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 02](../labs/02-remote-state/README.md) |
| 6d | Manage resource drift and Terraform state | [terraform/06](../teaching/terraform/06-state-management.md#objective-6d-drift-and-state-management), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 06](../labs/06-drift-and-import/README.md), [unexpected drift runbook](../runbooks/terraform-unexpected-drift.md) |

## Domain 7: Maintain infrastructure with Terraform

| Objective | Statement | Covered in |
|---|---|---|
| 7a | Import existing infrastructure into your Terraform workspace | [terraform/07](../teaching/terraform/07-maintaining-infrastructure.md#objective-7a-importing-existing-infrastructure), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 06](../labs/06-drift-and-import/README.md) |
| 7b | Use the CLI to inspect state | [terraform/07](../teaching/terraform/07-maintaining-infrastructure.md#objective-7b-inspecting-state-with-the-cli), [state and backends](../cheatsheets/terraform-state-and-backends.md), [lab 06](../labs/06-drift-and-import/README.md) |
| 7c | Describe when and how to use verbose logging | [terraform/07](../teaching/terraform/07-maintaining-infrastructure.md#objective-7c-verbose-logging), [CLI cheatsheet](../cheatsheets/terraform-cli.md), [lab 06](../labs/06-drift-and-import/README.md) |

## Domain 8: HCP Terraform

No lab covers this domain: the labs run against a local emulator, and HCP Terraform is a hosted service. The [study plan](terraform-study-plan.md#weekly-plan) has an exercise for it.

| Objective | Statement | Covered in |
|---|---|---|
| 8a | Use HCP Terraform to create infrastructure | [terraform/08](../teaching/terraform/08-hcp-terraform.md#objective-8a-creating-infrastructure-with-hcp-terraform), [CLI cheatsheet](../cheatsheets/terraform-cli.md) |
| 8b | Describe HCP Terraform collaboration and governance features | [terraform/08](../teaching/terraform/08-hcp-terraform.md#objective-8b-collaboration-and-governance) |
| 8c | Describe how to organize and use HCP Terraform workspaces and projects | [terraform/08](../teaching/terraform/08-hcp-terraform.md#objective-8c-workspaces-and-projects) |
| 8d | Configure and use HCP Terraform integration | [terraform/08](../teaching/terraform/08-hcp-terraform.md#objective-8d-integrations) |

## What changed from 003

From the differences section of the exam content list:

- Four new topics: resource dependencies with `depends_on` and the `create_before_destroy` lifecycle rule (4f), custom conditions (4g), ephemeral values and write-only arguments (part of 4h), and organizing HCP Terraform workspaces and projects (8c).
- The tested version moved to Terraform 1.12.
- HCP Terraform content is included, under that name.

The content list has the authoritative comparison.

## In this repo but not on the exam

This material is for doing the job on AWS and for SCS-C03 skill 6.2.1 (see the [SCS-C03 blueprint](scs-c03-blueprint.md)). Skip it if you are studying only for the Terraform Associate exam.

| Material | What it is for |
|---|---|
| [terraform/09 Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md) | Threat model for a Terraform pipeline: OIDC federation from CI, plan and apply roles, state protection, supply chain, guardrails before apply. The exam asks about none of the AWS specifics. |
| [State exposure](../runbooks/terraform-state-exposure.md), [state lock and corruption](../runbooks/terraform-state-lock-and-corruption.md), [unexpected drift](../runbooks/terraform-unexpected-drift.md), [pipeline compromise](../runbooks/terraform-pipeline-compromise.md) runbooks | Incident procedures. They exercise objectives 2d, 4h, 6b, and 6d, but the exam tests the concepts, not incident response. |
| [control-mappings/services/iac-terraform](../control-mappings/services/iac-terraform.md) | NIST SP 800-53 Rev. 5 controls that Terraform configurations support. Audit material only. |
| [AWS provider security cheatsheet](../cheatsheets/terraform-aws-provider-security.md) | Mostly beyond the exam: the exam is provider-agnostic and expects only how providers are configured and authenticated in general (2b, 4h). |
| Labs [04](../labs/04-iam-least-privilege/README.md), [05](../labs/05-kms-and-secrets/README.md), [07](../labs/07-tests-and-guardrails/README.md), [08](../labs/08-detection-baseline/README.md) | The Terraform in them is exam content. The IAM, KMS, and detection design they build is SCS-C03 content, and `terraform test` in lab 07 is not in the 004 content list. |
