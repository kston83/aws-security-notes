# Runbooks

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 2.1.1, 2.2.1–2.2.5 · **Teaching note:** [Domain 2](../teaching/02-incident-response.md)

Step-by-step procedures for specific security events. Each follows the same phases: triage, contain, preserve evidence, investigate, eradicate, recover, and follow up.

These are starting points. Adapt role names, account IDs, and escalation contacts to your environment, and test each one in a sandbox before you need it.

## Index

| Runbook | Trigger |
|---|---|
| [GuardDuty finding triage](guardduty-finding-triage.md) | Any GuardDuty finding; routes to the others |
| [Compromised IAM credentials](compromised-iam-credentials.md) | Leaked or misused access key, role session, or password |
| [Compromised EC2 instance](compromised-ec2-instance.md) | Malware, crypto mining, C2 traffic, unexpected processes |
| [S3 data exposure](s3-data-exposure.md) | Public bucket, unexpected external access, suspected exfiltration |
| [Root user activity](root-user-activity.md) | Root sign-in or API call |
| [CloudTrail tampering](cloudtrail-tampering.md) | Logging stopped, trail changed, detective service disabled |
| [KMS key scheduled for deletion](kms-key-scheduled-deletion.md) | `ScheduleKeyDeletion` or `DisableKey` on a key in use |
| [Ransomware and data destruction](ransomware-data-destruction.md) | Mass deletion or encryption of data, ransom note |

New runbooks start from [_template.md](_template.md).

## First five minutes

1. **Open a record.** Ticket or incident channel. Note the time, the trigger, and who is responding. Everything you do goes here with a timestamp.
2. **Confirm it is real enough to act on.** Check the resource exists, who owns it, and whether the activity is expected. Do not spend long: if in doubt, treat it as real.
3. **Assess severity.**

| Severity | Examples | Response |
|---|---|---|
| Critical | Active data exfiltration; root or admin credentials compromised; ransomware; logging disabled by an unknown actor | Page the incident commander now. Contain immediately. |
| High | Compromised workload credentials; compromised production instance; public exposure of sensitive data | Contain within the hour |
| Medium | Compromised non-production resource; policy violation without evidence of misuse | Same business day |
| Low | Reconnaissance; blocked attempts | Review and tune |

4. **Assume the responder role** in the affected account from the security account. Do not use the credentials or resources under investigation.
5. **Go to the specific runbook.**

## Principles

- **Contain before you investigate in depth**, but **preserve evidence before you destroy anything**. Deactivate, isolate, and snapshot. Do not delete or terminate until the investigation is closed.
- **Prefer reversible actions.** Deactivate a key rather than delete it. Disable a KMS key rather than schedule deletion. Attach a deny rather than remove a policy.
- **Temporary credentials outlive the thing that issued them.** After dealing with a user or key, revoke role sessions.
- **Assume persistence.** One compromised credential usually means the attacker created others.
- **Stay out of band.** If the account may be compromised, do not coordinate through resources in that account.
- **Check every Region.** Attackers use the ones you do not watch.
- **Write it down as you go.** The timeline is the most valuable product of the response.

## Authority to act

Decide these before an incident and record the answers here:

| Action | Who may authorize |
|---|---|
| Deactivate a user's credentials | On-call responder |
| Isolate a non-production instance | On-call responder |
| Isolate a production instance | _name or role_ |
| Attach the quarantine SCP to an account | _name or role_ |
| Disable a KMS key used by production | _name or role_ |
| Engage AWS Support or AWS Security Incident Response | _name or role_ |
| Notify customers or regulators | _name or role_ |

## Prerequisites

The runbooks assume these exist. If they do not, building them is the first job.

- [ ] Responder role in every account, assumable from the security account with MFA
- [ ] Organization trail and flow logs delivering to the log archive account
- [ ] Athena table or CloudTrail Lake event data store over CloudTrail
- [ ] GuardDuty and Security Hub with a delegated administrator
- [ ] Isolation security group in every VPC (no inbound or outbound rules)
- [ ] Quarantine SCP created, not attached
- [ ] Evidence bucket with Object Lock in a forensics account, and a KMS key for evidence
- [ ] SSM agent on instances, with an instance profile allowing Run Command
- [ ] Alternate security contact set on every account
- [ ] Escalation contacts and AWS Support access confirmed

## After every incident

- Complete the timeline and root cause within a week.
- Record each control that failed or was missing and assign a fix with an owner and date.
- Update the runbook you used.
- Map the gap to a control if you maintain an SSP. See [control mappings](../control-mappings/README.md). Incident handling itself supports IR-4, IR-5, and IR-6.
