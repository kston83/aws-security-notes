# Control impact: governance and response tooling

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching notes:** [Domain 6](../../teaching/06-security-foundations-and-governance.md), [Domain 2](../../teaching/02-incident-response.md)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

## Organizations and account structure

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| All accounts in one organization with all features | CM-8, AC-2, PM-5 | I | Unmanaged accounts outside guardrails and monitoring | Account list | `account-part-of-organizations` |
| Workloads separated into accounts by environment and sensitivity | SC-7(21), AC-4, AC-5, SC-2 | I | One compromise or mistake reaches unrelated workloads | OU and account structure | Manual |
| Management account holds no workloads; access tightly limited | AC-6(5), SC-2, AC-5 | I | The one account exempt from SCPs carries day-to-day risk | Resource inventory of the management account | Manual |
| Dedicated log archive and security tooling accounts | AU-9(2), AU-9(4), AC-5 | I | Those being audited control the audit data | Account structure | Manual |
| Delegated administrators for security services | AC-6(1), AC-5, CA-7 | I | Security operations require the management account | Delegated administrator list | Manual |
| Suspended OU with deny-all SCP for closed or quarantined accounts | AC-2(3), IR-4 | I | Dormant accounts remain usable | OU and SCP | Manual |
| Alternate security contact on every account | IR-6, SI-5 | I | AWS security notifications reach nobody | Account contacts | `account-contact-details-configured` |

## Control Tower

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Landing zone with mandatory controls | CM-2, CM-6, AU-12, AU-9 | I | Baseline logging and guardrails depend on manual setup | Landing zone status | Control Tower drift status |
| Account Factory for all new accounts | CM-2, AC-2, CM-3 | I | New accounts start without the baseline | Provisioned product list | Manual |
| Preventive controls enabled per OU | AC-3, AC-6, CM-5, CM-7 | I | Prohibited actions merely detected, not blocked | Enabled controls | Control status |
| Detective controls enabled per OU | CM-6, CA-7 | I, E | Noncompliance not surfaced | Control compliance | Control status |
| Proactive controls (CloudFormation hooks) | CM-4, CM-6, SA-10 | I | Noncompliant resources deployed before detection | Hook results | Control status |
| Region deny control | CM-7, AC-3 | I | Activity in unmonitored Regions | Control status | Control status |
| Drift monitored and repaired | CM-3, CM-6, CA-7 | S | Guardrails silently altered | Drift notifications | SNS drift notifications |

## Deployment and change

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Infrastructure defined as code in version control | CM-2, CM-3, SA-10, CP-10 | I | No reviewable baseline; recovery by memory | Repository history | Manual |
| Changes deployed only through pipelines with approval | CM-3, CM-5, AC-5 | I | Unreviewed manual changes in production | Pipeline history; CloudTrail | Custom rule on console changes |
| StackSets with automatic deployment for baselines | CM-2, CM-6, CM-6(1) | I | Baseline resources missing in new accounts | StackSet instance status | Manual |
| Drift detection on stacks | CM-3, CM-6, SI-7 | S | Manual changes undetected | Drift results | `cloudformation-stack-drift-detection-check` |
| Stack termination protection and stack policies | CM-5, CP-10 | I | Critical stacks deleted or altered by accident | Stack settings | Manual |
| Service Catalog products with launch constraints | CM-7, AC-6, SA-15, CM-2 | I | Teams build nonstandard configurations with broad permissions | Portfolio and constraints | Manual |
| RAM sharing restricted to the organization | AC-21, AC-3, AC-4 | I | Resources shareable with arbitrary external accounts | RAM settings; SCP on `ram:RequestedAllowsExternalPrincipals` | Custom |
| Required tags enforced at creation | CM-8, AC-16, PM-5 | S | Resources without owner or classification | Tag compliance | `required-tags` |

## Compliance evidence

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Audit Manager assessment against NIST 800-53 Rev. 5 | CA-2, CA-7, AU-6, PM-6 | E | Evidence gathered by hand at audit time | Assessment reports | Manual |
| Artifact reports reviewed and filed | SA-9, CA-2 | E | No evidence for the provider's share of controls, including the inherited PE family | Downloaded reports; review record | Manual |
| Well-Architected reviews with improvement plans | SA-8, RA-3, CA-5, PL-8 | S, E | Architectural risk unassessed and untracked | Workload reviews; milestones | Manual |
| Security Hub NIST 800-53 standard enabled | CA-2, CA-7, CM-6 | I, E | No continuous per-control status | Standard score and findings | Security Hub |
| Conformance pack deployed organization-wide | CM-6, CA-7 | I, E | Rule coverage differs by account | Pack compliance | Config |

## Incident response tooling

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Responder role deployed to every account | IR-4, AC-2, AC-6 | I | Responders wait for access during an incident | StackSet; role inventory | Custom |
| Runbooks maintained and exercised | IR-4, IR-8, IR-3 | I | Response improvised | [Runbooks](../../runbooks/README.md); exercise records | Manual |
| Automated containment (EventBridge, Lambda, Step Functions, SSM Automation) | IR-4(1), SI-4(5) | I | Containment time depends on human availability | Automation definitions; execution history | Manual |
| Incident Manager response plans and contacts | IR-4, IR-6, IR-8, IR-5 | I | No defined escalation; incidents untracked | Plans; incident records | Manual |
| Isolation security group and quarantine SCP staged | IR-4, SC-7, AC-3 | I | Containment mechanisms built during the incident | Resource and policy inventory | Custom |
| Forensics account with locked evidence bucket | IR-4, AU-9, AU-11, SI-7 | I | Evidence stored where the attacker may reach it | Bucket configuration | Manual |
| AWS Security Incident Response or Support plan | IR-7 | S | No external assistance path | Membership or plan | Manual |
| Fault Injection Service and Resilience Hub exercises | IR-3, CP-4, CP-2 | S, E | Plans untested | Experiment and assessment results | Manual |
| AWS Backup restore testing | CP-4, CP-9(1), CP-10 | I, E | Recovery unproven | Test results | Backup Audit Manager |
