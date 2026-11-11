# Domain 3: Infrastructure Security

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 3.1.1–3.1.4, 3.2.1–3.2.7, 3.3.1–3.3.5 (18%) · **Related:** [network security cheatsheet](../cheatsheets/network-security.md), [compromised EC2 runbook](../runbooks/compromised-ec2-instance.md), [network mappings](../control-mappings/services/network.md), [compute mappings](../control-mappings/services/compute.md)

## Why this matters

Identity is the primary perimeter in AWS, but the network and the host are where an attacker lands when an application has a flaw. This domain covers the layers that limit what a flaw exposes: the edge that filters requests, the compute that runs them, and the network that decides what can talk to what.

## Mental model

Follow a request from the internet to the data, and put a control at each hop:

```
Internet
  -> Route 53 / CloudFront / Global Accelerator     Shield, WAF, geo, TLS policy
    -> Load balancer / API Gateway                  WAF, TLS policy, authN
      -> Subnet boundary                            NACL, Network Firewall, route tables
        -> Instance / task / function               security group, IMDSv2, hardened image, patching
          -> Data store                             security group, endpoint policy, resource policy, KMS
            -> Egress                               Network Firewall, DNS Firewall, endpoint policies
```

North/south traffic crosses the VPC boundary. East/west traffic moves between workloads inside. Most designs control north/south well and forget east/west and egress.

## Task 3.1: Edge

### Choosing an edge strategy

| Threat | Primary control |
|---|---|
| Volumetric and protocol DDoS (L3/L4) | Shield Standard (automatic, free). Put CloudFront, Route 53, or Global Accelerator in front so attacks are absorbed at the edge. |
| Application-layer floods (L7) | WAF rate-based rules; Shield Advanced automatic application-layer mitigation |
| Injection, XSS, and other OWASP Top 10 | WAF managed rule groups plus input validation in the application |
| Bots, scraping, credential stuffing | WAF Bot Control, account takeover prevention, CAPTCHA and Challenge actions |
| Origin bypass | Restrict the origin to CloudFront only |
| Content theft | CloudFront signed URLs or signed cookies |

**Shield Advanced** adds, for a monthly fee and a commitment: enhanced detection, the Shield Response Team, cost protection against scaling charges from an attack, health-based detection using Route 53 health checks, automatic L7 mitigation, and WAF at no extra charge for protected resources. It protects CloudFront, Route 53 hosted zones, Global Accelerator, Elastic Load Balancing, and Elastic IPs.

### CloudFront controls

