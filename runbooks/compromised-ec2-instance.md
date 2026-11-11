# Compromised EC2 instance

> **Last reviewed:** 2026-11-10 · **Severity:** High · **SCS-C03:** 2.2.1, 2.2.4 · **NIST 800-53:** IR-4, SC-7, SI-3, SI-4, AU-6

## Trigger

- GuardDuty `*:EC2/*` or `*:Runtime/*` finding: C2 traffic, crypto mining, port scanning, malicious file, reverse shell
- Inspector finding with evidence of exploitation
- Unexpected outbound traffic, CPU, processes, or files reported by monitoring or the owner

## Triage

```bash
aws ec2 describe-instances --instance-ids INSTANCE_ID > evidence/INSTANCE_ID-describe.json
```

From the output, record: VPC, subnet, private and public IPs, security groups, **IAM instance profile**, AMI, launch time, tags, Auto Scaling group membership (`aws:autoscaling:groupName` tag), and attached volumes.

Decide:

- **Is it part of an Auto Scaling group?** Others from the same image may be affected too.
- **What can its role do?** If the role is powerful, treat this as a credential compromise as well.
- **Is harm ongoing?** Exfiltration or attacks on others justify isolating before memory capture. Otherwise capture first.

## Contain and preserve

The order below captures volatile evidence, then cuts access. If harm is ongoing, do step 5 first.

**1. Protect the instance from being terminated or replaced.**

```bash
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID --disable-api-termination
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID --instance-initiated-shutdown-behavior stop

# If in an Auto Scaling group: detach and let the group launch a replacement
aws autoscaling detach-instances --instance-ids INSTANCE_ID --auto-scaling-group-name ASG_NAME --no-should-decrement-desired-capacity

# Remove from load balancer target groups
aws elbv2 deregister-targets --target-group-arn TARGET_GROUP_ARN --targets Id=INSTANCE_ID
```

**2. Tag it.**

```bash
aws ec2 create-tags --resources INSTANCE_ID --tags Key=security:status,Value=quarantined Key=security:case,Value=CASE_ID
```

**3. Capture memory** if you have the tooling staged. Run your memory acquisition document through Systems Manager and write the image to the evidence bucket.

```bash
aws ssm send-command --instance-ids INSTANCE_ID --document-name MEMORY_CAPTURE_DOCUMENT \
  --parameters 'bucket=EVIDENCE_BUCKET,case=CASE_ID'
```

If the SSM agent is not working or no tooling is staged, note that memory was not captured and move on. Do not log in interactively to improvise; you will alter evidence.

**4. Snapshot every volume.**

```bash
for v in $(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=INSTANCE_ID --query 'Volumes[].VolumeId' --output text); do
  aws ec2 create-snapshot --volume-id "$v" --description "IR CASE_ID $v from INSTANCE_ID" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=security:case,Value=CASE_ID}]"
done
aws ec2 get-console-output --instance-id INSTANCE_ID --latest --output text > evidence/INSTANCE_ID-console.txt
```

**5. Isolate on the network.** Replace all security groups with the isolation group (no rules in either direction).

```bash
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID --groups ISOLATION_SG_ID
```

Established tracked connections can survive a security group change. To cut them, add a temporary deny for the instance's private IP to the subnet's network ACL, inbound and outbound, with low rule numbers:

```bash
aws ec2 create-network-acl-entry --network-acl-id NACL_ID --ingress --rule-number 1 --protocol -1 --cidr-block PRIVATE_IP/32 --rule-action deny
aws ec2 create-network-acl-entry --network-acl-id NACL_ID --egress  --rule-number 1 --protocol -1 --cidr-block PRIVATE_IP/32 --rule-action deny
```

The NACL deny affects traffic crossing the subnet boundary. It does not block traffic between instances in the same subnet; the isolation security group handles that for new connections.

If the instance has several network interfaces, apply the isolation group to each.

**6. Revoke the instance role's sessions.** Credentials may already have been copied off the instance.

Follow step 3 of [Compromised IAM credentials](compromised-iam-credentials.md#contain). Other instances using the same role refresh automatically.

**7. Disassociate any Elastic IP** if it must be kept out of the attacker's reach, and record it.

Do **not** stop or terminate the instance until evidence is captured and the investigation says so. Stopping loses memory and instance store data.

## Investigate

**From AWS logs**

- **VPC Flow Logs** for the instance's ENIs: outbound destinations and volumes, inbound sources before the first indicator, lateral connections to other private IPs. Queries: [CLI one-liners](../cheatsheets/cli-oneliners.md#cloudwatch-logs-insights).
- **Resolver query logs:** domains looked up.
- **CloudTrail** for the instance role's sessions (session name is the instance ID): any API calls from an IP that is not the instance.
- **CloudTrail** for changes to the instance: who launched it, security group changes, user data changes.
- **Detective:** the instance's profile and related findings.
- **Inspector:** known vulnerabilities on the instance that match the entry point.

**From the disk**

In the forensics account: share or copy the snapshots, create volumes, and attach them read-only to an analysis instance in an isolated VPC. Encrypted snapshots need the KMS key shared; snapshots encrypted with the AWS managed key must be copied with re-encryption to a shareable key first.

Look at: authentication logs, shell histories, cron and systemd units, startup scripts, SSH authorized keys, new users, web server logs, recently modified binaries, temporary directories, container state.

**Scope questions**

- How did they get in? Exposed port, vulnerable application, stolen SSH key, malicious AMI or dependency.
- What did the instance have access to? Role permissions, secrets on disk, network reach to databases.
- Where did they go next? Lateral movement to other instances; use of the role elsewhere.
- Are sibling instances from the same image compromised?

## Eradicate

- Fix the entry point: patch, close the port, rotate the key, rebuild the image.
- Rotate every secret that was on or reachable from the instance, including database credentials and application keys.
- Remove any persistence found in AWS (see the credentials runbook) and in the image pipeline.
- Rebuild the AMI from a trusted base if there is any doubt about it.

## Recover

- Launch replacement instances from a known-good, patched image. Never return the compromised instance to service.
- Remove the temporary NACL entries.
- When legal and investigative needs are met, terminate the instance. Keep the snapshots according to the evidence retention policy.

```bash
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID --no-disable-api-termination
aws ec2 terminate-instances --instance-ids INSTANCE_ID
```

- Monitor replacements for the same indicators.

## Follow up

| Gap | Fix |
|---|---|
| Entry through an exposed management port | Session Manager; no inbound SSH or RDP. [Domain 3](../teaching/03-infrastructure-security.md#administrative-access) |
| Unpatched vulnerability | Inspector plus Patch Manager; rebuild images on a schedule |
| Role credentials stolen through SSRF | Require IMDSv2; least-privilege instance roles |
| Unrestricted egress | Network Firewall domain allow list; DNS Firewall |
| No memory capture | Stage tooling and an Automation document; consider the Automated Forensics Orchestrator |
| Slow detection | GuardDuty Runtime Monitoring and Malware Protection |
