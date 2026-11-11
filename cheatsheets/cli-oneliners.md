# CLI one-liners and queries

> **Last reviewed:** 2026-11-10 · **SCS-C03:** 1.2.4, 2.2.2, 4.2.4 · AWS CLI v2. Replace `UPPER_SNAKE` placeholders. Commands marked **[changes state]** modify resources.

## Orientation

```bash
# Who am I?
aws sts get-caller-identity

# Which Regions are enabled for this account?
aws account list-regions --region-opt-status-contains ENABLED ENABLED_BY_DEFAULT --query 'Regions[].RegionName' --output text

# Run a command in every enabled Region
for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "== $r"; aws guardduty list-detectors --region "$r" --query 'DetectorIds' --output text
done
```

## IAM

```bash
# Credential report: users, key ages, MFA, last use
aws iam generate-credential-report
aws iam get-credential-report --query Content --output text | base64 -d > credential-report.csv

# Access keys for a user, and when one was last used
aws iam list-access-keys --user-name USER_NAME
aws iam get-access-key-last-used --access-key-id ACCESS_KEY_ID

# Everything in the account: users, groups, roles, policies
aws iam get-account-authorization-details > iam-snapshot.json

# What is attached to a role?
aws iam list-attached-role-policies --role-name ROLE_NAME
aws iam list-role-policies --role-name ROLE_NAME
aws iam get-role --role-name ROLE_NAME --query 'Role.AssumeRolePolicyDocument'

# Who has this managed policy?
aws iam list-entities-for-policy --policy-arn POLICY_ARN

# Would this principal be allowed?
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::111122223333:role/ROLE_NAME \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::BUCKET/KEY

# Decode an encoded authorization failure message
aws sts decode-authorization-message --encoded-message ENCODED_MESSAGE --query DecodedMessage --output text

# Services a role has actually used (start job, then fetch)
aws iam generate-service-last-accessed-details --arn arn:aws:iam::111122223333:role/ROLE_NAME
aws iam get-service-last-accessed-details --job-id JOB_ID

# Access Analyzer active findings
aws accessanalyzer list-analyzers --query 'analyzers[].arn'
aws accessanalyzer list-findings --analyzer-arn ANALYZER_ARN --filter '{"status":{"eq":["ACTIVE"]}}'

# Validate a policy document
aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file://policy.json
```

**Containment [changes state]**

```bash
# Deactivate an access key
aws iam update-access-key --user-name USER_NAME --access-key-id ACCESS_KEY_ID --status Inactive

# Remove console access
aws iam delete-login-profile --user-name USER_NAME

# Revoke all current sessions of a role (set the time to now, UTC)
aws iam put-role-policy --role-name ROLE_NAME --policy-name RevokeOlderSessions --policy-document '{
  "Version":"2012-10-17",
  "Statement":[{"Effect":"Deny","Action":"*","Resource":"*",
    "Condition":{"DateLessThan":{"aws:TokenIssueTime":"2026-11-10T14:00:00Z"}}}]}'
```

## CloudTrail

```bash
# Trails, their status, and what they capture
aws cloudtrail describe-trails --query 'trailList[].[Name,IsMultiRegionTrail,IsOrganizationTrail,LogFileValidationEnabled,KmsKeyId]' --output table
aws cloudtrail get-trail-status --name TRAIL_NAME
aws cloudtrail get-event-selectors --trail-name TRAIL_NAME

# Last 90 days of management events, by access key / user / event name
aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=ACCESS_KEY_ID --max-results 50
aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=USER_OR_SESSION_NAME
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --start-time 2026-11-01T00:00:00Z --end-time 2026-11-10T00:00:00Z

# Prove log integrity
aws cloudtrail validate-logs --trail-arn TRAIL_ARN --start-time 2026-10-01T00:00:00Z --end-time 2026-11-01T00:00:00Z
```

`lookup-events` searches one Region at a time and management events only. For anything larger, use Athena or CloudTrail Lake.

### Athena over CloudTrail

Assumes a table named `cloudtrail_logs` created from the CloudTrail console's Athena integration.

