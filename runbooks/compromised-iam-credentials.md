# Compromised IAM credentials

> **Last reviewed:** 2026-11-10 · **Severity:** High; Critical if administrative · **SCS-C03:** 2.2.2, 2.2.4, 4.1.2 · **NIST 800-53:** IR-4, AC-2, IA-5, AU-6

## Trigger

- GuardDuty `*:IAMUser/*` finding
- AWS Health event or support case about exposed credentials (AWS may attach the `AWSCompromisedKeyQuarantine` policy to the user)
- A key found in a repository, log, ticket, or chat
- Unexpected CloudTrail activity or billing spike
- A user reports phishing or a lost device

## Triage

Identify the credential type from the access key ID prefix:

| Prefix | Type | Containment |
|---|---|---|
| `AKIA` | Long-term IAM user access key | Deactivate the key |
| `ASIA` | Temporary credentials from STS (role session, federated session) | Revoke sessions on the role |
| Console password | IAM user sign-in | Reset password, check MFA devices |

Find the owner:

```bash
aws sts get-access-key-info --access-key-id ACCESS_KEY_ID          # which account
aws iam list-users --query 'Users[].UserName' --output text | tr '\t' '\n' | while read u; do
  aws iam list-access-keys --user-name "$u" --query "AccessKeyMetadata[?AccessKeyId=='ACCESS_KEY_ID'].[UserName,Status,CreateDate]" --output text
done
aws iam get-access-key-last-used --access-key-id ACCESS_KEY_ID
```

For an `ASIA` key, find the session in CloudTrail to get the role and session name:

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=ACCESS_KEY_ID --max-results 5 \
  --query 'Events[].CloudTrailEvent' --output text
```

Note what the principal is allowed to do. That sets the severity and the scope of the search.

## Contain

Do these in order. All are reversible.

**1. Long-term access key: deactivate.**

```bash
aws iam update-access-key --user-name USER_NAME --access-key-id ACCESS_KEY_ID --status Inactive
```

Side effect: anything legitimately using the key stops. Issue a replacement after eradication.

**2. Console access: remove.**

```bash
aws iam delete-login-profile --user-name USER_NAME
aws iam list-mfa-devices --user-name USER_NAME      # look for devices the user does not recognize
```

**3. Role or federated session: revoke sessions issued before now.**

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
aws iam put-role-policy --role-name ROLE_NAME --policy-name RevokeOlderSessions --policy-document "{
  \"Version\":\"2012-10-17\",
  \"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\",
    \"Condition\":{\"DateLessThan\":{\"aws:TokenIssueTime\":\"$NOW\"}}}]}"
```

Side effect: every existing session of that role is denied. Workloads using the role through an instance profile, task role, or SDK refresh will pick up new credentials on their own. Humans must sign in again.

For an IAM user who may have called `GetSessionToken` or `AssumeRole`, attach the same deny as an inline user policy, and apply step 3 to each role they assumed (see Investigate).

**4. If the principal was administrative, or you cannot bound the damage, quarantine the account.**

```bash
aws organizations attach-policy --policy-id QUARANTINE_POLICY_ID --target-id ACCOUNT_ID
```

Needs authorization. See [runbooks README](README.md#authority-to-act). Policy text: [org policies cheatsheet](../cheatsheets/org-policies-scp-rcp.md#scp-patterns).

**5. IAM Identity Center user:** disable the user in the identity source (IdP), delete their active sessions in Identity Center, then revoke sessions on the `AWSReservedSSO_*` roles they could assume, as in step 3.

Do **not** delete the user, key, or role yet. You need them for the investigation.

## Preserve evidence

```bash
aws iam get-account-authorization-details > evidence/iam-snapshot-$(date -u +%Y%m%dT%H%M%SZ).json
aws iam generate-credential-report && aws iam get-credential-report --query Content --output text | base64 -d > evidence/credential-report.csv
```

CloudTrail logs are already in the log archive. Note the time window and export query results to the evidence bucket.

## Investigate

Use Athena or CloudTrail Lake. Query templates: [CLI one-liners](../cheatsheets/cli-oneliners.md#athena-over-cloudtrail).

1. **Everything the credential did**, from first suspicious use. Note source IPs and user agents; these help find the attacker's other sessions.
2. **Role assumptions.** Each successful `AssumeRole` returns a new access key ID in `responseElements.credentials.accessKeyId`. Repeat step 1 for each, across accounts. Revoke those roles' sessions.
3. **Persistence in IAM.** `CreateUser`, `CreateAccessKey`, `CreateLoginProfile`, `UpdateLoginProfile`, `Attach*Policy`, `Put*Policy`, `CreatePolicyVersion`, `CreateRole`, `UpdateAssumeRolePolicy`, `CreateSAMLProvider`, `CreateOpenIDConnectProvider`, `CreateVirtualMFADevice`, `EnableMFADevice`.
4. **Persistence elsewhere.** New Lambda functions or changed code, new EC2 instances and key pairs, changed user data, new EventBridge rules, new resource policy statements on buckets, keys, queues, and roles, new Identity Center assignments.
5. **Defense evasion.** See [CloudTrail tampering](cloudtrail-tampering.md).
6. **Data access.** `GetObject`, `GetSecretValue`, `GetParameter`, `Decrypt`, snapshot sharing or copying, database snapshot export. Data events must have been enabled to see object-level reads.
7. **Resource abuse.** `RunInstances` in all Regions, especially large or GPU instance types; SES sending; Bedrock invocation.
8. **Same source elsewhere.** Search all accounts for the attacker's IPs and user agents.
9. **How it leaked.** Repository history, CI logs, an instance with IMDSv1 and an SSRF flaw, a compromised laptop, phishing.

Access Analyzer external access findings will show resource policies that now grant outside access.

## Eradicate

- Delete IAM users, access keys, login profiles, roles, policies, and identity providers the attacker created.
- Revert changed policies and trust policies to the last known-good version. Config history has it.
- Remove attacker-created compute, functions, rules, and resource policy statements, in every Region.
- Rotate every secret the principal could read: Secrets Manager secrets, database passwords, API keys, and other access keys visible to it.
- Fix the leak: remove the key from the repository **and its history**, patch the vulnerable application, enforce IMDSv2.
- Delete the compromised access key once the investigation is closed.

```bash
aws iam delete-access-key --user-name USER_NAME --access-key-id ACCESS_KEY_ID
```

## Recover

- Issue new credentials to the legitimate owner. Take the chance to replace the IAM user with federation or a role.
- Detach the quarantine SCP once eradication is verified.
- Leave the session-revocation deny in place; it is harmless for new sessions.
- Watch the principal and the attacker's indicators closely for two weeks.

## Follow up

| Gap | Fix |
|---|---|
| Long-term keys exist | Identity Center for people; roles, OIDC, or Roles Anywhere for workloads. [Domain 4](../teaching/04-identity-and-access-management.md) |
| Key had broad permissions | Least privilege; permissions boundary; unused access findings |
| Key usable from anywhere | `aws:SourceIp` or `aws:SourceVpce` conditions; data perimeter |
| Secrets in code | Secret scanning in the pipeline and pre-commit |
| Slow detection | GuardDuty everywhere; alert on `CreateAccessKey` and `CreateUser`; route AWS Health events |
| IMDSv1 | Require IMDSv2 by SCP or declarative policy |
