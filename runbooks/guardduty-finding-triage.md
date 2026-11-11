# GuardDuty finding triage

> **Last reviewed:** 2026-11-10 · **Severity:** by finding · **SCS-C03:** 1.1.4, 2.2.3 · **NIST 800-53:** SI-4, IR-4, IR-5, AU-6

## Trigger

A GuardDuty finding arrives through EventBridge, Security Hub, or the console.

## Read the finding type

```
ThreatPurpose : ResourceType / ThreatFamilyName . DetectionMechanism ! Artifact
     │               │                │                    │
     │               │                │                    └─ how it was detected (optional)
     │               │                └─ what the activity is
     │               └─ EC2, IAMUser, S3, Kubernetes, Lambda, RDS, Runtime
     └─ what the attacker is trying to do
```

| Threat purpose | Meaning | Rough ATT&CK tactic |
|---|---|---|
| `Recon` | Probing for weaknesses | Reconnaissance, Discovery |
| `UnauthorizedAccess` | Suspicious access or access pattern | Initial Access |
| `Backdoor` | Resource is compromised and contacting a controller | Command and Control |
| `Trojan` | Malicious software in use | Execution |
| `CryptoCurrency` | Mining activity | Impact |
| `Persistence` | Changes that keep access | Persistence |
| `PrivilegeEscalation` | Attempts to gain higher permissions | Privilege Escalation |
| `DefenseEvasion` | Attempts to avoid detection | Defense Evasion |
| `CredentialAccess` | Attempts to obtain credentials | Credential Access |
| `Discovery` | Enumeration of resources | Discovery |
| `Exfiltration` | Data leaving | Exfiltration |
| `Impact` | Disruption or destruction | Impact |
| `Stealth` | Hiding activity, for example by stopping logging | Defense Evasion |
| `Policy` | Behavior against security best practice | n/a |
| `Execution`, `AttackSequence` | Malware run; correlated multi-stage attack | Multiple |

`IAMUser` as the resource type covers all IAM principals, including roles and root.

## Severity

| Range | Label | Default handling |
|---|---|---|
| 9.0–10.0 | Critical | Attack sequence in progress. Respond immediately. |
| 7.0–8.9 | High | Resource is compromised and being used. Respond immediately. |
| 4.0–6.9 | Medium | Suspicious deviation. Investigate the same day. |
| 1.0–3.9 | Low | Attempted or blocked activity. Review in batch. |

## Triage

Pull the finding:

```bash
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty get-findings --detector-id "$DET" --finding-ids FINDING_ID
```

Answer these, from the finding JSON:

| Question | Field |
|---|---|
| Which account and Region? | `AccountId`, `Region` |
| Which resource? | `Resource.ResourceType` and the matching details block (`InstanceDetails`, `AccessKeyDetails`, `S3BucketDetails`, ...) |
| Who or what is the actor? | `Service.Action` (remote IP, API called, DNS domain, port) |
| Is it ongoing? | `Service.Count`, `EventFirstSeen`, `EventLastSeen` |
| Why did GuardDuty flag it? | `Description`, `Service.Evidence`, `Service.AdditionalInfo` |

Then validate against independent evidence:

1. **Owner and expectation.** Check resource tags. Ask the owner whether this is known: a penetration test, a scanner, a new deployment, a developer on a VPN.
2. **Remote IP.** Is it one of yours (office, NAT gateway, partner)? If so, consider a trusted IP list.
3. **Corroborate.** For IAM findings, look at CloudTrail for the principal around the time. For EC2 findings, look at flow logs and Resolver query logs for the instance. Open the finding in Detective for the entity's history.
4. **Scope.** Same finding on other resources? Other findings on this resource? Check the Auto Scaling group, the role, the subnet.

Outcome:

| Result | Action |
|---|---|
| Confirmed or cannot be ruled out | Go to the matching runbook below |
| Expected activity, one-off | Archive with a note |
| Expected activity, recurring | Create a suppression rule scoped tightly (finding type + specific resource or IP), record the reason |
| GuardDuty mistaken | Archive; mark as not useful so the service learns |

## Route to a runbook

| Finding pattern | Runbook |
|---|---|
| `*:IAMUser/*`, especially `InstanceCredentialExfiltration`, `AnomalousBehavior`, `MaliciousIPCaller`, `ConsoleLoginSuccess.B`, `TorIPCaller` | [Compromised IAM credentials](compromised-iam-credentials.md) |
| `*:EC2/*`, `*:Runtime/*`, `Execution:EC2/MaliciousFile`, `CryptoCurrency:*`, `Backdoor:*`, `Trojan:*` | [Compromised EC2 instance](compromised-ec2-instance.md) |
| `*:S3/*`: `Exfiltration:S3/*`, `Policy:S3/BucketPublicAccessGranted`, `Policy:S3/BucketBlockPublicAccessDisabled`, `Impact:S3/*` | [S3 data exposure](s3-data-exposure.md) or [Ransomware](ransomware-data-destruction.md) |
| `Policy:IAMUser/RootCredentialUsage` | [Root user activity](root-user-activity.md) |
| `Stealth:IAMUser/CloudTrailLoggingDisabled`, `Stealth:S3/ServerAccessLoggingDisabled`, `DefenseEvasion:*` | [CloudTrail tampering](cloudtrail-tampering.md) |
| `*:Kubernetes/*` | Treat the pod or node as a compromised workload: isolate with network policy or cordon the node, capture, rotate service account tokens, then follow [Compromised EC2 instance](compromised-ec2-instance.md) for nodes and [Compromised IAM credentials](compromised-iam-credentials.md) for the pod's role |
| `*:RDS/*` (anomalous login) | Rotate the database credential in Secrets Manager, restrict the security group, review database audit logs |
| `*:Lambda/*` | Set reserved concurrency to zero to stop the function, review its code and layers, rotate its role sessions |
| `AttackSequence:*` | Critical. Open the sequence, list every resource and credential involved, and run the relevant runbook for each, starting with credentials. |

## Tuning

- **Suppression rules** auto-archive matching findings. They do not stop detection. Scope each to the narrowest criteria and review them quarterly.
- **Trusted IP lists** stop findings for listed addresses. **Threat lists** add your own known-bad addresses.
- **Finding export frequency** for updates to existing findings defaults to six hours; reduce it if recurrence matters.
- Generate sample findings to test routing: `aws guardduty create-sample-findings --detector-id "$DET" --finding-types FINDING_TYPE`.

## Follow up

- If triage needed information that was not in the finding or the logs, add the log source. See [logging sources](../cheatsheets/logging-sources.md).
- If a finding type recurs, fix the cause instead of suppressing it.
