# Domain 2: Incident Response

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 2.1.1–2.1.4, 2.2.1–2.2.5 (14%) · **Related:** [runbooks](../runbooks/README.md), [CLI one-liners](../cheatsheets/cli-oneliners.md), [governance mappings](../control-mappings/services/governance.md)

## Why this matters

In the cloud, both attacker and responder work through APIs. An attacker with a valid key can enumerate, persist, and exfiltrate in minutes. The responder has the same speed available, but only if access, tooling, and procedure were set up before the incident. Most of this domain is about what you did last quarter.

## Mental model

The lifecycle follows NIST SP 800-61 and the AWS Security Incident Response Guide:

```
 PREPARE  ->  DETECT & ANALYZE  ->  CONTAIN  ->  ERADICATE  ->  RECOVER  ->  LEARN
    ^                                                                          |
    +--------------------------------------------------------------------------+
```

Two rules decide most exam questions here:

1. **Contain first, but do not destroy evidence.** Isolate the instance; do not terminate it. Deactivate the key; do not delete it until the investigation is done. Snapshot before you change anything.
2. **Revoking temporary credentials is different from revoking long-term ones.** Deleting or disabling an access key does nothing to role sessions already issued. Those need a session revocation policy.

AWS incidents fall into three domains, and the domain tells you which tools apply:

| Domain | Example | Respond with |
|---|---|---|
| **Service** | Leaked access key, public bucket, altered IAM policy | AWS APIs only: IAM, S3, Organizations |
| **Infrastructure** | Compromised EC2 instance, malicious container | AWS APIs plus OS-level forensics: snapshots, memory capture, isolation |
| **Application** | SQL injection, logic abuse | Application logs, WAF, code fix |

## Task 2.1: Plan and test

### Runbooks and playbooks

A runbook is a procedure for a specific scenario with the actual commands. Good ones state the trigger, the decision points, who has authority to take disruptive action, and what evidence to keep. The [runbooks](../runbooks/README.md) in this repo follow that shape.

Where runbooks live and execute on AWS:

| Tool | Role |
|---|---|
| **Systems Manager OpsCenter** | Aggregates operational and security issues as OpsItems with related resources and attached runbooks |
| **Systems Manager Incident Manager** | Response plans, escalation, on-call contacts, chat channels, timelines |
| **Systems Manager Automation** | Executable runbooks (documents) with approval steps; AWS provides many prebuilt ones |
| **SageMaker AI notebooks / Jupyter** | Interactive investigation playbooks: query Athena, enrich, visualize, with the narrative alongside |
| **AWS Security Incident Response** | Managed service for case handling and triage, with access to the AWS Customer Incident Response Team |

### Preparation

| Area | What to have in place |
|---|---|
| **Access** | A responder role in every account, deployed by StackSets, assumable from the security account, with MFA and its own alerting. A break-glass path that does not depend on the IdP. |
| **Logging** | Organization trail, flow logs, Resolver logs, all landing in the log archive. See [teaching/01](01-detection.md). |
| **Forensic environment** | A forensics account or VPC with no internet path, pre-built analysis AMIs, an evidence bucket with Object Lock, a KMS key for evidence |
| **Containment tooling** | A pre-created isolation security group in every VPC. A quarantine SCP ready to attach. Automation documents tested. |
| **Blast radius** | Workloads in separate accounts. Least-privilege roles. No long-term keys. IMDSv2 required. |
| **Contacts** | Alternate security contact set on every account. AWS Support plan level known. Escalation list current. |
| **DDoS** | Shield Advanced on internet-facing resources where justified, with Route 53 health checks associated, and Shield Response Team access configured in advance |
| **Backups** | AWS Backup with a vault in a separate account, Vault Lock, and tested restores |

The quarantine SCP is a deny-all policy with an exception for the responder role. Attaching it to a compromised account's OU stops every principal in the account, including ones the attacker created.

### Testing the plan

| Method | What it validates |
|---|---|
| Tabletop exercise | Roles, decisions, communication |
| Simulation / game day | Tooling, access, runbooks, under realistic signals. GuardDuty sample findings and open-source attack simulators generate the signals. |
| **AWS Fault Injection Service** | Controlled failure experiments: does detection fire, does automated recovery work |
| **AWS Resilience Hub** | Assesses a workload against RTO and RPO targets and recommends tests and alarms |
| Restore tests | That backups are usable. AWS Backup restore testing automates this. |

Every exercise ends with changes to runbooks. That is the Learn step.

### Automated response

The common shape:

```
Finding (GuardDuty / Security Hub / Config)
   -> EventBridge rule
      -> Lambda                      (single quick action)
      -> Step Functions              (multi-step, branching, human approval)
      -> SSM Automation runbook      (act on instances and resources, cross-account)
```

