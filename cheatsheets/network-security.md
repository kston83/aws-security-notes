# Network security cheatsheet

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 3.1.x, 3.3.x, 5.1.2 · **Teaching note:** [Domain 3](../teaching/03-infrastructure-security.md) · **Mappings:** [network](../control-mappings/services/network.md)

## Security group vs network ACL

| | Security group | Network ACL |
|---|---|---|
| Level | ENI (instance, endpoint, load balancer) | Subnet |
| Stateful | Yes: return traffic allowed automatically | No: allow both directions explicitly |
| Rule types | Allow only | Allow and deny |
| Evaluation | All rules considered together | Numbered order, first match wins |
| Default (new, custom) | No inbound, all outbound | Denies everything |
| Default (VPC default) | Allows inbound from itself, all outbound | Allows everything |
| References | CIDR, prefix list, security group ID | CIDR only |
| Block a specific IP | Cannot | Deny rule |

**Ephemeral ports:** a NACL allowing inbound 443 also needs outbound to the client's ephemeral range (1024–65535) for responses.

**Connection tracking:** changing a security group does not cut established tracked connections. A NACL change applies to the next packet.

## Where each control sits

| Control | Layer | Inspects | Deploy at |
|---|---|---|---|
| Shield Standard / Advanced | 3, 4 (Advanced adds 7 with WAF) | Volumetric and protocol attacks | Edge and Regional resources |
| WAF | 7 | HTTP(S) requests | CloudFront, ALB, API Gateway, AppSync, Cognito, App Runner, Verified Access |
| Network Firewall | 3–7 | 5-tuple, domains (SNI/Host), Suricata signatures, optional TLS inspection | VPC firewall subnets; route tables steer traffic |
| Gateway Load Balancer | 3 | Sends traffic to third-party appliances | Inspection VPC |
| Route 53 Resolver DNS Firewall | DNS | Queries by domain list | VPC association |
| NACL | 3, 4 | IP, protocol, port | Subnet |
| Security group | 3, 4 | IP, protocol, port, source group | ENI |
| VPC endpoint policy | API | Principal, action, resource | Endpoint |
| VPC Block Public Access | VPC | Internet gateway traffic | Account, VPC, or by declarative policy |
| VPC Lattice auth policy | 7 | Service-to-service requests with IAM | Service network or service |

## "Why can't A reach B?" order

1. **Route tables** on both sides: is there a route to the destination, and a return route?
2. **Security group** on the destination: inbound allow from the source? Source's outbound allow?
3. **NACL** on both subnets: inbound and outbound, including ephemeral ports?
4. **Gateway or attachment:** internet gateway, NAT gateway, transit gateway route tables and associations, peering (no transitive routing).
5. **Firewall:** Network Firewall rules; is routing symmetric?
6. **DNS:** does the name resolve to the address you expect? Private hosted zones, endpoint private DNS, DNS Firewall.
7. **Host:** OS firewall, service listening.
8. **Endpoint or resource policy** if the target is an AWS service.

Tools: **Reachability Analyzer** for the path, **VPC Flow Logs** for ACCEPT/REJECT.

Reading flow logs for a connection that fails:

| Flow log shows | Meaning |
|---|---|
| Inbound REJECT | Security group or NACL inbound blocked it |
| Inbound ACCEPT, outbound REJECT | NACL outbound blocked the response (a security group would have allowed it statefully) |
| No record | Traffic never arrived: routing, or the source's own controls |

## VPC endpoints

| | Gateway endpoint | Interface endpoint |
|---|---|---|
| Services | S3, DynamoDB | Most AWS services, plus PrivateLink services |
| Mechanism | Route table entry with a prefix list | ENI with private IP in your subnets |
| Security group | No | Yes |
| Endpoint policy | Yes | Yes (most services) |
| From on premises / peered VPC | No | Yes |
| Cost | Free | Hourly plus data |
| DNS | Service's public name | Private DNS overrides the service name inside the VPC |

