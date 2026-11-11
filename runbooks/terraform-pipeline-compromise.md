# Terraform pipeline compromise

> **Last reviewed:** 2026-11-11 · **Severity:** Critical: the deployment role can usually change everything Terraform manages · **SCS-C03:** 2.2.2, 2.2.4, 4.2.1, 4.2.3, 6.2.1 · **Terraform Associate (004):** 2a, 5d, 8b · **NIST 800-53:** IR-4, CM-3, CM-5, SI-7, SR-4, AC-6, IA-5

The **deployment role** is the IAM role the pipeline assumes to run `terraform apply`, normally through **OIDC** (OpenID Connect) federation from the CI system, so no long-term key is stored. Whoever controls the code, the runner, the dependencies, or the token controls that role. Background: [securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md), [modules](../teaching/terraform/05-modules.md), [HCP Terraform](../teaching/terraform/08-hcp-terraform.md).

## Trigger

- A change was merged and applied without the required review, or from an account that should not have merge rights
- A CI runner is compromised, or its logs show secrets printed or sent elsewhere
- `AssumeRoleWithWebIdentity` on the deployment role from a repository, branch, or environment that is not the deployment pipeline
- Deployment role activity outside a pipeline run, from an unfamiliar IP, or without a Terraform user agent
- `terraform init` fails because a provider package does not match the checksums in `.terraform.lock.hcl`, or the lock file changed in a commit nobody can explain
- A module source without a pinned version or commit changed upstream
- An HCP Terraform or CI token was leaked or used from an unknown location
- [Unexpected drift](terraform-unexpected-drift.md) attributed to the deployment role

## Triage

```bash
aws iam get-role --role-name DEPLOY_ROLE --query 'Role.AssumeRolePolicyDocument'
aws iam list-attached-role-policies --role-name DEPLOY_ROLE
aws iam list-role-policies --role-name DEPLOY_ROLE
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time START_TIME --query 'Events[].CloudTrailEvent' --output text \
  | jq -c 'select(.requestParameters.roleArn | endswith(":role/DEPLOY_ROLE")) | {eventTime, sub: .userIdentity.userName, session: .requestParameters.roleSessionName, sourceIPAddress}'
```

The `sub` value names the repository and ref that asked for the role, for example `repo:ORG/REPO:ref:refs/heads/main` for GitHub Actions **(verify)**. Establish:

1. **Which link failed?** Code (unreviewed merge), runner, role trust (another repository or branch could assume it), dependency (provider or module), or token.
2. **What can the role do?** Administrative access in production makes this Critical.
3. **Window.** From the first suspect event (merge, token leak, upstream change) to now.

If in doubt, treat it as real. A trust policy with no `sub` condition, or a wildcard such as `repo:ORG/*`, is a finding in itself.

## Contain

**1. Stop the pipeline.** GitHub Actions shown; use the equivalent in your CI system.

```bash
gh run list --repo OWNER/REPO --status in_progress
# changes state: no new runs of this workflow start
gh workflow disable WORKFLOW_NAME --repo OWNER/REPO
```

Side effect: no deployments. Cancelling a run in the middle of an apply can leave a stuck lock and partial state; if you must, fix it afterwards with [state lock and corruption](terraform-state-lock-and-corruption.md). In HCP Terraform, lock the workspace.

**2. Block the deployment role.** An explicit deny wins over every allow and is removed with one command.

```bash
# changes state: the role can do nothing, including in sessions that already exist
aws iam put-role-policy --role-name DEPLOY_ROLE --policy-name IncidentDenyAll \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
```

