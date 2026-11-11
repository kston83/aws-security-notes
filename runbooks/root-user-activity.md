# Root user activity

> **Last reviewed:** 2026-11-10 · **Severity:** Critical until explained · **SCS-C03:** 6.1.5, 2.2.4 · **NIST 800-53:** AC-2, AC-6(5), AC-6(9), IA-2(1), IR-4

## Trigger

- GuardDuty `Policy:IAMUser/RootCredentialUsage`
- EventBridge rule or CloudWatch alarm on `userIdentity.type = Root`
- Console sign-in notification to the root email address
- A password reset email for the root user that nobody requested

Root use should be rare enough that every occurrence is reviewed.

## Triage

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=root \
  --start-time START_TIME --query 'Events[].[EventTime,EventName,EventSource]' --output table
```

Or with Athena: [root user query](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail). Console sign-ins are recorded in the Region of the sign-in endpoint, so check us-east-1 and the Region you normally use.

| Question | How to tell |
|---|---|
| Was it root itself, or an AWS service acting with root identity? | `userIdentity.invokedBy` is present for service calls. Those are normally benign. |
| Was it a centralized privileged root session? | `AssumeRoot` in the management or delegated admin account's CloudTrail, with a task policy, shortly before |
| Was it planned? | Change ticket or break-glass record; ask the custodians of the root credentials |
| Was MFA used? | `additionalEventData.MFAUsed` on `ConsoleLogin` |
| From where? | `sourceIPAddress`, `userAgent` |
| What was done? | Event names after sign-in |

If it matches a recorded, authorized use: note it in the break-glass log, confirm the credentials were re-secured afterward, and close.

If nobody can account for it, or if any of these appear, treat as a compromise: sign-in without MFA, unfamiliar source IP, root access key creation, password or MFA or email change, changes to IAM, Organizations, billing, or security services.

## Contain

**Member account**

1. Attach the quarantine SCP. SCPs restrict the root user of member accounts.

```bash
aws organizations attach-policy --policy-id QUARANTINE_POLICY_ID --target-id ACCOUNT_ID
```

2. If centralized root access is enabled, remove the member account's root credentials from the management or delegated administrator account: delete the root password, access keys, signing certificates, and deactivate MFA through the IAM root access management console. With no root credentials, the root user cannot sign in at all.
3. Otherwise, sign in as root yourself (using the password reset flow if needed), change the password, delete all root access keys, and replace MFA devices.

**Management account**

SCPs do not apply. Speed matters.

1. Sign in as root from a trusted device. If the password was changed, use the reset flow through the root email. If the email or MFA was changed and you are locked out, open an account recovery case with AWS Support immediately and engage your AWS account team.
2. Change the password. Remove and re-register MFA devices. Delete any root access keys.

```bash
aws iam get-account-summary --query 'SummaryMap.[AccountAccessKeysPresent,AccountMFAEnabled]'
```

3. Verify the account's email address, phone number, and alternate contacts have not been changed.
4. Secure the root mailbox: reset its password, check forwarding rules and recent sign-ins.

## Preserve evidence

```bash
aws iam get-account-authorization-details > evidence/iam-snapshot.json
aws organizations list-accounts > evidence/org-accounts.json
aws organizations list-policies --filter SERVICE_CONTROL_POLICY > evidence/scps.json
```

## Investigate

Everything root did in the window. Root can do anything, so look widely:

- **IAM:** new users, roles, keys, policies, identity providers. See [Compromised IAM credentials](compromised-iam-credentials.md#investigate).
- **Organizations** (management account): accounts created, invited, or removed; SCPs detached or edited; delegated administrators registered; trusted access changes.
- **Account settings:** contact details, payment methods, Regions enabled, support cases opened, account closure attempts.
- **Security services:** see [CloudTrail tampering](cloudtrail-tampering.md).
- **Data and resources:** bucket policy changes, snapshot sharing, new instances in any Region.
- **How the credentials were obtained:** mailbox compromise, password reuse, custodians' devices, MFA device loss, social engineering of support.

## Eradicate

- Remove everything the attacker created, in every Region and, for the management account, across the organization.
- Restore SCPs, delegated administrators, and Organizations settings.
- Rotate credentials for any IAM principals root may have touched.
- Re-secure the root email account and its recovery paths.

## Recover

- Detach the quarantine SCP after verification.
- Re-seal root credentials: new password in the vault, MFA devices in their separate secure locations, custody log updated.
- Test the break-glass procedure again once things are calm.

## Follow up

| Gap | Fix |
|---|---|
| Member accounts still have root credentials | Enable centralized root access management and remove them. [Domain 6](../teaching/06-security-foundations-and-governance.md#root-user) |
| Root usable in member accounts | SCP denying actions by the root principal. [Org policies](../cheatsheets/org-policies-scp-rcp.md#scp-patterns) |
| Weak or single MFA | Two or more hardware security keys, stored separately |
| Root email is a personal mailbox | Group alias on a controlled domain with MFA |
| No alert on root use | EventBridge rule in every account and Region, deployed by StackSets |
| No custody record | Break-glass log with dual control |
| Root access keys existed | Config rule `iam-root-access-key-check` |
