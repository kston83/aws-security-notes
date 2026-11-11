# Domain 6: Security Foundations and Governance

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 6.1.1–6.1.5, 6.2.1–6.2.4, 6.3.1–6.3.3 (14%) · **Related:** [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md), [root user runbook](../runbooks/root-user-activity.md), [governance mappings](../control-mappings/services/governance.md), [control mappings](../control-mappings/README.md)

## Why this matters

Individual controls do not scale. A team with two hundred accounts cannot configure each by hand, and it cannot prove compliance by logging in to look. Governance is the machinery that makes the secure configuration the default, stops drift from it, and produces evidence without anyone collecting screenshots.

## Mental model

**The account is the unit of isolation.** It is the strongest security boundary AWS offers: separate IAM namespace, separate resources, separate limits. Governance is about managing accounts as a fleet.

```
                      Organization root          <- SCPs, RCPs, declarative policies inherited downward
        ┌─────────────────┼─────────────────┐
   Security OU      Infrastructure OU    Workloads OU ── Prod OU, Non-prod OU
   - Log archive    - Network            Sandbox OU
   - Security       - Shared services    Suspended OU
     tooling

   Management account: billing and organization management only. No workloads.
```

Controls come in three kinds, plus the response that follows detection. Good governance uses all of them for the same requirement.

| Kind | When it acts | AWS mechanisms |
|---|---|---|
| **Preventive** | Blocks the action | SCPs, RCPs, declarative policies, IAM, resource policies |
| **Proactive** | Blocks noncompliant resources before deployment | CloudFormation hooks, Guard rules in pipelines, Access Analyzer custom checks |
| **Detective** | Finds it afterward | Config rules, Security Hub controls, GuardDuty, Access Analyzer |
| *Responsive* | Fixes it | Config remediation, EventBridge automation |

The **shared responsibility model** sits underneath: AWS secures the infrastructure that runs the services; you secure what you configure and put in them. The line moves with the service: more is yours on EC2 than on Lambda or S3. In control-mapping terms, AWS's part is what you *inherit*. See [control mappings](../control-mappings/README.md).

## Task 6.1: Accounts

### AWS Organizations

- **Management account:** creates the organization, pays the bills, and is **not restricted by SCPs or RCPs**. Keep workloads and day-to-day users out of it.
- **All features** mode is required for policies and for most security service integrations. Consolidated billing mode gives you neither.
- **OUs** group accounts by control requirements, not by org chart. Policies attach to the root, OUs, or accounts and inherit downward.
- **Trusted access** lets an AWS service operate across the organization. **Delegated administrator** lets a member account administer that service.
- Moving an account between OUs changes which policies apply immediately. A **suspended** OU with a deny-all SCP holds accounts awaiting closure.

Policy types:

| Type | Kind | Controls |
|---|---|---|
| Service control policy (SCP) | Authorization | Maximum permissions for principals in member accounts |
| Resource control policy (RCP) | Authorization | Maximum permissions on resources in member accounts, whoever the caller is |
| Declarative policy | Management | Enforces a service configuration baseline (EC2 and VPC settings) regardless of how the API is called |
| Tag policy | Management | Standardizes tag keys and values |
| Backup policy | Management | Deploys AWS Backup plans |
| AI services opt-out policy | Management | Stops AWS AI services from using your content for service improvement |

More on the first three: [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md).

### Control Tower

Control Tower builds and maintains a landing zone on top of Organizations:

- Creates the **log archive** and **audit** accounts, an organization trail, Config in every account, and IAM Identity Center.
- **Account Factory** provisions new accounts with the baseline. Account Factory for Terraform and Account Factory Customization extend it.
- **Controls** (guardrails) applied per OU:

| Behavior | Implemented with |
|---|---|
| Preventive | SCPs, RCPs, declarative policies |
| Detective | Config rules, Security Hub controls |
| Proactive | CloudFormation hooks |

| Guidance | Meaning |
|---|---|
| Mandatory | Always on; protects the landing zone itself |
| Strongly recommended | Optional; common best practice |
| Elective | Optional; for specific needs |

