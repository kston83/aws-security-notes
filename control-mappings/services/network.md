# Control impact: network and edge services

> **Last reviewed:** 2026-11-10 · **Framework:** NIST SP 800-53 Rev. 5 · **Method:** [README](../README.md) · **Teaching note:** [Domain 3](../../teaching/03-infrastructure-security.md)

Type: **I** = Implements, **S** = Supports, **E** = Evidence. Config rule names and Security Hub IDs are pointers **(verify)**.

## VPC, security groups, network ACLs

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Tiered subnets: public, private, isolated | SC-7, SC-7(21), AC-4 | I | Data stores share a network tier with internet-facing components | Route tables; subnet inventory | `no-unrestricted-route-to-igw`, `subnet-auto-assign-public-ip-disabled` |
| Security groups allow only required ports and sources | SC-7(5), CM-7, AC-4 | I | Unneeded services reachable; lateral movement easy | Security group rules | `vpc-sg-open-only-to-authorized-ports`, `restricted-common-ports` |
| No unrestricted inbound SSH or RDP | SC-7, AC-17, CM-7 | I | Management ports exposed to internet scanning and brute force | Security group rules | `restricted-ssh` (EC2.13), `restricted-common-ports` (EC2.14) |
| Default security group has no rules | SC-7(5) | I | Resources launched without an explicit group inherit open intra-group access | Default group rules | `vpc-default-security-group-closed` (EC2.2) |
| Instances without public IPs | SC-7, AC-3 | I | Workloads directly addressable from the internet | Instance attributes | `ec2-instance-no-public-ip` (EC2.9) |
| NACLs as coarse subnet guardrails | SC-7, AC-4 | I | No stateless backstop if a security group is misconfigured | NACL entries | `nacl-no-unrestricted-ssh-rdp` (EC2.21) |
| VPC Block Public Access | SC-7, AC-4, CM-6 | I | Internet path can be created by any route and gateway change | BPA setting; declarative policy | Manual |
| VPC Flow Logs on all VPCs | AU-2, AU-12, SI-4(4) | E | No record of network connections for detection or forensics | Flow log configuration | `vpc-flow-logs-enabled` (EC2.6) |
| Transit gateway route tables separate environments | AC-4, SC-7(21) | I | Production and non-production mutually reachable | Route table associations | Network Access Analyzer |
| Network Access Analyzer scopes run regularly | CA-7, SC-7, CA-9 | S, E | Unintended paths accumulate unnoticed | Analyzer findings | Scheduled analysis |

## VPC endpoints and private access

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| VPC endpoints for AWS services | SC-7, AC-4, SC-8 | I | Service traffic requires an internet path | Endpoint inventory | `service-vpc-endpoint-enabled` |
| Endpoint policies restricting principals and resources to the organization | AC-4, SC-7(10), AC-3 | I | Endpoint usable to reach external buckets or with external credentials | Endpoint policy | Custom |
| Resource policies requiring `aws:SourceVpce` | AC-3, AC-4, SC-7 | I | Resource reachable from any network with valid credentials | Resource policies | Custom |
| PrivateLink for internal and partner services | SC-7, CA-3, AC-4 | I | Peering or internet exposure widens connectivity beyond the one service | Endpoint services | Manual |

## Network Firewall and DNS Firewall

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| Egress filtered by domain allow list | SC-7(5), SC-7(10), AC-4, SC-7(8) | I | Compromised workloads reach any command-and-control or exfiltration destination | Firewall policy; route tables | `netfw-policy-default-action-packets`, `netfw-policy-rule-group-associated` |
| Stateful IPS rules, including managed threat signatures | SI-4, SI-4(4), SI-3 | I | Known exploit traffic passes uninspected | Rule groups | `netfw-stateless-rule-group-not-empty` |
| Firewall alert and flow logging | AU-2, AU-12, SI-4 | E | Blocks and alerts unrecorded | Logging configuration | `netfw-logging-enabled` |
| East/west inspection through an inspection VPC | SC-7, AC-4, SI-4(4) | I | Lateral traffic between VPCs unobserved and unfiltered | Transit gateway routing | Network Access Analyzer |
| DNS Firewall with managed and custom domain lists | SC-7(10), SI-4(4), SC-20 | I | DNS usable for command and control and exfiltration | Rule group associations | Manual |
| Resolver query logging | AU-2, AU-12, SI-4(4) | E | No record of DNS lookups | Query log configuration | Manual |

## WAF, Shield, CloudFront

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| WAF web ACL on internet-facing ALBs, APIs, and distributions | SC-7, SI-10, SI-4(4), SI-3 | I | Application-layer attacks reach the application unfiltered | Web ACL associations | `alb-waf-enabled`, `api-gw-associated-with-waf`, `cloudfront-associated-with-waf` |
| Rate-based rules | SC-5 | I | Application-layer floods and brute force unthrottled | Web ACL rules | Custom |
| WAF logging | AU-2, AU-12, SI-4 | E | No record of blocked and allowed requests | Logging configuration | `wafv2-logging-enabled` |
| Shield Advanced on critical endpoints, with health checks | SC-5, IR-7, CP-10 | I | Limited DDoS visibility and no response team support | Protections list | `shield-advanced-enabled-autorenew` |
| CloudFront HTTPS only with current TLS policy | SC-8, SC-8(1), SC-13 | I | Viewers can connect over HTTP or weak TLS | Distribution settings | `cloudfront-viewer-policy-https`, `cloudfront-security-policy-check` |
| Origin restricted to CloudFront (OAC, prefix list, custom header) | SC-7, AC-3 | I | Attackers bypass WAF and edge controls by hitting the origin | Bucket policy; security group | `cloudfront-s3-origin-access-control-enabled` |
| Response headers policy (HSTS, CSP) | SC-8, SI-10 | S | Browsers not instructed to enforce transport and content restrictions | Distribution settings | Manual |
| Firewall Manager policies across the organization | CM-6, CM-6(1), SC-7 | I | Protections depend on each account configuring them | Firewall Manager policy compliance | `fms-*` rules |

## Load balancing and hybrid

| Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check |
|---|---|---|---|---|---|
| HTTPS/TLS listeners only; HTTP redirected | SC-8, SC-8(1), SC-23 | I | Sessions and credentials in clear text | Listener configuration | `elb-tls-https-listeners-only`, `alb-http-to-https-redirection-check` |
| ALB drops invalid headers; desync mitigation | SI-10, SC-7 | I | HTTP request smuggling possible | Load balancer attributes | `alb-http-drop-invalid-header-enabled`, `alb-desync-mode-check` |
| Load balancer access logs | AU-2, AU-12 | E | No request record at the entry point | Attributes | `elb-logging-enabled` |
| Site-to-Site VPN with both tunnels up | SC-8, CP-8, AC-17(2) | I | Unencrypted or single-path hybrid link | VPN status | `vpc-vpn-2-tunnels-up` |
| Direct Connect with MACsec or VPN overlay | SC-8, SC-8(1) | I | Private but unencrypted transport | Connection settings | Manual |
| Client VPN with SAML and MFA, authorization rules, connection logs | AC-17, AC-17(1), IA-2(1), AU-2 | I | Remote users over-connected and unlogged | Endpoint configuration | Manual |
| Verified Access policies on identity and device posture | AC-17, AC-3, IA-3, AC-2(11) | I | Application access granted on network location alone | Policies; access logs | Manual |