**3. Revoke existing sessions** with the `aws:TokenIssueTime` deny in [Compromised IAM credentials](compromised-iam-credentials.md#contain), step 3. It stays in place after the deny-all is lifted.

**4. Tighten the trust policy** if another repository, branch, or pull request could assume the role. Save it first.

```bash
aws iam get-role --role-name DEPLOY_ROLE --query 'Role.AssumeRolePolicyDocument' > evidence/DEPLOY_ROLE-trust-before.json
# changes state: replaces who may assume the role
aws iam update-assume-role-policy --role-name DEPLOY_ROLE --policy-document file://DEPLOY_ROLE-trust-fixed.json
```

The fixed policy pins `sub` with `StringEquals` to one repository and one protected branch or environment, and `aud` to `sts.amazonaws.com`.

**5. Revoke leaked tokens** at the issuer: HCP Terraform user, team, and organization tokens; CI personal access tokens and deploy keys; registry tokens.

**6. Check for other roles** that trust the same identity provider (`aws iam list-roles` and filter on the provider ARN), in every account the pipeline deploys to. Repeat steps 2 to 4 for each.

## Preserve evidence

- CI run logs and artifacts for the window (they expire), the suspect commits, and the pull request record including who approved.
- `.terraform.lock.hcl` and `.terraform/modules/modules.json` from the runner's working directory, and the downloaded provider binaries if the runner still exists.
- The state as it stands (it holds secrets; store it in the evidence bucket):

```bash
terraform state pull > evidence/state-as-found.json
aws s3api list-object-versions --bucket STATE_BUCKET --prefix STATE_KEY --query 'Versions[].[VersionId,LastModified]' --output table
```

- A snapshot of the runner if it is self-hosted: [Compromised EC2 instance](compromised-ec2-instance.md).

## Investigate

Work from a clean responder workstation with a read-only role, not from the pipeline.

**1. Everything the deployment role did in the window.**

```sql
SELECT eventtime, awsregion, eventsource, eventname, sourceipaddress, useragent, errorcode, useridentity.principalid
FROM cloudtrail_logs
WHERE useridentity.sessioncontext.sessionissuer.arn = 'arn:aws:iam::111122223333:role/DEPLOY_ROLE'
  AND eventtime BETWEEN 'START_TIME' AND 'END_TIME'
  AND readonly = 'false'
ORDER BY eventtime;
```

Add `AND useragent NOT LIKE '%Terraform%'` to find calls made by hand with stolen credentials: the AWS provider puts `Terraform` in its user agent **(verify)**. A user agent can be forged, so its presence proves nothing. For one session, `aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=ROLE_SESSION_NAME`. Look hardest at IAM (`CreateUser`, `CreateAccessKey`, `CreateRole`, `UpdateAssumeRolePolicy`, `Attach*Policy`, `CreateOpenIDConnectProvider`) and at logging changes.

**2. Compare live infrastructure with the last known-good commit.**

```bash
git worktree add ../known-good GOOD_COMMIT && cd ../known-good
terraform init -lockfile=readonly
terraform plan -lock=false -out=compare.tfplan      # -lock=false: a read-only role cannot write the lock, and the pipeline is stopped
terraform show -json compare.tfplan | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(",")) \(.address)"'
```

Every line is something the suspect runs changed, something in state that the good code does not declare (shown as delete), or drift. Read, do not apply.

**3. Check state for injected resources.**

```bash
diff <(jq -r '.resources[] | "\(.module // "root") \(.type).\(.name)"' evidence/state-GOOD_VERSION_ID.json | sort) \
     <(jq -r '.resources[] | "\(.module // "root") \(.type).\(.name)"' evidence/state-as-found.json | sort)
```

**4. Verify providers.** `init -lockfile=readonly` verifies downloaded packages against the checksums already recorded and refuses to change the lock file. Then check the lock file itself:

```bash
git diff GOOD_COMMIT HEAD -- .terraform.lock.hcl
# in a scratch copy of the configuration: build a fresh lock file from the registry and compare
cp .terraform.lock.hcl ../committed.lock.hcl && rm .terraform.lock.hcl
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
diff ../committed.lock.hcl .terraform.lock.hcl
```

List every platform your team and runners use, or the fresh file will lack hashes the committed one has.

A provider whose source address, version, or hashes changed without a matching pull request is suspect. `providers lock` reports the signing key of each package; check it is the publisher you expect.

**5. Verify modules.** `git diff GOOD_COMMIT HEAD -- '*.tf' | grep -E 'source|version'`, and compare `.terraform/modules/modules.json` with the sources in code. A Git source pinned to a branch or tag can change without any commit in your repository.

**6. What the runner could reach.** Every secret, token, and variable set exposed to the compromised job is compromised.

## Eradicate

- Revert the malicious commits; remove attacker accounts, deploy keys, webhooks, and workflow changes from the repository and CI system.
- Remove attacker-created resources. Those in state: plan and apply from the known-good commit. Those outside state: by hand, in every Region.
- Remove persistence in IAM per the credentials runbook, including identity providers and trust policy statements.
- Rebuild runners from a clean image. Clear provider and module caches and any plugin mirror.
- Pin the tampered provider or module to a verified version or commit, and regenerate the lock file from the registry.
- Rotate every secret the pipeline held and every secret in state that the role or runner could read: [Terraform state exposure](terraform-state-exposure.md#eradicate).

## Recover

1. Restore the trust policy in its tightened form and re-enable the workflow.
2. Before unblocking the role, repeat the read-only plan from Investigate step 2 against the commit you intend to deploy. It should show only the reversions you expect.
3. Remove the deny (changes state): `aws iam delete-role-policy --role-name DEPLOY_ROLE --policy-name IncidentDenyAll`. Leave the session-revocation policy.
4. Apply, then confirm `terraform plan -detailed-exitcode` returns `0`.
5. Watch the role's activity and new `AssumeRoleWithWebIdentity` subjects closely for two weeks.

## Follow up

| Gap | Fix |
|---|---|
| Unreviewed change reached apply | Branch protection, required reviews from code owners, no self-approval, apply only from a protected branch or environment with a manual approval |
| Trust policy too broad | `StringEquals` on `sub` and `aud`; one role per repository and environment. [Policy evaluation](../cheatsheets/iam-policy-evaluation.md), [lab 04](../labs/04-iam-least-privilege/README.md) |
| One role planned and applied | Separate read-only plan role (pull requests) and apply role (protected branch only) |
| Deployment role was administrator | Least privilege, a permissions boundary on the role and on every role it creates, SCP backstops for logging, identity providers, and organization changes. [Org policies](../cheatsheets/org-policies-scp-rcp.md#scp-patterns) |
| Provider or module could change underneath you | Commit `.terraform.lock.hcl`; `terraform init -lockfile=readonly` in CI; `version` constraints on registry modules; Git sources pinned to a commit SHA. [Terraform CLI cheatsheet](../cheatsheets/terraform-cli.md) |
| Long-lived tokens in CI | OIDC to AWS; short-lived or dynamic credentials for HCP Terraform; secrets scoped to protected environments |
| Bad configuration not caught before apply | Policy checks and `terraform test` in the pipeline. [Lab 07](../labs/07-tests-and-guardrails/README.md), [AWS provider security cheatsheet](../cheatsheets/terraform-aws-provider-security.md) |
| Slow detection | Alert on `AssumeRoleWithWebIdentity` with an unexpected `sub`, on deployment role use outside pipeline runs, and on `UpdateAssumeRolePolicy`. [Lab 08](../labs/08-detection-baseline/README.md) |
| Controls not mapped | [IaC control mapping](../control-mappings/services/iac-terraform.md) |