- **Region deny** control restricts which Regions can be used.
- **Drift:** changes made outside Control Tower, such as editing a managed SCP or moving an account in Organizations, are detected and must be resolved by repair or re-registration.
- **Existing environments:** you can set up Control Tower in an existing organization and **enroll** existing accounts and OUs. Enrolling applies the OU's controls, so check for conflicts first.
- **Custom controls:** deploy your own SCPs, Config rules, and resources through Customizations for AWS Control Tower or your own StackSets.

### Delegated administration

Run security services from a dedicated security tooling account, not from the management account.

| Service | Delegated admin gives you |
|---|---|
| GuardDuty, Security Hub, Inspector, Macie, Detective | Org-wide enablement, auto-enable for new accounts, central findings |
| Config | Organization aggregator, organization rules and conformance packs |
| IAM Access Analyzer | Organization-level analyzers |
| Firewall Manager | Central firewall policies |
| CloudTrail | Manage the organization trail and CloudTrail Lake |
| IAM Identity Center | Manage permission sets and assignments (except those for the management account) |
| CloudFormation StackSets | Deploy to OUs with service-managed permissions |
| Security Lake, Audit Manager, Backup | Central configuration and data |

Pattern: from the management account, enable trusted access and register the delegated administrator, once. Everything after that happens in the security account.

### Root user

Each account has a root user with unrestricted access that policies in the account cannot limit. (SCPs do limit member account root users.)

| Practice | Detail |
|---|---|
| **Centralize root access** | IAM's centralized root access management lets you remove root credentials from member accounts entirely and perform the few root-only tasks through short-lived, task-scoped privileged sessions from the management or delegated admin account. New member accounts are created without root credentials. |
| **MFA** | Required on root. Use phishing-resistant hardware keys, more than one, stored separately. |
| **No access keys** | Root should never have access keys. |
| **Management account root** | Cannot be centralized away. Protect with hardware MFA, a group mailbox, a strong password held in a vault, and dual control. |
| **Monitor** | Alert on any root sign-in or API use. See [root user runbook](../runbooks/root-user-activity.md). |
| **Contacts** | Set the alternate security contact so AWS notifications reach the security team. |

**Break-glass** is the documented emergency path when normal access fails, for example when the IdP is down. Design it with: a small number of emergency IAM users or roles outside the federation path, strong MFA, credentials sealed and split, alarms on every use, a regular test, and a post-use credential reset.

## Task 6.2: Deployment

### Infrastructure as code

IaC makes configuration reviewable, repeatable, and testable. Security checks run on the template before anything exists.

| Tool | Role |
|---|---|
| **CloudFormation StackSets** | Deploy a stack to many accounts and Regions. With **service-managed permissions**, target OUs and enable automatic deployment to accounts that join. This is how baseline roles, Config rules, and EventBridge rules get everywhere. |
| **cfn-lint** | Validates template syntax and resource properties |
| **CloudFormation Guard** | Policy as code: rules such as "every S3 bucket must have encryption configured." Runs in a pipeline, and the same language powers Config custom rules and hooks. |
| **CloudFormation hooks** | Proactive control: inspect a resource before create or update and fail the operation if noncompliant |
| **Stack policies, termination protection, drift detection** | Protect deployed stacks from unintended updates and deletion; find manual changes |
| **Third-party IaC** (Terraform and others) | Same principles: scan plans in the pipeline, protect state files (they contain secrets), least-privilege deployment roles |

Keep secrets out of templates. Use dynamic references to Secrets Manager or Parameter Store, and `NoEcho` for parameters.

### Tagging

Tags drive ownership, cost allocation, automation, and ABAC.

| Need | Mechanism |
|---|---|
| Consistent keys and values | Tag policies in Organizations |
| Require tags at creation | SCP or IAM deny when `aws:RequestTag/key` is absent (`Null` condition) |
| Find untagged resources | Config rule `required-tags`; Tag Editor |
| Stop tag tampering | Deny tag and untag actions on protected keys with `aws:TagKeys` |
| Act on groups of resources | Resource Groups; tag-based targets in Systems Manager, Backup, and Data Lifecycle Manager |

