# NIST SP 800-53 control impact mappings

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **SCS-C03:** 6.3.1, 6.3.2 · **Teaching note:** [Domain 6](../teaching/06-security-foundations-and-governance.md#task-63-evaluate-compliance)

These mappings connect AWS service configurations to the 800-53 controls they affect. They answer three questions:

1. **Forward:** I am enabling or changing this AWS feature. Which controls does it touch?
2. **Reverse:** I need to address this control. Which AWS configurations help, and what evidence do they produce?
3. **Impact:** If this configuration is missing or is removed, which controls are weakened and how?

## Files

| File | Organized by | Use for |
|---|---|---|
| [by-family.md](by-family.md) | Control family, then control | Writing SSP implementation statements; reverse lookup |
| [services/identity.md](services/identity.md) | IAM, Identity Center, Organizations policies, Cognito, Access Analyzer | Forward lookup and change impact |
| [services/data-protection.md](services/data-protection.md) | KMS, S3, EBS, RDS, Secrets Manager, ACM, Backup, Macie | |
| [services/network.md](services/network.md) | VPC, security groups, Network Firewall, WAF, Shield, endpoints, hybrid | |
| [services/logging-detection.md](services/logging-detection.md) | CloudTrail, CloudWatch, Config, GuardDuty, Security Hub, Detective, Security Lake | |
| [services/compute.md](services/compute.md) | EC2, Systems Manager, Inspector, containers, Lambda, pipelines | |
| [services/governance.md](services/governance.md) | Organizations, Control Tower, CloudFormation, Audit Manager, incident response tooling | |
| [services/iac-terraform.md](services/iac-terraform.md) | Terraform pipelines: source control, state storage, deployment credentials, providers and modules, pre-deployment checks, drift | |
| [control-impact-matrix.csv](control-impact-matrix.csv) | One row per configuration-control pair | Filtering, pivoting, importing into a GRC tool |

The CSV is generated. Edit the tables in `services/`, then run `scripts/build-control-matrix.sh`. Do not edit the CSV by hand.

## Read this before relying on a mapping

- **A mapping is not a compliance determination.** It says a configuration *can contribute* to a control. Whether the control is satisfied depends on your system boundary, your organization-defined parameters, your procedures, and your assessor.
- **Almost no control is met by technology alone.** Each family's `-1` control (policy and procedures) and most others need documented process. The mappings cover the technical part.
- **Mappings are many-to-many and partial.** One configuration touches several controls; one control needs several configurations.
- **These are practitioner notes, not an authoritative crosswalk.** Cross-check against AWS's own material: the NIST 800-53 Rev. 5 standard in Security Hub, the Config conformance pack "Operational Best Practices for NIST 800-53 rev 5", and the Audit Manager NIST 800-53 framework.
- **FedRAMP** baselines are built from 800-53 with their own parameters. Authorized Regions and services matter there; this repo does not track that.

## Shared responsibility as control inheritance

| Control origin | Meaning | Example | Your evidence |
|---|---|---|---|
| **Inherited** | AWS implements it fully | PE family (physical and environmental protection) for AWS data centers; MA and MP for AWS hardware | AWS reports from Artifact (SOC 2, ISO 27001, FedRAMP package) |
| **Shared** | AWS implements part; you implement part | SC-7: AWS protects its network; you configure VPCs and security groups. CM-6: AWS configures hosts; you configure guests and services. CP-9: AWS provides durable storage; you configure backups. | Artifact for AWS's part; your configuration and records for yours |
| **Customer** | You implement it using AWS features or otherwise | AC-2 account management in IAM; AU-6 log review; IR-4 incident handling | Your configuration, procedures, and records |

The more managed the service, the more you inherit. On EC2 you own the operating system (SI-2, CM-6, CM-7 at the guest level). On Lambda or S3, AWS does.

## Impact types

Each mapping row carries one of these:

| Type | Meaning | How to use it in an SSP |
|---|---|---|
| **Implements** | The configuration is a technical mechanism that directly enforces part of the control's requirement | Cite it in the implementation statement as the mechanism |
| **Supports** | The configuration helps meet the control but depends on process or other mechanisms to do so | Cite it as a contributing capability; describe the process around it |
| **Evidence** | The configuration produces records or reports an assessor can examine for this control | List it as an evidence source |

## Row format

Service files use this table layout:

| Column | Content |
|---|---|
| **Configuration** | A specific, checkable setting or feature, not a whole service |
| **Controls** | 800-53 Rev. 5 IDs. Enhancements in parentheses: `AC-6(9)`. |
| **Type** | Implements, Supports, or Evidence |
| **If absent or misconfigured** | The concrete weakness: what an attacker or auditor would find |
| **Evidence** | Where proof comes from |
| **Automated check** | AWS Config managed rule name, and Security Hub control ID where known **(verify)** |

Config rule names and Security Hub control IDs change over time. Treat them as pointers and confirm in the current documentation.

## Using mappings for change impact

When reviewing a change (CM-3, CM-4), look up each configuration the change touches in the service file:

1. List the controls in its row.
2. Read "If absent or misconfigured" to see what the change would weaken if it removes or loosens the setting.
3. Check whether a compensating configuration in the same control's row in [by-family.md](by-family.md) remains in place.
4. Note which evidence sources will change, so continuous monitoring (CA-7) is not broken.

Example: a proposal to move an S3 bucket from SSE-KMS with a customer managed key to SSE-S3.

| Control | Impact |
|---|---|
| SC-28, SC-28(1) | Still met: data remains encrypted at rest |
| SC-12 | Weakened: key lifecycle is no longer under organizational control |
| AC-3 | Weakened: the key policy no longer acts as a second access control on the data |
| AU-2, AU-12 | Weakened: per-use KMS events in CloudTrail disappear |
| IR-4 | Weakened: disabling the key is no longer available as a containment step |

## Using mappings in the other direction

To write an implementation statement for a control:

1. Find the control in [by-family.md](by-family.md).
2. Pick the configurations that are deployed in your boundary.
3. For each, record where it is enforced (organization policy, account baseline, workload) and its evidence source.
4. State the process that surrounds it: who reviews, how often, what happens on failure.
5. Identify the inherited portion and cite the AWS report.

## Automating evidence

| Tool | Role |
|---|---|
| Security Hub CSPM, NIST SP 800-53 Rev. 5 standard | Continuous control checks with per-resource status |
| Config conformance pack for NIST 800-53 rev 5 | Config rules grouped by control, deployable across the organization |
| Audit Manager, NIST 800-53 Rev. 5 framework | Collects Config, Security Hub, and CloudTrail evidence into an assessment, organized by control |
| Config aggregator and advanced queries | Point-in-time inventory and configuration answers (CM-8) |
| CloudTrail Lake | Who-did-what evidence over long periods |
| Artifact | AWS reports for inherited controls |

## Baseline notation

Where [by-family.md](by-family.md) shows a baseline, **L**, **M**, and **H** mean the control is selected in the NIST SP 800-53B Low, Moderate, or High baseline. Shown for base controls only and from memory of 800-53B; confirm against the published baselines before use **(verify)**.
