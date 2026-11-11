# Logging sources cheatsheet

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 1.2.1, 1.2.2, 1.2.6, 1.3.x · **Teaching note:** [Domain 1](../teaching/01-detection.md) · **Mappings:** [logging and detection](../control-mappings/services/logging-detection.md)

## Control plane and identity

| Source | Records | Destinations | On by default | Notes |
|---|---|---|---|---|
| CloudTrail management events | Control-plane API calls, console sign-ins | S3, CloudWatch Logs, CloudTrail Lake, EventBridge | Event history only (90 days) | Create an organization, multi-Region trail |
| CloudTrail data events | Object, item, and invocation-level calls | Same | No | Scope with advanced event selectors |
| CloudTrail Insights | Unusual API call and error rates | Same | No | |
| CloudTrail network activity events | API calls through VPC endpoints | Same | No | Shows denied calls by endpoint policy |
| IAM Access Analyzer | External, internal, and unused access findings | Console, Security Hub, EventBridge | No | |
| IAM credential report | Per-user credential status and age | Download (CSV) | On demand | |
| Config | Resource configuration history | S3, SNS | No | Needs the recorder running |

## Network

| Source | Records | Destinations | Notes |
|---|---|---|---|
| VPC Flow Logs | IP traffic metadata per ENI: addresses, ports, protocol, bytes, ACCEPT/REJECT | CloudWatch Logs, S3, Firehose | No payload. Custom format adds fields such as `pkt-srcaddr`, `tcp-flags`, `flow-direction`. |
| Transit gateway flow logs | Traffic through a transit gateway | CloudWatch Logs, S3, Firehose | For hub visibility |
| Route 53 Resolver query logs | DNS queries from VPC resources and their responses | CloudWatch Logs, S3, Firehose | The only place DNS exfiltration shows |
| Route 53 public query logs | Queries to public hosted zones | CloudWatch Logs (us-east-1) | |
| Network Firewall logs | Alert, flow, and TLS logs | CloudWatch Logs, S3, Firehose | |
| DNS Firewall | Blocked and alerted queries | Through Resolver query logs | |
| Traffic Mirroring | Full packets | An ENI, NLB, or GWLB target | For IDS and deep forensics |
| Client VPN connection logs | Connection attempts | CloudWatch Logs | |
| Verified Access logs | Access requests and trust data (OCSF) | CloudWatch Logs, S3, Firehose | |

Flow logs do **not** capture: traffic to the Amazon DNS server, instance metadata (169.254.169.254), Amazon Time Sync, DHCP, Windows license activation, or mirrored traffic.

## Edge and application

| Source | Records | Destinations | Notes |
|---|---|---|---|
| WAF logs | Each inspected request with matched rules and labels | CloudWatch Logs, S3, Firehose | Name prefix `aws-waf-logs-` |
| CloudFront standard logs | Viewer requests | S3, CloudWatch Logs, Firehose | Delayed, best effort |
| CloudFront real-time logs | Viewer requests within seconds | Kinesis Data Streams | |
| ALB / NLB / CLB access logs | Requests or connections | S3 | Bucket policy must permit ELB log delivery |
| API Gateway execution logs | Request processing detail | CloudWatch Logs | Needs account-level CloudWatch role |
| API Gateway access logs | Who called, custom format | CloudWatch Logs, Firehose | Per stage |
| Lambda logs | Function output | CloudWatch Logs (also S3, Firehose) | Execution role needs logs permissions |
| S3 server access logs | Requests to a bucket | Another S3 bucket | Best effort; not the audit record |

## Compute and data