Tag policies report and optionally enforce formatting. They do not on their own force a tag to be present. That takes an SCP.

### Central enforcement

**Firewall Manager** deploys and maintains protections across the organization and applies them automatically to new accounts and resources.

- Prerequisites: Organizations with all features, a Firewall Manager administrator account, and AWS Config enabled in member accounts.
- Policy types: WAF, Shield Advanced, security groups (common baseline, content audit, unused and redundant cleanup), Network Firewall, Route 53 Resolver DNS Firewall, network ACLs, and third-party firewalls.
- It can auto-remediate noncompliant resources or only report them.

Other central mechanisms: Security Hub central configuration, GuardDuty and Inspector auto-enable, Config organization rules and conformance packs, backup policies, declarative policies.

### Sharing

| Service | Shares | Notes |
|---|---|---|
| **AWS RAM** | Subnets, transit gateways, Resolver rules, prefix lists, Private CAs, License Manager configurations, and more | Share with accounts, OUs, or the organization. Enabling sharing with Organizations removes invitations. The owner keeps control; participants use. |
| **Service Catalog** | Approved products (CloudFormation or Terraform templates) in portfolios | A **launch constraint** names a role used to provision, so users can launch a product without holding the underlying permissions. Template constraints limit parameters. |
| Resource-based policies | Buckets, keys, queues, and other resources | Scope with `aws:PrincipalOrgID` |

Shared VPC subnets through RAM let a network team own the VPC while workload accounts launch into it, keeping network control central.

## Task 6.3: Evaluate compliance

### Config

- The **configuration recorder** captures resource configurations and changes. Nothing in Config works without it.
- **Rules** evaluate resources: AWS managed, custom Lambda, or custom Guard. Triggered by configuration change, on a schedule, or both.
- **Remediation** runs a Systems Manager Automation document against a noncompliant resource, automatically or manually, with retries.
- **Conformance packs** bundle rules and remediations. Sample packs exist for many frameworks including NIST 800-53. Deploy organization-wide from the delegated administrator.
- **Aggregators** collect configuration and compliance from accounts and Regions into one view. Advanced queries run SQL over it.
- Config is Regional. Record global resources (IAM) in one Region to avoid duplicates.

Config rules are detective. A resource can be noncompliant for a while before remediation. If the requirement is "must never happen," add a preventive control.

### Security Hub standards

Security Hub CSPM runs **controls**, most of them backed by Config rules, grouped into **standards**: AWS Foundational Security Best Practices, CIS AWS Foundations Benchmark, PCI DSS, NIST SP 800-53 Rev. 5, and others. Each control has a status per resource, and each standard a score.

- Consolidated control findings give one finding per control across standards.
- Central configuration applies standards and controls to OUs from the delegated administrator.
- Disable controls that do not apply, with a reason, so scores mean something.
- Findings go to EventBridge for notification and automated remediation.

### Evidence

| Service | Provides |
|---|---|
| **AWS Audit Manager** | Continuously collects evidence against a framework's controls from Config, Security Hub, CloudTrail, and API snapshots. Prebuilt frameworks include NIST 800-53, PCI DSS, HIPAA, SOC 2, and CIS; you can build custom ones. Supports manual evidence, delegation of control review, and assessment reports. |
| **AWS Artifact** | AWS's own compliance reports (SOC, ISO, PCI attestation) and agreements such as the BAA. This is the evidence for the AWS side of shared responsibility: your *inherited* controls. |
| **Well-Architected Tool** | Structured review of a workload against the framework's pillars, including Security. Records risks, tracks an improvement plan and milestones. Custom lenses hold your own standards. |
| **Config** | Point-in-time and historical configuration: "what did this security group look like on 3 March?" |
| **CloudTrail** | Who did what, when |
| **Trusted Advisor** | Account-level best practice checks |