| Control | Purpose |
|---|---|
| **Origin access control (OAC)** | S3 origin accepts requests only from the distribution. The bucket policy allows `cloudfront.amazonaws.com` with `aws:SourceArn` set to the distribution. Replaces origin access identity. Supports SSE-KMS. |
| **Custom-origin lockdown** | ALB security group allows only the CloudFront managed prefix list, plus a secret custom header that CloudFront adds and the ALB or WAF verifies. VPC origins let CloudFront reach a private ALB directly. |
| **Viewer protocol policy and security policy** | Redirect HTTP to HTTPS; set the minimum TLS version for viewers |
| **Response headers policy** | Adds `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, and CORS headers |
| **Signed URLs and signed cookies** | Time-limited access to private content. URLs for single files, cookies for many files. |
| **Geo restriction** | Country allow list or block list at the distribution. Use WAF geo match when you need it combined with other conditions. |
| **Field-level encryption** | Encrypts specific form fields at the edge with a public key so only the holder of the private key can read them |

**S3 CORS** tells browsers which other origins may read responses. Browsers enforce it. It is not access control and it does not stop a non-browser client.

**AWS IoT policies** attach to device certificates. Scope them with policy variables such as `${iot:Connection.Thing.ThingName}` so a device can publish and subscribe only to its own topics.

### WAF rule design

A web ACL attaches to CloudFront, an Application Load Balancer, API Gateway, AppSync, a Cognito user pool, App Runner, or Verified Access. Web ACLs for CloudFront are created in us-east-1.

| Concept | Detail |
|---|---|
| Evaluation | Rules run in priority order. The first terminating action (Allow, Block) ends evaluation. Count does not terminate. A default action applies if nothing matches. |
| Actions | Allow, Block, Count, CAPTCHA, Challenge |
| Capacity | Each rule costs web ACL capacity units (WCUs) against a limit per web ACL |
| Labels | A rule can add a label to a request; later rules match on labels. This is how you tune a managed rule group: set its rule to Count, then write your own rule on its label. |
| Scope-down | Narrows which requests a rate-based or managed rule evaluates |

Rule types and when to use them:

| Requirement | Rule |
|---|---|
| Block known-bad request patterns | AWS managed rule groups: core rule set, known bad inputs, SQL database, IP reputation, anonymous IP |
| Limit requests per client | Rate-based rule, aggregated on source IP, forwarded IP, or a custom key such as a header, cookie, or query argument |
| Restrict by country | Geo match statement |
| Allow or block specific addresses | IP set |
| Identify clients behind shared IPs | JA3 or JA4 TLS fingerprint match |
| Stop automated traffic | Bot Control managed group; Challenge or CAPTCHA action |
| Use a vendor's rules | AWS Marketplace managed rule groups |

Always deploy new rules in Count mode first, read the logs, then switch to Block. WAF logs go to CloudWatch Logs, S3, or Firehose, and can be ingested into Security Lake in OCSF. WAF inspects only the first part of a request body; set a size constraint rule for oversized bodies so they do not slip through uninspected.

## Task 3.2: Compute

### Hardened images

**EC2 Image Builder** runs a pipeline: base image, build components (install, harden, patch), test components, then distribution of the AMI or container image to accounts and Regions. Schedule it so images are rebuilt with current patches. It integrates with Inspector to scan the result.

Harden by removing what is not needed, applying a benchmark such as CIS or STIG, baking in the SSM agent and CloudWatch agent, and requiring IMDSv2 in the AMI's launch settings. Then replace instances from new images rather than patching long-lived ones where the workload allows it.

For containers: minimal base images, no secrets in layers, non-root user, read-only root filesystem, ECR image scanning, immutable tags, and image signing.

### Workload identity

| Compute | Identity mechanism | Note |
|---|---|---|
| EC2 | Instance profile wrapping an IAM role | Credentials come from the instance metadata service |
| ECS | **Task role** for the application; **task execution role** for the agent to pull images and write logs | Do not confuse the two |
| EKS | EKS Pod Identity or IAM roles for service accounts | Avoid letting pods use the node's instance role |
| Lambda | **Execution role** for what the function can call; **resource-based policy** for who can invoke it | |
| AWS services acting for you | **Service role** you create and pass, or **service-linked role** the service owns | `iam:PassRole` controls who can hand a role to a service |

`iam:PassRole` is a privilege-escalation path. A principal who can pass an admin role to a service they control gains admin. Scope it by role ARN or path and by `iam:PassedToService`.

**IMDSv2** requires a session token obtained with a PUT request, which defeats most SSRF attacks against the metadata endpoint. Require it with `HttpTokens=required`, set it as the account default for new instances, and enforce it with an SCP or declarative policy. The response hop limit defaults to 1, so containers on the instance need 2 to reach it.

### Vulnerability management

**Inspector** scans continuously, with no scheduled assessments:

| Target | How |
|---|---|
| EC2 | Agent-based through the SSM agent, or agentless from EBS snapshots |
| ECR images | On push and continuously as new CVEs are published |
| Lambda | Package dependencies (standard scanning) and function code (code scanning) |

It also reports network reachability findings and can export a software bill of materials. Findings flow to Security Hub and EventBridge.

**GuardDuty Runtime Monitoring** watches process, file, and network behavior inside EC2, ECS on Fargate, and EKS workloads. Inspector tells you what is vulnerable. GuardDuty tells you what is being exploited.

**Patch Manager** applies patches using:

- **Patch baselines:** which patches are approved, with auto-approval delays
- **Patch groups** or tags: which instances get which baseline
- **Maintenance windows** or patch policies: when
- **Compliance reporting:** which instances are missing what, also surfaced through Config

The loop is: Inspector finds, Patch Manager fixes, Inspector confirms the finding closed.

### Administrative access

| Option | How it works | Why choose it |
|---|---|---|
| **Session Manager** | SSM agent makes an outbound connection; you get a shell through the Systems Manager API | No inbound ports, no bastion, no SSH keys. IAM controls access. Sessions are logged to S3 or CloudWatch Logs and recorded in CloudTrail. Works in private subnets through interface endpoints. |
| **EC2 Instance Connect** | Pushes a one-time SSH public key to the instance, valid briefly, authorized by IAM | Standard SSH client with IAM-governed access. The Instance Connect Endpoint reaches private instances without a public IP. |
| Bastion host | A hardened jump instance | Legacy. Prefer the two above. |

Session Manager in a private subnet needs interface endpoints for `ssm`, `ssmmessages`, and `ec2messages`, plus an instance profile with `AmazonSSMManagedInstanceCore`.

### Pipeline security

Shift checks left so flaws are caught before deployment:

| Stage | Control |
|---|---|
| IDE and pull request | Amazon Q Developer security scans; CodeGuru Security static analysis **(verify availability)**; secret scanning |
| Build | Dependency scanning and SBOM generation; Inspector scanning of images and code |
| IaC | cfn-lint, CloudFormation Guard, Access Analyzer custom policy checks |
| Artifact | ECR scan on push; image signing with AWS Signer; Lambda code signing |
| Deploy | Approval gates; deployment role with least privilege; CloudFormation hooks |

The pipeline is also a target. Its roles can deploy anything. Protect it with OIDC federation in place of stored keys, scoped roles per stage, and branch protection.

### Generative AI workloads

Map controls to the OWASP Top 10 for LLM Applications:

| Risk | AWS control |
|---|---|
| Prompt injection | Bedrock Guardrails prompt attack filter; separate system and user content; treat model output as untrusted |
| Sensitive information disclosure | Guardrails sensitive information filters (mask or block PII); Macie on training and retrieval data; least-privilege access to knowledge bases |
| Supply chain | Use vetted foundation models; scan dependencies; control which models are permitted with IAM and SCPs |
| Data and model poisoning | Access control and integrity on training and retrieval data sources |
| Improper output handling | Validate and encode model output before passing it to browsers, shells, or queries |
| Excessive agency | Least-privilege roles for agents and their action groups; human confirmation for consequential actions |
| System prompt leakage | Keep secrets and authorization logic out of prompts |
| Vector and embedding weaknesses | Tenant isolation and access control in the vector store |
| Misinformation | Guardrails contextual grounding checks; cite sources |
| Unbounded consumption | Quotas, throttling, WAF rate limits, budget alarms |

Also: reach Bedrock through PrivateLink, enable model invocation logging, encrypt with customer managed keys, and use the AI services opt-out policy in Organizations where data use for service improvement must be prevented.

## Task 3.3: Network

### Controls that permit or deny traffic

| | Security group | Network ACL | Network Firewall |
|---|---|---|---|
| Applies to | ENI | Subnet | Traffic routed through firewall endpoints |
| State | Stateful | Stateless | Stateless and stateful engines |
| Rules | Allow only | Allow and deny, evaluated in number order | Suricata-compatible rules, domain lists, 5-tuple |
| Can reference | CIDRs, prefix lists, other security groups | CIDRs | CIDRs, domains, protocols, signatures |
| Typical use | Per-workload micro-segmentation | Coarse subnet guardrail, explicit blocks | Egress filtering, IDS/IPS, deep inspection |

Details that get tested:

- A NACL needs rules in both directions, including the **ephemeral port range** for return traffic.
- Security groups can reference other security groups, which keeps rules valid as instances come and go.
- Network Firewall takes effect only if **route tables** send traffic through its endpoints. Symmetric routing is required for stateful inspection.
- For central inspection through a transit gateway, enable **appliance mode** on the inspection VPC attachment so both directions of a flow use the same Availability Zone.
- **Gateway Load Balancer** inserts third-party appliances transparently.
- **Route 53 Resolver DNS Firewall** filters DNS queries by domain list, which covers the DNS exfiltration path that other controls miss.
- **VPC Block Public Access** is a declarative control that blocks internet gateway traffic for a VPC or account regardless of route tables and security groups.

The cheatsheet has the troubleshooting order: [network security](../cheatsheets/network-security.md).

### Segmentation

- **Account and VPC boundaries** are the strongest segmentation. Separate production, non-production, and shared services.
- **Subnet tiers:** public (load balancers, NAT), private (application), isolated (data stores, no route to the internet at all).
- **Transit gateway route tables** decide which VPCs can reach each other. Separate route tables for production and non-production prevent east/west paths between them while both reach shared services and inspection.
- **East/west inspection:** route inter-VPC traffic through an inspection VPC with Network Firewall or Gateway Load Balancer.
- **Egress control:** a central egress VPC with Network Firewall domain allow lists; VPC endpoints for AWS services so that traffic never needs the internet path.
- **Application-layer segmentation:** VPC Lattice auth policies or security group references.

### Hybrid connectivity

| Option | Encryption | Notes |
|---|---|---|
| **Site-to-Site VPN** | IPsec, always | Two tunnels per connection for redundancy. Runs over the internet or over Direct Connect. |
| **Direct Connect** | **None by default** | Private, consistent path, but not encrypted |
| Direct Connect with **MACsec** | Layer 2 encryption on the link | Dedicated connections at supported speeds and locations only |
| VPN over Direct Connect | IPsec end to end | Use when MACsec is unavailable or when encryption must extend past the first hop |
| **Client VPN** | TLS | For individual users. Authenticates with certificates, Active Directory, or SAML. Authorization rules limit which networks each group reaches. |
| **Verified Access** | TLS | Application access without a VPN. Each request is evaluated against Cedar policies using identity and device posture from trust providers. |

If a requirement says data crossing Direct Connect must be encrypted, the answer is MACsec or a VPN over the connection. Direct Connect alone does not meet it.

### Finding unnecessary access

| Tool | Question it answers |
|---|---|
| **Network Access Analyzer** | Which paths exist that violate my stated requirements? For example, any path from the internet to the data tier. |
| **Reachability Analyzer** | Can A reach B, and if not, which component blocks it? |
| **Inspector network reachability** | Which instance ports are reachable from the internet? |
| **Security Hub and Config rules** | Which security groups allow 0.0.0.0/0 on sensitive ports? |
| **Firewall Manager** | Audit and remediate over-permissive security groups across the organization |
| **Verified Access logs** | Who accessed which application, with what trust context |

## Worked examples

**1. An ALB behind CloudFront is being hit directly by attackers who found its DNS name.**
Restrict the ALB security group to the CloudFront origin-facing managed prefix list. Add a custom origin header in CloudFront carrying a secret, and block requests without it at the ALB or with WAF. Or move the ALB to private subnets and use a CloudFront VPC origin.

**2. Instances in private subnets must reach only `*.example.com` and AWS APIs.**
Route outbound traffic through Network Firewall with a stateful domain allow list (inspecting TLS SNI and HTTP Host). Add VPC endpoints for the AWS services. Add DNS Firewall to block lookups of other domains.

**3. A login endpoint sees credential stuffing from thousands of IPs, each sending few requests.**
An IP rate limit will not trigger. Use the WAF account takeover prevention managed rule group, Bot Control, or a rate-based rule aggregated on a different key such as the username field or a JA4 fingerprint, with a Challenge or CAPTCHA action.

## Pitfalls and exam traps

- Security groups cannot deny. To block one IP, use a NACL, WAF, or Network Firewall.
- NACL rules are evaluated lowest number first, and the first match wins.
- WAF does not attach to a Network Load Balancer or directly to EC2.
- A web ACL for CloudFront must be created in us-east-1 with CloudFront scope.
- Shield Standard is automatic. Shield Advanced must be subscribed, and resources must be explicitly added.
- OAC applies to S3 origins (and some others such as Lambda function URLs), not to ALB origins.
- Direct Connect is private but not encrypted.
- Inspector needs the SSM agent to be managed, or agentless mode, to scan EC2. An unmanaged instance is not scanned.
- The ECS task execution role is not the role your application code uses.
- Gateway endpoints exist only for S3 and DynamoDB, and they work through route tables, so they are not reachable from on premises.

## Self-check

1. You must block a single abusive IP address from reaching instances in a subnet. Which control?
2. Why does a containerized application on EC2 fail to get credentials after IMDSv2 is enforced?
3. What two things make Session Manager work in a subnet with no internet path?
4. Which WAF action lets you evaluate a rule's effect without blocking?
5. How do you ensure traffic through a central inspection VPC is symmetric?
6. A requirement states that traffic over Direct Connect must be encrypted at Layer 2. What do you use?
7. Which tool confirms that no network path exists from an internet gateway to a database subnet across the organization's VPCs?
8. Which Bedrock feature reduces the risk of a model returning customer PII?

<details>
<summary>Answers</summary>

1. A network ACL deny rule (or WAF/Network Firewall if those are in the path). Security groups cannot deny.
2. The metadata response hop limit is 1. Containers add a hop; raise the limit to 2 or use task or pod roles.
3. Interface VPC endpoints for `ssm`, `ssmmessages`, and `ec2messages`, and an instance profile with SSM permissions (with the agent installed).
4. Count.
5. Enable appliance mode on the transit gateway attachment for the inspection VPC.
6. MACsec on a supported dedicated connection.
7. Network Access Analyzer, with a scope defining that path as prohibited.
8. Guardrails sensitive information filters.

</details>

## Further reading

- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [AWS Best Practices for DDoS Resiliency](https://docs.aws.amazon.com/whitepapers/latest/aws-best-practices-ddos-resiliency/)
- [Building a Scalable and Secure Multi-VPC AWS Network Infrastructure](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/)
- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
