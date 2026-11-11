# Labs

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2a–2d, 3a–3g, 4a–4h, 5a–5d, 6a–6d, 7a–7c · **SCS-C03:** 6.2.1 · **Emulator:** [floci](https://github.com/floci-io/floci) · **Related:** [Terraform blueprint](../exam/terraform-associate-blueprint.md), [Terraform study plan](../exam/terraform-study-plan.md)

Hands-on Terraform labs that run against floci, a local AWS emulator. Nothing here touches a real AWS account, costs money, or needs real credentials. Each lab is a folder with a `README.md` to follow and a complete, working configuration.

## Index

| Lab | You practice | Terraform Associate (004) | SCS-C03 |
|---|---|---|---|
| [01 First apply](01-first-apply/README.md) | The core workflow on a hardened S3 bucket; reading a plan | 3a–3g | 6.2.1 |
| [02 Remote state](02-remote-state/README.md) | S3 backend, state locking, encrypting state, finding secrets in state | 2d, 6a–6c | 6.2.1 |
| [03 Variables and modules](03-variables-and-modules/README.md) | Typed variables, validation, `for_each`, writing and versioning a module | 4c–4e, 4g, 5a–5d | 6.2.1 |
| [04 IAM least privilege](04-iam-least-privilege/README.md) | Roles, policy documents, permissions boundaries, references and dependencies | 4a, 4b, 4f | 4.2.1–4.2.3 |
| [05 KMS and secrets](05-kms-and-secrets/README.md) | Key policies, Secrets Manager, keeping secret values out of state | 4h | 5.2.1, 5.3.2 |
| [06 Drift and import](06-drift-and-import/README.md) | Out-of-band changes, refresh-only plans, `import`, `moved`, and `removed` blocks, state inspection | 6d, 7a–7c | 6.2.1 |
| [07 Tests and guardrails](07-tests-and-guardrails/README.md) | `terraform test`, preconditions, postconditions, `check` blocks | 4g | 6.2.1 |
| [08 Detection baseline](08-detection-baseline/README.md) | Multiple provider configurations; CloudTrail, EventBridge, and SNS as code | 2c | 1.1.4, 1.2.2 |

Do them in order. Later labs assume the habits from earlier ones.

## What you need

| Tool | Version | Check |
|---|---|---|
| Docker | 23.0 or later, with `docker compose` v2 **(verify)** | `docker compose version` |
| Terraform | 1.12 or later (the version the 004 exam tests) | `terraform version` |
| AWS CLI | v2 | `aws --version` |

## Start the emulator

```bash
cd labs
docker compose up -d                              # [changes state] starts floci on port 4566
curl -s http://localhost:4566/_floci/health       # lists emulated services as "running"
```

Point the AWS CLI at the emulator for the rest of your shell session. floci accepts any non-empty credentials.

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
aws sts get-caller-identity                       # Account is 000000000000
```

`AWS_ENDPOINT_URL` sends every AWS CLI v2 call to floci. The Terraform AWS provider reads it too, so while it is set, a service missing from a lab's `endpoints` block still reaches floci. Unset it before you use the CLI or Terraform against real AWS.

Stop the emulator and discard everything it holds:

```bash
docker compose down                               # [changes state] deletes all emulated resources
```

[docker-compose.yml](docker-compose.yml) uses `FLOCI_STORAGE_MODE: memory`, so emulated resources vanish when the container stops. Terraform state files in a lab folder do not. If you restart floci mid-lab, delete the lab's `terraform.tfstate` or Terraform will plan against resources that no longer exist. That mismatch is itself a useful thing to see once.

## How a lab is laid out

```
labs/NN-name/
  README.md       the lab: goal, steps, verification, things to break, clean-up
  providers.tf    Terraform and provider settings that point at floci
  *.tf            the finished configuration the steps walk through
```

Every lab `README.md` has the same sections:

1. **Goal**: what you will be able to do afterward.
2. **Before you start**: prerequisites and the notes to read first.
3. **Steps**: numbered, with every command copy-pasteable.
4. **Verify**: commands that prove the result, with the output to expect.
5. **Break it**: deliberate mistakes to make, what you should see, and why.
6. **Clean up**: how to remove everything the lab created.
7. **What differs on real AWS**: where the emulator is more forgiving than AWS, and what the lab-only provider settings would be replaced with.

New labs start from [_template/](_template/README.md).

## The lab provider block

Every lab's `providers.tf` carries the same provider settings:

```hcl
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.floci_endpoint
    sts = var.floci_endpoint
  }
}
```

| Setting | Why the lab needs it | On real AWS |
|---|---|---|
| `access_key`, `secret_key` | floci accepts any non-empty value | Never in configuration. Credentials come from the environment, an assumed role, or OIDC. See [AWS provider security](../cheatsheets/terraform-aws-provider-security.md). |
| `skip_*` flags | Stop the provider from calling real STS and the instance metadata service | Remove |
| `s3_use_path_style` | `localhost` has no per-bucket DNS names | Remove |
| `endpoints` | Sends each listed service's API calls to floci without relying on your shell. With `AWS_ENDPOINT_URL` unset, a service you use but do not list goes to real AWS and fails. | Remove |

## Limits of the emulator

floci emulates API behavior, not AWS's security enforcement. Keep these in mind when a lab "works":

- **IAM policies are not enforced by default.** A principal with no permissions can still call any API. Labs that teach least privilege say how they demonstrate it.
- **The account ID is `000000000000`** unless the access key is a 12-digit number, in which case floci uses that number as the account ID **(verify)**.
- **KMS ciphertext is emulator-specific** and cannot be decrypted by real AWS KMS.
- **Eventual consistency, service quotas, and API throttling are not emulated.** Real applies are slower and fail in ways the emulator does not.
- **Coverage varies by service.** The [floci services overview](https://floci.io/floci/services/) lists what is implemented **(verify)**.

Passing a lab proves your Terraform is well-formed and your workflow is sound. It does not prove a policy is correct or that a real apply will succeed.

## Tested with

Last run on 2026-11-11 with Terraform 1.17.1, AWS provider 6.72.0, random provider 3.9.1, AWS CLI 2.40.0, and floci nightly-11102026 (native Linux build, not the Docker image) **(verify)**.

| Labs | Test status |
|---|---|
| 01, 02, 03, 07 | Run end to end: every step, Verify command, "Break it" exercise, and clean-up |
| 04, 05, 06, 08 | Smoke-tested only: `init`, `validate`, `apply`, Verify, `destroy`. Step-by-step outputs and "Break it" exercises are described but have not been run. Each of these READMEs carries a **Test status** line. |

`docker-compose.yml` itself has not been run; the emulator was started from its native build for these tests. If a step fails on a newer version, check the lab's "What differs on real AWS" section and the provider changelog first.

## Lab safety

- Run the labs only against the emulator. The fake credentials make a misdirected call to real AWS fail, which is the point of using them.
- Do not copy a lab `providers.tf` into real work. Start real configurations from the patterns in [Securing Terraform on AWS](../teaching/terraform/09-securing-terraform-on-aws.md).
- Lab state files contain whatever secrets the lab created. They are fake, but treat the habit as real: the repo's `.gitignore` excludes `*.tfstate`, and you should never commit one.