| Source | Records | Destinations | Notes |
|---|---|---|---|
| OS and application logs | Syslog, auth logs, Windows events, app logs | CloudWatch Logs through the CloudWatch agent | Needs agent, IAM role, network path |
| Session Manager logs | Session activity | S3, CloudWatch Logs | Configure in session preferences |
| EKS control plane logs | API server, audit, authenticator | CloudWatch Logs | Enable per log type |
| ECS container logs | stdout/stderr | CloudWatch Logs (`awslogs`), FireLens | Task execution role needs logs permissions |
| RDS / Aurora logs | Error, slow query, audit | CloudWatch Logs | Enable export per log type; audit needs engine configuration |
| RDS Database Activity Streams | Near-real-time database activity | Kinesis Data Streams | Separation of duties from DBAs |
| Redshift audit logging | Connections, user activity | S3, CloudWatch Logs | |
| DynamoDB, S3, Lambda data access | Item, object, invoke | CloudTrail data events | |
| KMS key usage | Every KMS API call | CloudTrail management events | |
| Bedrock model invocation logs | Prompts and responses | CloudWatch Logs, S3 | Off by default; contains sensitive data |

## Findings

| Source | Emits to |
|---|---|
| GuardDuty | Console, EventBridge, Security Hub, S3 export, Detective |
| Security Hub | Console, EventBridge |
| Inspector | Console, EventBridge, Security Hub, S3 export |
| Macie | Console, EventBridge, Security Hub; discovery results to S3 |
| Config rules | Console, EventBridge, Security Hub, SNS |
| Health (including abuse and exposed-credential notifications) | EventBridge, Health Dashboard |

## Storage choices

| Store | Query | Retention | Use for |
|---|---|---|---|
| S3 (log archive account) | Athena | Lifecycle; Object Lock for immutability | Long-term, cheapest, authoritative copy |
| CloudWatch Logs | Logs Insights; metric and subscription filters | Per log group; default never expires | Near-real-time alerting and operational search |
| CloudTrail Lake | SQL | Configurable, multi-year | CloudTrail and Config analysis without table management |
| Security Lake | Athena, subscribers | Lifecycle per source | Normalized OCSF across sources and Regions |
| OpenSearch Service | Search and dashboards | Index policies | Interactive investigation, SIEM |

## Minimum viable logging for an organization

- [ ] Organization trail: multi-Region, management events, log file validation, SSE-KMS, to log archive S3
- [ ] CloudTrail data events for buckets, tables, and functions holding sensitive data
- [ ] Config recorder in every account and Region in use; aggregator in the security account
- [ ] VPC Flow Logs on every VPC, to S3
- [ ] Resolver query logging on every VPC
- [ ] GuardDuty in every account and Region, delegated administrator, auto-enable
- [ ] Security Hub with cross-Region aggregation
- [ ] ALB, CloudFront, and WAF logs for internet-facing workloads
- [ ] Log archive bucket: Object Lock, versioning, deny-delete SCP
- [ ] CloudWatch log group retention set and log groups encrypted
- [ ] An alarm for "a log source stopped delivering"

## Why are my logs missing?

| Check | Detail |
|---|---|
| Enabled for this type? | Data events, Insights, and most service logs are opt-in. Trail is multi-Region? |
| Destination policy | S3 bucket policy allows the service principal with the right prefix and `aws:SourceArn`. CloudWatch Logs resource policy for vended logs. |
| KMS | Key policy allows the delivering service to `GenerateDataKey*`; readers have `Decrypt` |
| Sender permissions | Lambda execution role; instance profile for the agent; API Gateway account role; flow log delivery role for CloudWatch Logs |
| Network | Private subnet without endpoints or NAT for `logs` |
| Stopped or deleted | CloudTrail: `StopLogging`, `DeleteTrail`, `PutEventSelectors`, `DeleteFlowLogs`, `DeleteLogGroup` |
| Organization policy | SCP or RCP now blocking delivery |
| Wrong place | Different Region, different account, different prefix; global service events in us-east-1 |
| Delay | CloudTrail to S3 takes minutes; CloudFront standard logs can take longer; S3 access logs are best effort |
| Retention | Log group retention expired the data; S3 lifecycle removed it |
| Naming | WAF destination lacks the `aws-waf-logs-` prefix |

Check delivery status with `aws cloudtrail get-trail-status`, which reports the latest delivery error, and `aws ec2 describe-flow-logs`, which reports `DeliverLogsStatus`.
