# Domain 1: Detection

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 1.1.1–1.1.5, 1.2.1–1.2.6, 1.3.1–1.3.2 (16%) · **Related:** [logging sources](../cheatsheets/logging-sources.md), [services at a glance](../cheatsheets/security-services-at-a-glance.md), [GuardDuty triage](../runbooks/guardduty-finding-triage.md), [logging and detection mappings](../control-mappings/services/logging-detection.md)

## Why this matters

You cannot respond to what you cannot see. Detection is the difference between finding a leaked access key in ten minutes and finding it on the invoice. It is also the domain where the most common production failure is silent: a log source that was never enabled, or that stopped delivering months ago and nobody noticed.

## Mental model

Think in four layers. Each exam question in this domain is about one of them or about a break between two of them.

```
  SOURCES        ->   COLLECTION       ->   ANALYSIS          ->   ACTION
  what happened       where it lands        what it means          who or what reacts

  CloudTrail          S3 (log archive)      GuardDuty              EventBridge rule
  VPC Flow Logs       CloudWatch Logs       Security Hub           SNS / chat / ticket
  Resolver logs       Security Lake         Detective              Lambda / SSM Automation
  Service logs        CloudTrail Lake       Athena / Logs Insights Step Functions
  OS / app logs                             Macie / Inspector / Config
```

Three rules hold across all four layers:

1. **Collect centrally, in an account the workload teams cannot write to.** A log archive account under a Security OU, with an SCP that stops anyone deleting or altering the logs.
2. **Enable at the organization level.** Organization trail, delegated administrator, auto-enable for new accounts. Per-account setup always leaves gaps.
3. **A detective control without a route to a responder is a storage cost.** Every finding type needs an owner and a path to them.

## Task 1.1: Monitoring and alerting

### Deciding what to monitor

Start from the threat, not the service catalog. For a workload, ask:

| Question | Drives |
|---|---|
| What data does it hold and who would want it? | Whether you need S3 or DynamoDB data events, Macie |
| How is it reached from outside? | WAF logs, ALB and CloudFront logs, Shield metrics |
| What identities can act on it? | CloudTrail management events, Access Analyzer |
| What does it call outbound? | VPC Flow Logs, Resolver query logs, Network Firewall logs |
| What does "healthy" look like? | Health checks, CloudWatch alarms, anomaly detection |

Health checks are a security signal too. A Route 53 health check or ALB target health change during an attack tells you about availability impact, and Shield Advanced uses Route 53 health checks to improve its detection accuracy and to qualify for proactive engagement.

### The managed detection services

| Service | Reads | Tells you | Scope notes |
|---|---|---|---|
| **GuardDuty** | CloudTrail management events, VPC Flow Logs, DNS query logs (it pulls these itself; you do not need to enable them), plus optional protection plans | Threats: compromised credentials, crypto mining, C2 traffic, exfiltration, malware | Regional. Enable in every Region. |
| **Security Hub** | Findings from AWS services and partners; its own posture checks, which depend on AWS Config | Posture: which resources fail which controls; one normalized findings feed | Regional with cross-Region aggregation to a home Region |
| **Inspector** | EC2 (agent via SSM, or agentless), ECR images, Lambda functions and code | Software vulnerabilities (CVEs) and unintended network reachability | Continuous, re-scans on new CVE or change |
| **Macie** | S3 objects | Sensitive data (PII, credentials, financial) and bucket-level policy findings | S3 only |
| **Config** | Resource configuration via the configuration recorder | Configuration history and rule compliance | Regional; aggregators give an org view |
| **IAM Access Analyzer** | Resource policies, CloudTrail access activity | External access, unused access, policy validation | Zone of trust is the account or the organization |
| **Detective** | CloudTrail, VPC Flow Logs, GuardDuty findings, EKS audit logs | Investigation context: behavior graph, timelines, related entities | Used after a finding, not as a first-line detector |

GuardDuty protection plans to know by name: S3 Protection, EKS Protection, Runtime Monitoring (EKS, ECS on Fargate, EC2), Malware Protection for EC2, Malware Protection for S3, RDS Protection (login anomalies on Aurora), Lambda Protection. Extended Threat Detection correlates signals into attack-sequence findings **(verify current list)**.