| Tool | Use |
|---|---|
| **Lambda** | Single-purpose actions: swap a security group, deactivate a key, tag a resource |
| **Step Functions** | Orchestration with branching, waits, parallel steps, approval gates |
| **Systems Manager Automation** | Prebuilt and custom runbooks; target of Config remediation; multi-account and multi-Region execution |
| **Config remediation** | Fix noncompliant resources automatically or on approval, through an Automation document |
| **Security Hub automation rules and custom actions** | Modify findings in bulk; send selected findings to EventBridge on analyst request |
| **Automated Forensics Orchestrator for Amazon EC2** | AWS solution that captures disk and memory evidence and isolates the instance through a Step Functions workflow |
| **Amazon Application Recovery Controller** | Shifts traffic away from an impaired zone or Region (zonal shift, routing controls) to recover availability |

Automate containment that is safe and reversible, such as tagging, snapshotting, and notifying. Put a human approval in front of anything that takes a production workload offline unless the business has accepted that trade.

## Task 2.2: Respond

### Capturing evidence

Order matters. Volatile data first.

| Artifact | How | Notes |
|---|---|---|
| Instance metadata | `describe-instances`, tags, IAM role, security groups, ENIs | Record before changing anything |
| Memory | SSM Run Command with a memory acquisition tool, written to the evidence bucket | Lost on stop or terminate. Needs tooling in place beforehand. |
| Disk | EBS snapshots of all volumes | Copy to the forensics account. Encrypted volumes need the key shared. |
| Instance store | Copy off before stop | Lost on stop |
| Logs | CloudTrail, flow logs, Resolver logs, OS and application logs | Already in the archive if you prepared |
| Console output and screenshot | `get-console-output`, `get-console-screenshot` | |

Then protect the instance from accidental loss: enable termination protection, set shutdown behavior to stop, detach it from its Auto Scaling group, and deregister it from load balancers.

Store evidence in a dedicated bucket with Object Lock and restricted access, and keep a record of who collected what and when. That record is your chain of custody.

### Containment techniques

**Network containment of an instance.** Replace its security groups with an isolation group that has no inbound and no outbound rules.

There is a catch: security groups are stateful, and **existing tracked connections are not cut** when you remove the rule that allowed them. An attacker's established session can survive. To cut it, either apply a deny in the subnet's network ACL, which is stateless and takes effect on every packet, or use the two-step approach: first switch to a group that makes connections untracked (allow all in and out), then switch to the empty isolation group.

**Credential containment.**

| Credential type | Action |
|---|---|
| IAM user access key | Deactivate (`update-access-key --status Inactive`). Reversible. Delete after the investigation. |
| IAM user console access | Delete the login profile, deactivate MFA devices the attacker may have added |
| Role session credentials (instance role, assumed role, federated) | Attach an inline deny with `aws:TokenIssueTime` earlier than now. The console's "Revoke active sessions" does this. New sessions still work; stolen ones do not. |
| Root user | Change the password, rotate MFA, delete any root access keys; for member accounts, use centralized root access management |
| Database, application, or API secrets | Rotate in Secrets Manager |
| KMS key misuse | Disable the key or revoke grants. Disabling is reversible. |

**Account containment.** Attach the quarantine SCP. Remember SCPs do not affect the management account, which is one reason nothing should run there.

**Data containment.** Turn on S3 Block Public Access at the account level, remove the offending policy statement, or apply an explicit deny bucket policy.

### Searching and correlating

Start from what you know and pivot:

1. **The principal.** Query CloudTrail by access key ID or by role session. What did it call, from where, with what user agent?
2. **Persistence.** Look for `CreateUser`, `CreateAccessKey`, `CreateLoginProfile`, `AttachUserPolicy`, `PutRolePolicy`, `UpdateAssumeRolePolicy`, `CreateRole`, new Lambda functions, new EC2 key pairs, new identity providers.
3. **Defense evasion.** `StopLogging`, `DeleteTrail`, `PutEventSelectors`, `DeleteDetector`, `DisableSecurityHub`, `DeleteFlowLogs`.
4. **Impact.** `RunInstances` in unused Regions, `GetObject` volume, `DeleteObject`, snapshot sharing, `ScheduleKeyDeletion`.
5. **Role chaining.** Each `AssumeRole` event links a source identity to new session credentials. Follow `sharedEventID` and the session's access key ID across accounts.

Tools: CloudTrail Lake or Athena for breadth and history, Logs Insights for speed on recent data, Detective for the visual pivot. Query examples are in the [CLI one-liners](../cheatsheets/cli-oneliners.md).

### Validating findings

A finding is a hypothesis. Before disruptive action, confirm:

- Is the resource real, and who owns it? Check tags and the account.
- Is the activity expected? A penetration test, a new deployment, a scanner.
- Does independent evidence agree? A GuardDuty exfiltration finding should match CloudTrail and flow logs.
- What is the scope? One instance or the whole Auto Scaling group; one key or the role every instance uses.

The detail is in [GuardDuty finding triage](../runbooks/guardduty-finding-triage.md).

### Eradication and recovery

- Remove everything the attacker created: users, keys, roles, policies, functions, instances, resource policy statements, identity providers.
- Rebuild compute from a known-good image. Do not clean a compromised host and return it to service.
- Patch the entry point: the vulnerable application, the over-permissive policy, the exposed key.
- Restore data from backups taken before the compromise. Verify integrity before reconnecting.
- Rotate every secret the compromised resource could read.
- Watch closely afterward. Attackers return.

### Root cause analysis

**Amazon Detective** builds a behavior graph from CloudTrail, VPC Flow Logs, GuardDuty findings, and EKS audit logs. From a finding you can see the entity's activity over time, what is new or unusual against its baseline, related findings grouped together, and which other resources it touched. It answers "what else did this principal do" without writing queries.

RCA output: a timeline, the initial access vector, each control that failed or was missing, and specific changes with owners. Write it without blame so people report honestly.

## Worked examples

**1. A developer reports pushing an access key to a public repository an hour ago.**
Deactivate the key now. Query CloudTrail for that access key ID since the push. Look for persistence: new users, keys, roles. Look for role assumptions made with the key and revoke those sessions. Remove what the attacker created, issue a new credential to the developer (preferably move them to Identity Center), then delete the old key. Full procedure: [compromised IAM credentials](../runbooks/compromised-iam-credentials.md).

**2. GuardDuty reports `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`.**
The instance role's credentials are being used from an external IP. Revoke the role's active sessions with the `aws:TokenIssueTime` deny. The instance will fetch new credentials and keep working. Then treat the instance as compromised, because the credentials got out somehow: SSRF against IMDSv1 is the classic path. Enforce IMDSv2.

**3. Put these in order: terminate the instance, snapshot the volumes, isolate with a security group, capture memory.**
Capture memory, snapshot volumes, isolate, and terminate only after the investigation. Many teams isolate first to stop active harm; that is defensible if outbound activity is causing damage. Terminate is always last.

## Pitfalls and exam traps

- Deleting an access key does not end sessions already obtained with it through `AssumeRole`.
- Stopping an instance loses memory and instance store data. Terminating loses everything not snapshotted.
- Changing a security group does not drop established, tracked connections.
- An instance in an Auto Scaling group may be terminated by a health check while you investigate. Detach it or move it to standby.
- Snapshots of volumes encrypted with the AWS managed key `aws/ebs` cannot be shared cross-account. Use a customer managed key, or copy and re-encrypt.
- You do not need AWS approval for penetration tests on a published list of services. DDoS simulation has its own policy and requirements.
- AWS notifications about abuse or exposed credentials go to the account's security contact. If it is unset, they go to the root email, which often nobody reads.

## Self-check

1. An attacker has temporary credentials from a role. Which action invalidates them without breaking the legitimate workload for more than a moment?
2. Why might an isolation security group fail to stop an attacker's active SSH session?
3. Name three API calls that indicate persistence in IAM.
4. What must exist before the incident for memory capture to be feasible?
5. Which service helps you answer "what else did this IP address interact with over the past month"?
6. Why attach a quarantine SCP rather than deleting the attacker's IAM user?
7. What should happen to a compromised EC2 instance after forensics are complete?

<details>
<summary>Answers</summary>

1. Add a deny-all policy to the role conditioned on `aws:TokenIssueTime` being before the current time (Revoke active sessions). The workload obtains fresh credentials automatically.
2. Security group changes do not terminate existing tracked connections. Use a NACL deny or first convert the connection to untracked.
3. Any three of: `CreateAccessKey`, `CreateUser`, `CreateLoginProfile`, `AttachUserPolicy`/`AttachRolePolicy`, `PutUserPolicy`/`PutRolePolicy`, `UpdateAssumeRolePolicy`, `CreateRole`, `CreateSAMLProvider`/`CreateOpenIDConnectProvider`.
4. SSM agent and an instance profile permitting Run Command, a memory acquisition tool available to deploy, and an evidence bucket the instance can write to.
5. Amazon Detective.
6. The SCP blocks every principal in the account at once, including persistence you have not found yet, and is reversible. Deleting one user leaves other footholds.
7. Terminate it and replace it from a known-good, patched image. Do not return it to service.

</details>

## Further reading

- [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/)
- [NIST SP 800-61](https://csrc.nist.gov/pubs/sp/800/61/r3/final)
- [AWS Customer Playbook Framework](https://github.com/aws-samples/aws-customer-playbook-framework)