```sql
-- Everything a credential did
SELECT eventtime, eventsource, eventname, awsregion, sourceipaddress, useragent, errorcode
FROM cloudtrail_logs
WHERE useridentity.accesskeyid = 'ACCESS_KEY_ID'
  AND eventtime > '2026-11-01T00:00:00Z'
ORDER BY eventtime;

-- IAM persistence attempts
SELECT eventtime, useridentity.arn, eventname, requestparameters, sourceipaddress
FROM cloudtrail_logs
WHERE eventsource = 'iam.amazonaws.com'
  AND eventname IN ('CreateUser','CreateAccessKey','CreateLoginProfile','UpdateLoginProfile',
                    'AttachUserPolicy','AttachRolePolicy','PutUserPolicy','PutRolePolicy',
                    'CreateRole','UpdateAssumeRolePolicy','CreatePolicyVersion',
                    'CreateSAMLProvider','CreateOpenIDConnectProvider')
ORDER BY eventtime DESC;

-- Defense evasion
SELECT eventtime, useridentity.arn, eventsource, eventname, sourceipaddress
FROM cloudtrail_logs
WHERE eventname IN ('StopLogging','DeleteTrail','UpdateTrail','PutEventSelectors',
                    'DeleteDetector','DisableSecurityHub','StopConfigurationRecorder',
                    'DeleteFlowLogs','DeleteLogGroup','PutBucketPolicy','DeleteBucketPolicy')
ORDER BY eventtime DESC;

-- Access denied, grouped: reconnaissance shows up here
SELECT useridentity.arn, eventsource, eventname, count(*) AS denied
FROM cloudtrail_logs
WHERE errorcode IN ('AccessDenied','Client.UnauthorizedOperation','AccessDeniedException')
  AND eventtime > '2026-11-09T00:00:00Z'
GROUP BY 1,2,3 ORDER BY denied DESC LIMIT 50;

-- Role assumptions: who became what
SELECT eventtime, useridentity.arn AS caller, 
       json_extract_scalar(requestparameters, '$.roleArn') AS role,
       json_extract_scalar(responseelements, '$.credentials.accessKeyId') AS issued_key,
       sourceipaddress
FROM cloudtrail_logs
WHERE eventname = 'AssumeRole'
ORDER BY eventtime DESC LIMIT 100;

-- Root user activity
SELECT eventtime, eventname, eventsource, sourceipaddress, useragent
FROM cloudtrail_logs
WHERE useridentity.type = 'Root' AND useridentity.invokedby IS NULL
ORDER BY eventtime DESC;
```

### CloudWatch Logs Insights

```
# CloudTrail in CloudWatch Logs: failed console logins by source
fields @timestamp, userIdentity.arn, sourceIPAddress, errorMessage
| filter eventName = "ConsoleLogin" and responseElements.ConsoleLogin = "Failure"
| stats count(*) as failures by sourceIPAddress
| sort failures desc

# VPC Flow Logs: top rejected sources
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as rejects by srcAddr, dstPort
| sort rejects desc
| limit 25

# VPC Flow Logs: outbound bytes from one instance ENI by destination
filter interfaceId = "ENI_ID" and action = "ACCEPT"
| stats sum(bytes) as total by dstAddr
| sort total desc
| limit 25

# Resolver query logs: most-queried domains from one instance
filter srcids.instance = "INSTANCE_ID"
| stats count(*) as queries by query_name
| sort queries desc
| limit 50
```

## S3

```bash
# Account-level Block Public Access
aws s3control get-public-access-block --account-id 111122223333

# Bucket: BPA, policy status, policy, encryption, versioning, object lock, logging
aws s3api get-public-access-block --bucket BUCKET
aws s3api get-bucket-policy-status --bucket BUCKET
aws s3api get-bucket-policy --bucket BUCKET --query Policy --output text
aws s3api get-bucket-encryption --bucket BUCKET
aws s3api get-bucket-versioning --bucket BUCKET
aws s3api get-object-lock-configuration --bucket BUCKET
aws s3api get-bucket-logging --bucket BUCKET

# [changes state] Turn on all Block Public Access settings for the account
aws s3control put-public-access-block --account-id 111122223333 \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# List versions and delete markers under a prefix (recovery)
aws s3api list-object-versions --bucket BUCKET --prefix PREFIX
```