**Naming note.** AWS relaunched Security Hub in 2025 as a unified security operations product that correlates findings into exposures. The original posture-management capability, with its standards and controls, is now called **Security Hub CSPM**. Exam questions about standards, controls, and ASFF findings are about the CSPM capability **(verify current naming)**.

### Aggregation

| Need | Mechanism |
|---|---|
| One place for findings across accounts | Delegated administrator for GuardDuty, Security Hub, Inspector, Macie, Detective |
| One place for findings across Regions | Security Hub cross-Region aggregation |
| Config compliance across the org | Config aggregator (organization-wide, authorized through Organizations) |
| Metrics, logs, traces across accounts | CloudWatch cross-account observability (monitoring account plus source accounts) |
| Events across accounts | EventBridge rule in each account that targets an event bus in the security account |
| Normalized log data lake | Security Lake |

### Alerting patterns

**Pattern 1: finding to responder.** Most services emit findings to the default EventBridge bus.

```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": { "severity": [{ "numeric": [">=", 7] }] }
}
```

Target SNS for notification, Lambda or Step Functions for response, or Systems Manager OpsCenter or Incident Manager for case tracking.

GuardDuty sends a new finding to EventBridge within minutes. Updates to an existing finding are batched, every six hours by default, configurable down to 15 minutes. If the requirement is "notified of recurrences quickly," change the export frequency.

**Pattern 2: API call to alarm.** For specific API activity with no managed finding, such as root user sign-in or a security group change:

- EventBridge rule on `AWS API Call via CloudTrail` for near-real-time reaction to a specific call, or
- CloudTrail to CloudWatch Logs, then a metric filter, then an alarm, when you want a count over time ("more than five failed console logins in five minutes"). This is what the CIS benchmark monitoring controls describe.

**Pattern 3: anomaly.** CloudWatch anomaly detection for metrics, CloudTrail Insights for unusual API call rates or error rates, GuardDuty for behavioral anomalies.

### Automated assessment

| Tool | What it automates |
|---|---|
| **Config conformance packs** | A set of Config rules and remediation actions deployed as a unit, across an organization |
| **Security Hub standards** | Continuous posture checks: AWS Foundational Security Best Practices, CIS AWS Foundations, PCI DSS, NIST SP 800-53 Rev. 5 |
| **Systems Manager State Manager** | Keeps instances in a defined state on a schedule (agent installed, baseline applied) |
| **Inspector** | Continuous vulnerability scanning with no schedule to manage |
| **Security Hub automation rules** | Update or suppress findings by criteria before a human sees them |

## Task 1.2: Logging

### CloudTrail in depth

| Event type | Records | Default |
|---|---|---|
| Management events | Control-plane calls: `RunInstances`, `PutBucketPolicy`, `AssumeRole`, console sign-in | On in Event history (90 days, per Region, not exportable as a stream). A trail is needed for durable storage. |
| Data events | Data-plane calls: S3 object operations, Lambda invocations, DynamoDB item operations, and others | Off. High volume. Use advanced event selectors to scope. |
| Insights events | Unusual volume of write API calls or of API errors | Off |
| Network activity events | Calls made through VPC endpoints, including denied ones | Off |

Key design points:

- **Organization trail.** Created from the management account or a delegated administrator. Applies to every member account. Members can see it but cannot alter or stop it.
- **Multi-Region trail.** One trail, all Regions, including Regions enabled later. Global service events (IAM, STS, CloudFront) are recorded in us-east-1 and included.
- **Log file integrity validation.** CloudTrail writes a signed digest file each hour containing hashes of the log files delivered. `aws cloudtrail validate-logs` proves whether files were changed or deleted. This is the answer to "prove logs were not tampered with."
- **Encryption.** SSE-KMS with a customer managed key. The key policy must let `cloudtrail.amazonaws.com` call `kms:GenerateDataKey*`, and readers need `kms:Decrypt`.
- **Delivery is not instant.** Expect minutes to S3. For near-real-time reaction, use EventBridge.
- **CloudTrail Lake.** Managed event data stores queried with SQL, with long retention, for when you do not want to run Athena over S3.

### The log archive pattern