**Endpoint policy to keep traffic inside the organization**

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": "*",
    "Resource": "*",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalOrgID": "o-EXAMPLE",
        "aws:ResourceOrgID": "o-EXAMPLE"
      }
    }
  }]
}
```

Endpoints needed for common private-subnet tasks:

| Task | Endpoints |
|---|---|
| Session Manager | `ssm`, `ssmmessages`, `ec2messages` (plus `kms` and `logs` or `s3` if encrypting and logging sessions) |
| CloudWatch agent | `logs`, `monitoring` |
| Pull from ECR | `ecr.api`, `ecr.dkr`, S3 gateway |
| Secrets Manager rotation | `secretsmanager` |
| STS regional | `sts` |

## Network Firewall

- **Firewall policy** = stateless rule groups + stateful rule groups + default actions.
- **Stateless** rules: priority order, 5-tuple; actions pass, drop, or forward to stateful.
- **Stateful** rules: Suricata-compatible, domain lists (allow or deny by HTTP Host or TLS SNI), standard 5-tuple. Choose **strict order** evaluation to get predictable priority and a default drop action.
- **Managed rule groups** from AWS for threat signatures and malicious domains.
- **TLS inspection** decrypts and re-encrypts using certificates in ACM.
- Logs: **alert** logs (matches on drop, alert, reject) and **flow** logs, to S3, CloudWatch Logs, or Firehose.
- Deployment models: distributed (firewall in each VPC), centralized (inspection VPC on a transit gateway, **appliance mode on**), or combined.

## WAF quick reference

| Item | Detail |
|---|---|
| Rule actions | Allow, Block, Count, CAPTCHA, Challenge |
| Rate-based rule | Counts requests per aggregation key over a window; blocks while above the limit |
| Managed groups | Core rule set, known bad inputs, SQL database, Linux/Windows/PHP/WordPress, IP reputation, anonymous IP, Bot Control, account takeover prevention, account creation fraud prevention |
| Tuning | Override a managed rule to Count, then match its **label** in your own rule |
| Forwarded IP | Use the `X-Forwarded-For` header when WAF sits behind a proxy or CDN |
| Logging | CloudWatch Logs, S3, or Firehose; destination name starts with `aws-waf-logs-`; redact fields; filter what is logged |
| Scope | `CLOUDFRONT` (create in us-east-1) or `REGIONAL` |

## Hybrid connectivity

| | Encrypted | Private path | Notes |
|---|---|---|---|
| Site-to-Site VPN | IPsec | No (internet) unless over Direct Connect | Two tunnels; attach to virtual private gateway or transit gateway |
| Direct Connect | **No** | Yes | Add MACsec (Layer 2) or VPN on top |
| Direct Connect + MACsec | Layer 2 | Yes | Dedicated connections at supported speeds |
| Client VPN | TLS | No | Mutual certificate, Active Directory, or SAML authentication; authorization rules per group; connection logging |
| Verified Access | TLS | No | Per-request policy on identity and device; no VPN client |

## DDoS resilience checklist

- [ ] Front with CloudFront, Route 53, or Global Accelerator
- [ ] Origins not directly reachable from the internet
- [ ] WAF with rate-based rules
- [ ] Auto Scaling and load balancing sized for surge
- [ ] Shield Advanced on critical resources, with health checks associated and proactive engagement on
- [ ] CloudWatch alarms on Shield and WAF metrics
- [ ] Runbook and Shield Response Team access configured

## Segmentation patterns

| Goal | Pattern |
|---|---|
| Keep data stores off the internet | Isolated subnets with no route to an internet or NAT gateway; endpoints for AWS services |
| Separate environments | Separate accounts and VPCs; transit gateway route tables without routes between them |
| Inspect east/west | Transit gateway routes inter-VPC traffic through an inspection VPC |
| Control egress | Central egress VPC: NAT plus Network Firewall domain allow list; DNS Firewall |
| Central network ownership | Shared VPC subnets through AWS RAM |
| Service-to-service authorization | Security group references; VPC Lattice auth policies; mutual TLS |