## EC2 and network

```bash
# Security groups open to the world
aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0 \
  --query 'SecurityGroups[].[GroupId,GroupName,VpcId]' --output table

# Instances not requiring IMDSv2
aws ec2 describe-instances --filters Name=metadata-options.http-tokens,Values=optional \
  --query 'Reservations[].Instances[].InstanceId' --output text

# [changes state] Require IMDSv2 on an instance
aws ec2 modify-instance-metadata-options --instance-id INSTANCE_ID --http-tokens required --http-endpoint enabled

# Instances with public IPs
aws ec2 describe-instances --query 'Reservations[].Instances[?PublicIpAddress!=`null`].[InstanceId,PublicIpAddress]' --output table

# EBS encryption by default
aws ec2 get-ebs-encryption-by-default
# [changes state]
aws ec2 enable-ebs-encryption-by-default

# Public snapshots and AMIs owned by this account
aws ec2 describe-snapshots --owner-ids self --restorable-by-user-ids all --query 'Snapshots[].SnapshotId'
aws ec2 describe-images --owners self --filters Name=is-public,Values=true --query 'Images[].ImageId'

# Flow logs and their delivery status
aws ec2 describe-flow-logs --query 'FlowLogs[].[FlowLogId,ResourceId,LogDestinationType,DeliverLogsStatus]' --output table

# Instances managed by Systems Manager, and patch state
aws ssm describe-instance-information --query 'InstanceInformationList[].[InstanceId,PingStatus,AgentVersion]' --output table
aws ssm describe-instance-patch-states --instance-ids INSTANCE_ID

# Shell without SSH
aws ssm start-session --target INSTANCE_ID
```

## KMS

```bash
aws kms list-aliases --query 'Aliases[].[AliasName,TargetKeyId]' --output table
aws kms describe-key --key-id KEY_ID --query 'KeyMetadata.[KeyState,KeyManager,Origin,MultiRegion,DeletionDate]'
aws kms get-key-policy --key-id KEY_ID --policy-name default --query Policy --output text
aws kms get-key-rotation-status --key-id KEY_ID
aws kms list-grants --key-id KEY_ID

# [changes state] Stop a deletion, then re-enable
aws kms cancel-key-deletion --key-id KEY_ID
aws kms enable-key --key-id KEY_ID

# [changes state] Reversible kill switch
aws kms disable-key --key-id KEY_ID
```

## RDS

```bash
# Publicly accessible or unencrypted instances
aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==`true`].DBInstanceIdentifier'
aws rds describe-db-instances --query 'DBInstances[?StorageEncrypted==`false`].DBInstanceIdentifier'

# Who can restore this snapshot? ("all" means public)
aws rds describe-db-snapshot-attributes --db-snapshot-identifier SNAPSHOT_ID
```

## Detection services

```bash
# GuardDuty: detector, then high-severity findings
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty list-findings --detector-id "$DET" \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7},"service.archived":{"Eq":["false"]}}}'
aws guardduty get-findings --detector-id "$DET" --finding-ids FINDING_ID

# Security Hub: active critical findings
aws securityhub get-findings --max-items 20 --filters '{
  "SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}],
  "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
  "WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]}'

# Config: recorder running? which rules are failing? history of one resource
aws configservice describe-configuration-recorder-status
aws configservice describe-compliance-by-config-rule --compliance-types NON_COMPLIANT \
  --query 'ComplianceByConfigRules[].ConfigRuleName'
aws configservice get-resource-config-history --resource-type AWS::EC2::SecurityGroup --resource-id SG_ID --limit 5
```

## Organizations

```bash
aws organizations list-accounts --query 'Accounts[].[Id,Name,Status]' --output table
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[].[Id,Name]' --output table
aws organizations list-policies-for-target --target-id ACCOUNT_OR_OU_ID --filter SERVICE_CONTROL_POLICY
aws organizations list-delegated-administrators

# [changes state] Quarantine an account by attaching a deny-all SCP
aws organizations attach-policy --policy-id QUARANTINE_POLICY_ID --target-id ACCOUNT_ID
```
