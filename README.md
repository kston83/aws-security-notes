# AWS Security Notes

Version-controlled working notes for a security practitioner on an AWS team. The repo holds four kinds of material, each with a different job:

| Folder | What it is | Use it when |
|---|---|---|
| [`exam/`](exam/) | Blueprint alignment for AWS Certified Security – Specialty (SCS-C03) and the security content of related AWS certifications | Planning study, checking coverage |
| [`teaching/`](teaching/) | Long-form teaching notes, one per SCS-C03 domain: mental models, worked examples, pitfalls, self-check questions | Learning or teaching a topic |
| [`cheatsheets/`](cheatsheets/) | Dense quick reference: decision tables, limits, policy snippets, CLI commands | You know the topic and need the fact |
| [`runbooks/`](runbooks/) | Step-by-step incident response procedures with commands | Something is on fire |
| [`control-mappings/`](control-mappings/) | NIST SP 800-53 Rev. 5 control impact mappings per AWS service and configuration | Writing an SSP, answering an auditor, assessing a change |

## Start here

- **Studying for SCS-C03:** [exam/scs-c03-blueprint.md](exam/scs-c03-blueprint.md) maps every task statement to notes in this repo. [exam/study-plan.md](exam/study-plan.md) sequences them.
- **Holding or pursuing another AWS cert:** [exam/related-certifications.md](exam/related-certifications.md) shows which notes cover its security content.
- **On call:** [runbooks/README.md](runbooks/README.md) has the index and the first-five-minutes checklist.
- **Compliance work:** [control-mappings/README.md](control-mappings/README.md) explains the mapping method; [control-mappings/control-impact-matrix.csv](control-mappings/control-impact-matrix.csv) is the filterable dataset.

## Contents

### Teaching notes

| # | Domain | SCS-C03 weight | Note |
|---|---|---|---|
| 1 | Detection | 16% | [teaching/01-detection.md](teaching/01-detection.md) |
| 2 | Incident Response | 14% | [teaching/02-incident-response.md](teaching/02-incident-response.md) |
| 3 | Infrastructure Security | 18% | [teaching/03-infrastructure-security.md](teaching/03-infrastructure-security.md) |
| 4 | Identity and Access Management | 20% | [teaching/04-identity-and-access-management.md](teaching/04-identity-and-access-management.md) |
| 5 | Data Protection | 18% | [teaching/05-data-protection.md](teaching/05-data-protection.md) |
| 6 | Security Foundations and Governance | 14% | [teaching/06-security-foundations-and-governance.md](teaching/06-security-foundations-and-governance.md) |

### Cheatsheets

- [IAM policy evaluation](cheatsheets/iam-policy-evaluation.md)
- [Organization policies: SCPs, RCPs, declarative policies](cheatsheets/org-policies-scp-rcp.md)
- [KMS](cheatsheets/kms.md)
- [S3 security](cheatsheets/s3-security.md)
- [Network security](cheatsheets/network-security.md)
- [Logging sources](cheatsheets/logging-sources.md)
- [Security services at a glance](cheatsheets/security-services-at-a-glance.md)
- [CLI one-liners](cheatsheets/cli-oneliners.md)

### Runbooks

- [Compromised IAM credentials](runbooks/compromised-iam-credentials.md)
- [Compromised EC2 instance](runbooks/compromised-ec2-instance.md)
- [S3 data exposure](runbooks/s3-data-exposure.md)
- [GuardDuty finding triage](runbooks/guardduty-finding-triage.md)
- [Root user activity](runbooks/root-user-activity.md)
- [CloudTrail tampering](runbooks/cloudtrail-tampering.md)
- [KMS key scheduled for deletion](runbooks/kms-key-scheduled-deletion.md)
- [Ransomware and data destruction](runbooks/ransomware-data-destruction.md)

### NIST 800-53 control impact mappings

- [Method and how to read a mapping](control-mappings/README.md)
- [By control family](control-mappings/by-family.md)
- By service group: [identity](control-mappings/services/identity.md), [data protection](control-mappings/services/data-protection.md), [network](control-mappings/services/network.md), [logging and detection](control-mappings/services/logging-detection.md), [compute](control-mappings/services/compute.md), [governance](control-mappings/services/governance.md)
- [Control impact matrix (CSV)](control-mappings/control-impact-matrix.csv)

## Accuracy and currency

AWS changes constantly. Every note carries a `Last reviewed` date in its header. Treat anything older than six months as needing a check against AWS documentation before you rely on it for a production decision or an audit response. Limits, defaults, and supported-service lists go stale fastest; the notes mark those with **(verify)**.

These notes are not authoritative for compliance. Control mappings describe how an AWS configuration can support a control. Whether a control is satisfied in your system is a determination for your assessor.

## Maintaining the repo

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions, templates, and the review cadence.

| Script | Purpose |
|---|---|
| `scripts/check-links.sh` | Verifies every relative link and heading anchor. Run before committing. |
| `scripts/build-control-matrix.sh` | Regenerates `control-mappings/control-impact-matrix.csv` from the tables in `control-mappings/services/`. Run after editing a mapping. |

Both need Bash; the matrix script needs GNU awk (included with Git for Windows).