```
Member accounts                     Log archive account (Security OU)
  org trail ----------------------> S3 bucket
  Config delivery ----------------> - bucket policy allows service principals only,
  VPC Flow Logs ------------------>   scoped with aws:SourceOrgID / aws:SourceArn
  other service logs -------------> - versioning + Object Lock (compliance mode)
                                    - SSE-KMS, lifecycle to colder storage
                                    - SCP denies delete and policy changes

Security tooling account
  delegated admin for GuardDuty, Security Hub, Inspector, Macie, Detective
  read-only access to the archive; Athena / OpenSearch / SIEM
```

Separating the archive (write-once storage) from tooling (where analysts work) limits who can touch evidence.

### Security Lake and OCSF

Security Lake collects logs into S3 in your account, converts them to the **Open Cybersecurity Schema Framework (OCSF)** in Parquet, and manages partitions and lifecycle.

- **Native sources:** CloudTrail management and data events, VPC Flow Logs, Route 53 Resolver query logs, Security Hub findings, EKS audit logs, WAF logs.
- **Custom sources:** anything you can convert to OCSF.
- **Subscribers:** data access (notified of new objects, read from S3) or query access (through Lake Formation, with Athena).
- **Rollup Regions** consolidate data from contributing Regions.

Choose Security Lake when the requirement mentions normalization, a common schema, or third-party analytics tools consuming AWS and non-AWS logs together.

### Analysis

| Tool | Good for | Notes |
|---|---|---|
| CloudWatch Logs Insights | Ad hoc queries over log groups, recent data | Purpose-built query language; fast for operational questions |
| Athena | SQL over S3: CloudTrail, flow logs, ALB logs, Security Lake | Use partition projection to keep scans cheap |
| CloudTrail Lake | SQL over CloudTrail events without managing tables | |
| OpenSearch Service | Full-text search, dashboards, correlation across sources | Feed with subscription filters or Firehose |
| Lambda | Custom parsing, enrichment, normalization in a pipeline | |
| Managed Grafana | Dashboards across CloudWatch, OpenSearch, Athena | Visualization, not storage |
| Detective | Pivoting from a finding to related activity | |

A CloudWatch Logs **subscription filter** streams matching events in near real time to Kinesis Data Streams, Firehose, Lambda, or OpenSearch. A **metric filter** turns matching events into a metric you can alarm on. Know which is which.

### Choosing network log sources

| Question you need to answer | Source |
|---|---|
| Which IPs talked, on which ports, accepted or rejected? | VPC Flow Logs (VPC, subnet, or ENI level) |
| What crossed between VPCs through the hub? | Transit gateway flow logs |
| What domain names did workloads look up? | Route 53 Resolver query logs |
| What was in the packets? | Traffic Mirroring to an inspection appliance |
| What did the firewall alert on or drop? | Network Firewall alert and flow logs |
| What HTTP requests hit the application? | ALB access logs, CloudFront logs, WAF logs |

VPC Flow Logs record metadata only, never payload. They also skip some traffic: queries to the Amazon DNS server, instance metadata (169.254.169.254), Amazon Time Sync, DHCP, and Windows license activation. DNS-based exfiltration is invisible in flow logs. That is what Resolver query logs and DNS Firewall are for.

## Task 1.3: Troubleshooting

Missing logs nearly always come down to one of five causes. Check them in this order.

| # | Cause | Typical symptom | Check |
|---|---|---|---|
| 1 | **Not enabled, or not for this event type** | No S3 object-level events | Data events are off by default. Trail not multi-Region. Flow log on the wrong ENI. |
| 2 | **Destination resource policy** | Trail shows delivery errors | S3 bucket policy must allow the service principal. KMS key policy must allow the service to generate data keys. CloudWatch Logs resource policy for services that deliver via log delivery. |
| 3 | **Sender IAM permissions** | Lambda runs but writes no logs | Execution role lacks `logs:CreateLogStream` / `logs:PutLogEvents`. Instance role lacks `CloudWatchAgentServerPolicy`. API Gateway has no account-level CloudWatch role. |
| 4 | **Network path** | Agent on a private subnet sends nothing | No route to the `logs` and `monitoring` endpoints: add interface endpoints or NAT. Endpoint policy or security group blocks it. |
| 5 | **Something stopped it** | Logs end at a point in time | `StopLogging`, deleted trail, changed bucket policy, expired retention, SCP introduced. Search CloudTrail for the change. |