Audit Manager gathers evidence. It does not make you compliant and does not assess whether evidence is sufficient. Artifact is about AWS. Audit Manager is about you.

The Well-Architected Security pillar's design principles are worth memorizing: implement a strong identity foundation, maintain traceability, apply security at all layers, automate security best practices, protect data in transit and at rest, keep people away from data, and prepare for security events.

## Worked examples

**1. No account in the organization may use Regions outside two approved ones, except for global services.**
An SCP at the root denying all actions when `aws:RequestedRegion` is not in the list, with `NotAction` exempting global services (IAM, Organizations, Route 53, CloudFront, Support, and similar), and a condition exempting any roles that need to operate elsewhere. Or enable the Control Tower Region deny control.

**2. Every new account must have GuardDuty on, an IAM role for the security team, and a Config rule set, without manual steps.**
GuardDuty: delegated administrator with auto-enable. Role and Config rules: StackSets with service-managed permissions and automatic deployment targeting the OUs, or a conformance pack deployed to the organization.

**3. Developers must be able to launch an approved database configuration without having RDS or IAM permissions.**
A Service Catalog product with a launch constraint. The launch role holds the permissions; developers need only Service Catalog end-user access.

**4. An auditor needs evidence that encryption-at-rest controls operated over the last six months, mapped to NIST 800-53.**
An Audit Manager assessment using the NIST 800-53 Rev. 5 framework, scoped to the in-scope accounts, collecting Config and Security Hub evidence continuously. Export the assessment report. For AWS's physical and infrastructure controls, download the relevant reports from Artifact.

## Pitfalls and exam traps

- SCPs and RCPs do not apply to the management account. Declarative policies and others have their own scoping rules; read them.
- SCPs do not affect service-linked roles.
- An SCP attached to an OU affects every account beneath it, including nested OUs. Removing the default `FullAWSAccess` without a replacement allow denies everything.
- Config must be recording before Security Hub controls, Firewall Manager, and conformance packs function.
- Control Tower detective controls are Config rules and report only. Preventive controls block.
- Changing Control Tower-managed resources directly causes drift.
- Tag policies do not require tags to exist.
- Firewall Manager needs Config and an Organizations administrator account set from the management account.
- StackSets with self-managed permissions need roles created in each target account first. Service-managed permissions use Organizations and avoid that.
- Artifact holds AWS's reports, not yours.

## Self-check

1. Which accounts are unaffected by SCPs?
2. A requirement says S3 buckets must never be publicly readable. Give one preventive and one detective control.
3. What is needed before Firewall Manager can deploy a WAF policy across the organization?
4. How do you make sure a baseline CloudFormation stack is deployed to every account that joins an OU in future?
5. What is the difference between a Control Tower mandatory control and a strongly recommended control?
6. Where do you get AWS's SOC 2 report?
7. What replaces root user credentials in member accounts for tasks that once needed them?
8. A Config rule flags a noncompliant security group. How can it be fixed without a human?

<details>
<summary>Answers</summary>

1. The management account. (Also, service-linked roles in any account are not restricted.)
2. Preventive: S3 Block Public Access at the account or organization level, enforced so it cannot be turned off (SCP denying `s3:PutAccountPublicAccessBlock`), or an RCP. Detective: Config rule `s3-bucket-public-read-prohibited`, Security Hub control, or Access Analyzer external access findings.
3. Organizations with all features, a designated Firewall Manager administrator account, and AWS Config enabled in the accounts.
4. A StackSet with service-managed permissions and automatic deployment enabled, targeting the OU.
5. Mandatory controls are always enforced and cannot be disabled. Strongly recommended controls are optional and enabled per OU.
6. AWS Artifact.
7. Centralized root access management: privileged, task-scoped root sessions initiated from the management or delegated administrator account.
8. Configure automatic remediation on the rule with a Systems Manager Automation document.

</details>

## Further reading

- [Organizing Your AWS Environment Using Multiple Accounts](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/)
- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/)
- [Well-Architected Framework: Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [AWS Control Tower controls reference](https://docs.aws.amazon.com/controltower/latest/controlreference/)
