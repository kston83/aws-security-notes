# Terraform Associate (004) study plan

> **Last reviewed:** 2026-11-11 · **Related:** [Terraform blueprint](terraform-associate-blueprint.md), [labs](../labs/README.md), [SCS-C03 study plan](study-plan.md)

A five-week plan at roughly 5–6 hours a week for someone who already works in AWS and has run Terraform a few times. Compress or stretch to fit; keep the order. State comes in week 2, ahead of configuration, because every later topic (drift, import, modules, HCP Terraform) is easier once you know what state holds. The labs run on a local emulator, so nothing in the plan needs an AWS account.

## Weekly plan

| Week | Focus | Read | Do |
|---|---|---|---|
| 1 | IaC concepts, providers, the core workflow (domains 1–3) | [terraform/01](../teaching/terraform/01-iac-with-terraform.md), [terraform/02](../teaching/terraform/02-terraform-fundamentals.md), [terraform/03](../teaching/terraform/03-core-workflow.md), [CLI cheatsheet](../cheatsheets/terraform-cli.md) | [Lab 01](../labs/01-first-apply/README.md). Then save a plan with `terraform plan -out=tfplan`, change the configuration, and apply the saved plan to see which version wins. Open `.terraform.lock.hcl`, loosen the provider version constraint, and compare `terraform init` with `terraform init -upgrade`. |
| 2 | State, locking, backends (objective 2d, domain 6) | [terraform/06](../teaching/terraform/06-state-management.md), [state and backends](../cheatsheets/terraform-state-and-backends.md) | [Lab 02](../labs/02-remote-state/README.md). Then move the state back to the local backend with `terraform init -migrate-state` and say what `-reconfigure` would have done instead. Read the [state lock and corruption runbook](../runbooks/terraform-state-lock-and-corruption.md) and find where it uses `terraform force-unlock`. |
| 3 | Configuration and modules (domains 4–5) | [terraform/04](../teaching/terraform/04-configuration.md), [terraform/05](../teaching/terraform/05-modules.md), [HCL cheatsheet](../cheatsheets/terraform-hcl.md) | [Lab 03](../labs/03-variables-and-modules/README.md), [lab 04](../labs/04-iam-least-privilege/README.md), [lab 05](../labs/05-kms-and-secrets/README.md). This is the heaviest week; let lab 05 slip into week 4 if you need to. Then use `terraform console` to evaluate ten functions from the cheatsheet against your own variables, and convert one `count` resource to `for_each` with a `moved` block so the plan shows no destroy. |
| 4 | Drift, import, inspecting state, logging, custom conditions (objectives 6d, 4g, domain 7) | [terraform/07](../teaching/terraform/07-maintaining-infrastructure.md), [terraform/06](../teaching/terraform/06-state-management.md#objective-6d-drift-and-state-management), [terraform/04](../teaching/terraform/04-configuration.md#objective-4g-custom-conditions) | [Lab 06](../labs/06-drift-and-import/README.md), [lab 07](../labs/07-tests-and-guardrails/README.md). Then rerun one failing step with `TF_LOG_PROVIDER=DEBUG` and `TF_LOG_PATH` set, find the API call in the log, and delete the log. Walk the [unexpected drift runbook](../runbooks/terraform-unexpected-drift.md) against the drift you created in lab 06. |
| 5 | HCP Terraform (domain 8), multiple providers (2c), review | [terraform/08](../teaching/terraform/08-hcp-terraform.md), [terraform/02](../teaching/terraform/02-terraform-fundamentals.md#objective-2c-multiple-provider-configurations), [blueprint](terraform-associate-blueprint.md) | [Lab 08](../labs/08-detection-baseline/README.md). Then create an HCP Terraform organization on the free edition **(verify)**, add a `cloud` block to a configuration that uses only the `random` provider, run `terraform login` and `terraform init`, and trigger a run; look at where the state, variables, and run history live. Work HashiCorp's [sample questions](https://developer.hashicorp.com/terraform/tutorials/certification-004/associate-questions-004). Re-read the pitfalls section of every Terraform teaching note. |

[terraform/09 Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md) and the four Terraform runbooks are not exam content. Read them for the job and for SCS-C03, after the exam if time is short. The [blueprint](terraform-associate-blueprint.md#in-this-repo-but-not-on-the-exam) lists what falls outside the exam.

## How to use the notes

- Each teaching note has one `## Objective` heading per exam objective. Tick objectives off against the [blueprint](terraform-associate-blueprint.md), not chapters.
- Read the teaching note, then answer its self-check questions **without** looking. Anything you miss goes on a list.
- Use cheatsheets for spaced review. Cover the right-hand column of a table and recite it. The [CLI cheatsheet](../cheatsheets/terraform-cli.md) rewards this most: many questions come down to what one command or flag does.
- Do the labs, including every "Break it" step. Predict the plan output before you run the command, then compare. Reading a plan is the skill the exam and the job share.
- Type the configuration when you repeat a lab rather than copying the finished files. Syntax questions are easy only if your hands know the syntax.

## Question technique

The exam is one hour of true or false, multiple choice, and multiple answer questions. HashiCorp says the questions are not meant to trick you, so read for what a thing does, not for a catch.

- **Separate what a command reads from what it changes.** For each command ask three things: does it change real infrastructure, does it change state, does it change files in the working directory? `terraform fmt` rewrites files only. `terraform validate` checks the configuration without touching remote services or state. `terraform plan` proposes and changes nothing. `terraform import`, `terraform state mv`, and `terraform state rm` change state and leave infrastructure alone. `terraform apply -refresh-only` updates state to match reality and leaves infrastructure alone. The teaching notes and the [state and backends cheatsheet](../cheatsheets/terraform-state-and-backends.md) mark which is which.
- **Forget is not destroy.** Removing a resource from state (`terraform state rm`, a `removed` block) leaves the real object running. Removing the `resource` block from configuration and applying destroys it. Expect both in answer lists.
- **Answer for Terraform 1.12.** The exam tests 1.12, and your installed version is probably newer. Where behaviour changed, the teaching notes say so: S3 state locking with `use_lockfile` against the older DynamoDB table ([terraform/06](../teaching/terraform/06-state-management.md#objective-6b-state-locking)), `import`, `moved`, and `removed` blocks against their CLI equivalents, `terraform refresh` against `-refresh-only`, ephemeral values and write-only arguments ([terraform/04](../teaching/terraform/04-configuration.md#objective-4h-sensitive-data-and-vault)). Prefer the current, declarative form when two answers both work, and do not pick a feature that arrived after 1.12.
- **`sensitive` hides, it does not encrypt.** A sensitive value is redacted from CLI output and still written to state in plain text. Questions on secrets usually turn on that, and on what does keep a value out of state.
- **Recognize HCP Terraform features by name.** Domain 8 asks what a feature is for, not how to click through it: workspaces against projects, variable sets, the three run workflows (VCS-driven, CLI-driven, API-driven), policy enforcement with Sentinel or OPA, run tasks, the private registry, dynamic provider credentials, health assessments. Know that an HCP Terraform workspace is not a CLI workspace, and that the product was called Terraform Cloud in older material.
- **Multiple answer questions state how many to pick.** Pick exactly that many. Eliminate the options that describe a different command first.
- **True or false questions hinge on one word.** Look for "always", "only", "must", and "automatically", and test the statement against one counterexample.
- **Version constraints and module sources are small tables worth memorizing.** What `~> 6.2` allows, which module sources accept a `version` argument, and what the dependency lock file does and does not pin.

## Lab safety

The [labs](../labs/README.md) run against floci, a local AWS emulator, with fake credentials. They cost nothing and cannot touch a real account. The emulator is also more forgiving than AWS, so a passing lab proves less than it seems to:

- **IAM is not enforced by default.** A lab policy that is wrong still "works". Lab 04 says how it demonstrates least privilege without enforcement.
- **No eventual consistency, quotas, or throttling.** Real applies are slower and fail in ways the emulator does not.
- **Each lab's "What differs on real AWS" section** lists the specifics. Read it even if you never leave the emulator.

If you repeat a lab on real AWS:

- Use a dedicated sandbox account inside an organization you control, and set a budget alarm. The same rule as the [SCS-C03 plan](study-plan.md#lab-safety).
- `unset AWS_ENDPOINT_URL` first, or the AWS CLI keeps talking to the emulator while Terraform talks to AWS.
- Do not reuse a lab `providers.tf`. Remove the static `access_key` and `secret_key`, the `skip_*` flags, `s3_use_path_style`, and the `endpoints` block, and take credentials from the environment or an assumed role. See [AWS provider security](../cheatsheets/terraform-aws-provider-security.md).
- Start with empty state. A `terraform.tfstate` left over from the emulator describes resources that do not exist in the real account.
- S3 bucket names are globally unique on real AWS; the lab names will collide. Add your own suffix.
- Run `terraform destroy` when you finish, then check the console. KMS keys are not deleted at once: they enter a waiting period and bill until it ends **(verify)**. A versioned or Object Lock bucket may refuse to delete until it is emptied.
- State now holds real identifiers and possibly real secrets. Keep it out of Git and treat a leak as the [state exposure runbook](../runbooks/terraform-state-exposure.md) describes.

## Combining with the SCS-C03 plan

The two plans overlap on SCS-C03 skill 6.2.1 (IaC deployment) and reinforce each other elsewhere.

- **Doing both, Terraform first (recommended):** five weeks of this plan, then the eight-week [SCS-C03 plan](study-plan.md) with its "Do" exercises written as Terraform where that is practical. Thirteen weeks in all. The SCS exercises that prove a policy holds, such as the permissions boundary in week 1, need a real sandbox account, because the emulator does not enforce IAM.
- **Doing both in parallel:** about 11–14 hours a week for eight weeks. Pair the weeks so the Terraform labs build what the SCS reading explains:

| SCS-C03 week | Terraform work alongside it |
|---|---|
| 1–2 (IAM) | Weeks 1–2 of this plan, then [lab 04](../labs/04-iam-least-privilege/README.md) |
| 3–4 (data protection) | Week 3 of this plan; [lab 05](../labs/05-kms-and-secrets/README.md) matches the KMS and secrets reading |
| 5 (detection) | [Lab 08](../labs/08-detection-baseline/README.md) |
| 6–7 (infrastructure security, incident response) | Week 4 of this plan, plus the four Terraform [runbooks](../runbooks/README.md) |
| 8 (governance) | Week 5 of this plan and [terraform/09](../teaching/terraform/09-securing-terraform-on-aws.md), which is the Terraform side of skill 6.2.1 |

- **SCS-C03 only:** skip this plan. Read [terraform/09](../teaching/terraform/09-securing-terraform-on-aws.md) in SCS week 8 and do [lab 01](../labs/01-first-apply/README.md) and [lab 02](../labs/02-remote-state/README.md) so the note has something to attach to.