Service-specific gotchas:

- **CloudWatch agent:** configuration lives in a JSON file or Parameter Store. Check the agent's own log on the instance, the file paths in the `logs` section, and that the agent was restarted after a change.
- **API Gateway:** execution logging and access logging are configured per stage, and both need the account-level CloudWatch Logs role ARN set once per Region.
- **CloudFront:** standard logs are delivered with delay and on a best-effort basis. Real-time logs go to Kinesis Data Streams.
- **WAF:** log destinations must be named with the prefix `aws-waf-logs-`.
- **ALB access logs:** the bucket policy must grant the Elastic Load Balancing log delivery principal for that Region.
- **Config:** if Security Hub controls show no data, the Config recorder is probably not recording the resource types the control needs.
- **GuardDuty findings not arriving:** suppression rule matching, finding is an update to an existing one (batched), or the EventBridge rule is in a different Region from the detector.

## Worked examples

**1. "The security team must be alerted within minutes whenever the root user signs in to any account."**
An EventBridge rule in each account (deployed by StackSets) matching `detail-type: AWS Console Sign In via CloudTrail` with `userIdentity.type: Root`, targeting a central event bus or SNS topic. Console sign-in events are recorded in the Region of the sign-in endpoint, so deploy the rule to us-east-1 at minimum and preferably everywhere. GuardDuty also raises `Policy:IAMUser/RootCredentialUsage`.

**2. "An auditor asks for proof that last quarter's CloudTrail logs are complete and unaltered."**
Log file integrity validation must have been enabled at the time. Run `aws cloudtrail validate-logs` over the period. Object Lock on the archive bucket shows the files could not have been deleted. If validation was not enabled, you cannot prove it after the fact.

**3. "A company wants one query surface over CloudTrail, VPC Flow Logs, and its firewall vendor's logs, in a standard schema, for its SIEM."**
Security Lake with native sources plus a custom source for the vendor logs, and the SIEM as a subscriber.

## Pitfalls and exam traps

- GuardDuty does **not** require you to turn on VPC Flow Logs or DNS logs. It reads its own independent stream. Turning them on is for your own analysis.
- GuardDuty, Security Hub, Config, Inspector, and Macie are **Regional**. "Enabled" means enabled in every Region you use, and ideally in those you do not, to catch activity there.
- Security Hub CSPM controls need **Config recording** enabled.
- CloudTrail Event history is 90 days of management events and cannot be used as a durable audit record.
- S3 server access logs are best-effort and can be delayed. CloudTrail data events are the authoritative record of object-level API calls.
- A trail delivering to CloudWatch Logs needs an IAM role. A trail delivering to S3 needs a bucket policy. Different mechanisms, different failures.
- Suppressing a GuardDuty finding archives it automatically; it does not stop detection. Trusted IP lists stop findings for those IPs.
- Detective investigates. It does not generate primary findings for alerting.

## Self-check

1. Which GuardDuty data sources must you enable yourself before GuardDuty can use them?
2. A Lambda function runs successfully but its log group does not exist. Most likely cause?
3. Which log source shows that an instance resolved a known malware domain?
4. What does CloudTrail log file integrity validation produce, and how often?
5. You need object-level read auditing for one sensitive bucket at minimum cost. What do you configure?
6. Security Hub shows controls with no evaluation data in a new account. First thing to check?
7. Metric filter or subscription filter: which do you use to stream matching log events to OpenSearch?

<details>
<summary>Answers</summary>

1. None of the foundational ones. GuardDuty consumes CloudTrail management events, VPC Flow Logs, and DNS logs independently. Protection plans are opt-in features, not sources you configure separately.
2. The execution role lacks CloudWatch Logs permissions (`logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`).
3. Route 53 Resolver query logs. GuardDuty would also raise a DNS-based finding.
4. A signed digest file every hour, containing hashes of the log files delivered in that hour.
5. A CloudTrail data event selector scoped to that bucket, read events only, using advanced event selectors.
6. Whether the AWS Config recorder is enabled and recording the required resource types.
7. Subscription filter.

</details>

## Further reading

- [CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [GuardDuty finding types](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html)
- [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/)
- [OCSF schema](https://schema.ocsf.io/)
