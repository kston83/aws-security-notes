# Terraform 2: Terraform Fundamentals

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2a–2d · **SCS-C03:** 6.2.1 · **Related:** [IaC with Terraform](01-iac-with-terraform.md), [core workflow](03-core-workflow.md), [state management](06-state-management.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [AWS provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md), [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md), [lab 01: first apply](../../labs/01-first-apply/README.md)

## Why this matters

A provider is third-party code that runs with your deployment credentials. Whoever controls which provider binary gets downloaded controls what happens in your accounts. Version constraints and the dependency lock file are how you decide that, which makes them supply-chain controls and not housekeeping.

State is the other fundamental. It is the record that ties your code to real resources, it is required for Terraform to work at all, and it holds resource attributes in plain text, secrets included.

## Mental model

**Terraform core is a planner. Providers do the work. State is the memory.**

```
  terraform init
       │  reads required_providers
       ▼
  Terraform Registry ──download──▶ .terraform/providers/   (binaries; never committed)
  (or a mirror)                    .terraform.lock.hcl      (versions + checksums; committed)

  terraform plan / apply
       │
  Terraform core ──RPC──▶ provider process ──HTTPS──▶ AWS APIs
       │                  (one per provider;
       │                   one configuration per alias)
       ▼
  State: aws_s3_bucket.logs  ⇄  bucket "audit-logs-111122223333"
```

| Piece | What it is | Where it lives |
|---|---|---|
| **Terraform core** | The `terraform` binary: parses HCL, builds the graph, computes the plan | Your machine or the pipeline runner |
| **Provider** | A plugin that knows one API: resource types, data sources, how to create, read, update, delete | Downloaded by `terraform init` into `.terraform/` |
| **Provider requirement** | Which provider and which versions are acceptable | `required_providers` in the `terraform` block |
| **Provider configuration** | How to reach the API: Region, credentials, role to assume | `provider` blocks |
| **Dependency lock file** | The exact versions and checksums selected | `.terraform.lock.hcl`, committed to version control |
| **State** | The mapping from resource addresses to real objects, plus their last known attributes | `terraform.tfstate` locally, or a remote backend |

## Objective 2a: Install and version providers

### Declaring a requirement

```hcl
terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

- **`required_version`** constrains the Terraform CLI itself. It has nothing to do with providers.
- The key (`aws`) is the provider's **local name** inside this module.
- **`source`** is the provider's address: `HOSTNAME/NAMESPACE/TYPE`. The hostname is optional and defaults to `registry.terraform.io`, so `hashicorp/aws` means `registry.terraform.io/hashicorp/aws`.
- **`version`** is a constraint, not a pin. With no constraint, any version is acceptable. Always set one.

If a provider has no `required_providers` entry at all, Terraform assumes `registry.terraform.io/hashicorp/NAME`. That only works for providers in the `hashicorp` namespace and is a common source of "provider not found" errors for others.

### Version constraints

| Operator | Meaning | Example | Allows |
|---|---|---|---|
| `=` or none | Exactly this version | `= 6.4.0` | 6.4.0 only |
| `!=` | Exclude this version | `!= 6.4.1` | Anything else |
| `>`, `>=`, `<`, `<=` | Comparison | `>= 6.0` | 6.0 and newer, including 7.x |
| `~>` | **Pessimistic**: only the rightmost component may increase | `~> 6.0` | 6.1, 6.20, not 7.0 |
| | | `~> 6.4.0` | 6.4.1, 6.4.9, not 6.5.0 |

Combine with commas; all must hold: `>= 6.2, < 7.0`. Pre-release versions such as `7.0.0-beta1` are matched only by an exact constraint.

HashiCorp's guidance: **root modules** set a lower and an upper bound (`~>`), and **reusable modules** set only a minimum (`>=`) so the caller decides the maximum.

### Installing

`terraform init` installs providers. It reads every `required_providers` block in the root module and its child modules, finds a version that satisfies all of them, downloads it into `.terraform/providers/`, and records the choice in the lock file. Details of the command are in [core workflow](03-core-workflow.md).

Sources Terraform can install from:

| Source | Use |
|---|---|
| Public Terraform Registry | The default |
| Private registry (HCP Terraform or Terraform Enterprise) | Internal providers |
| **Network or filesystem mirror** | Air-gapped or controlled environments; configured in the CLI configuration file, or with `terraform init -plugin-dir=PATH` |
| Plugin cache (`TF_PLUGIN_CACHE_DIR`) | Avoids re-downloading the same provider for every working directory |

Registry providers carry a tier badge: **official** (maintained by HashiCorp), **partner** (maintained by the vendor and verified by HashiCorp), and **community**. The badge tells you who publishes the code, not that it is safe.

### The dependency lock file

`.terraform.lock.hcl` is created and updated by `terraform init` in the root module directory.

```hcl
# This file is maintained automatically by "terraform init".
provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.20.0"          # illustrative
  constraints = "~> 6.0"
  hashes = [
    "h1:EXAMPLEHASH=",
    "zh:examplehash",
  ]
}
```

| Fact | Detail |
|---|---|
| Tracks | **Provider** versions and checksums only. Module versions are not locked; pin those with an exact `version` in the `module` block. |
| When a provider is already locked | `init` reselects the recorded version, even if a newer one satisfies the constraint |
| To move to a newer version | `terraform init -upgrade`, then review and commit the lock file change |
| Checksums | `h1:` hashes the package contents; `zh:` is the legacy hash of the official zip. A downloaded package matching none of the recorded hashes is an error. |
| Trust model | **Trust on first use**: the first `init` records what it received; later runs verify against it |
| Other platforms | `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` records hashes for platforms other than the one you ran `init` on |
| In pipelines | `terraform init -lockfile=readonly` verifies against the lock file and refuses to change it |
| Version control | **Commit it.** Do not commit the `.terraform/` directory. |

Constraint and lock file do different jobs. The constraint says what is acceptable. The lock file says what was chosen. Everyone who runs `init` against the same lock file gets the same provider build.

Useful commands: `terraform version` prints the CLI and selected provider versions. `terraform providers` prints which providers the configuration and state require.

## Objective 2b: How Terraform uses providers

- A provider is a **separate executable**. Terraform core starts it and talks to it over a local RPC channel. Core never calls AWS directly.
- A provider supplies **resource types** (`aws_s3_bucket`), **data sources** (`aws_caller_identity`), and, in newer versions, functions and ephemeral resources. The prefix of the type name (`aws_`) tells Terraform which provider owns it.
- Providers are released on their own schedule, separately from Terraform itself. Upgrading one does not upgrade the other.
- Every resource belongs to exactly one **provider configuration**. State remembers which, so removing a provider configuration while resources that use it are still in state causes an error. Destroy or move the resources first.
- Provider arguments must be known before the run starts. They can use variables and locals, not attributes of resources that do not exist yet.

A typical AWS configuration:

```hcl
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["111122223333"]

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Owner     = "security-engineering"
    }
  }
}
```

- **Credentials** come from the standard AWS chain: environment variables, shared config and credentials files, IAM Identity Center sessions, container or instance roles. Never write `access_key` and `secret_key` in the block. (The labs do, with fake values, only because they talk to an emulator.)
- **`allowed_account_ids`** makes the provider refuse to run against any other account. It is a cheap guard against applying prod code with dev credentials or the reverse.
- **`default_tags`** applies tags to every taggable resource this configuration creates.

More provider arguments with a security purpose are in the [AWS provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md).

## Objective 2c: Multiple provider configurations

Two different things go by "multiple providers":

**Different providers in one configuration.** Add each to `required_providers` and give each a `provider` block. Resources select their provider by type prefix.

```hcl
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
```

**Several configurations of the same provider.** Used for more than one account or Region. One block has no `alias` and is the **default**. The others each get an **`alias`**.

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "log_archive"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::444455556666:role/terraform-deploy"
  }
}

resource "aws_s3_bucket" "app" {
  bucket = "app-data-111122223333"
}

resource "aws_s3_bucket" "audit" {
  provider = aws.log_archive
  bucket   = "audit-logs-444455556666"
}
```

- A resource or data source with no `provider` argument uses the default configuration.
- `provider = aws.log_archive` selects an alias. It is a reference, not a string, so no quotes.
- **Modules** receive the default configuration automatically. Aliased ones must be passed explicitly, and the child module must declare that it expects them:

```hcl
# Root module
module "replica" {
  source = "./modules/log-replica"

  providers = {
    aws         = aws
    aws.replica = aws.log_archive
  }
}

# modules/log-replica/versions.tf
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0"
      configuration_aliases = [aws.replica]
    }
  }
}
```

- Do not put `provider` blocks inside reusable modules. Configure providers in the root and pass them down.

**Regions in AWS provider v6.** From v6.0.0, most Regional resources accept a `region` argument that overrides the provider's Region for that resource, so a second Region no longer needs an alias. Changing `region` on an existing resource replaces it. Global services such as IAM, Route 53, CloudFront, and Organizations do not have the argument. Aliases remain the way to reach a **different account or role**, and existing multi-Region alias configurations still work.

```hcl
resource "aws_kms_key" "replica_region" {
  region              = "us-west-2"
  description         = "Log encryption key, second Region"
  enable_key_rotation = true
}
```

## Objective 2d: What state is and why Terraform needs it

**State** is Terraform's record of the resources it manages. By default it is a JSON file named `terraform.tfstate` in the working directory (the **local backend**). A **remote backend**, such as S3 or HCP Terraform, stores it somewhere shared.

Why Terraform cannot work without it:

| Purpose | Explanation |
|---|---|
| **Mapping to the real world** | Configuration says `aws_s3_bucket.audit`. AWS knows a bucket name. State links the two. Each real object is bound to one resource address. |
| **Metadata** | State keeps dependency order and which provider configuration created each resource. When you delete a block from the code, state is the only place that still knows the resource exists and in what order to destroy it. |
| **Performance** | State caches attributes, so Terraform does not have to rediscover everything. On large estates the refresh can be skipped (`-refresh=false`) and the cache trusted. |
| **Collaboration** | With remote state and **locking**, every run starts from the latest state and two runs cannot write at once. |

How it is used during a run:

1. Read the state.
2. **Refresh**: ask the provider for the current attributes of every resource in state.
3. Compare the refreshed state with the configuration. The difference is the plan.
4. On apply, make the changes and write the new state.

Consequences worth holding on to:

- Terraform manages only what is in state. A resource created by hand is invisible to it until it is **imported**.
- A resource in state but removed from configuration is planned for **destruction**.
- **State is sensitive.** Resource attributes are stored in plain text, including database passwords, generated keys, and anything else a provider returns. Marking a value `sensitive` hides it from CLI output only; it is still in the state file. Ephemeral values and write-only arguments, added in Terraform 1.10 and 1.11 **(verify)**, are the mechanisms that keep a value out of state altogether.
- Do not edit the state file by hand and do not commit it to version control. Use the `terraform state` commands.
- Losing state does not delete the infrastructure. It makes Terraform forget it, and the next apply tries to create everything again.

That is the "what and why". Backends, locking, the `backend` block, and drift are in [state management](06-state-management.md), with commands in the [state and backends cheatsheet](../../cheatsheets/terraform-state-and-backends.md) and practice in [lab 02: remote state](../../labs/02-remote-state/README.md). If a state file is exposed, follow the [state exposure runbook](../../runbooks/terraform-state-exposure.md).

## Worked examples

**1. A pipeline run fails on Monday with an error from a provider release published over the weekend. Nothing in the repository changed.**
The lock file was not committed, so each run selected the newest version allowed by the constraint. Commit `.terraform.lock.hcl` and run `terraform init -lockfile=readonly` in the pipeline. Upgrades then happen only when someone runs `terraform init -upgrade` and the lock file diff passes review.

**2. A developer on macOS commits the lock file. The Linux pipeline fails because the provider package does not match any recorded checksum.**
The lock file holds hashes only for the platform that ran `init`. Run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` and commit the result.

**3. Application buckets live in account 111122223333. Their access logs must land in a bucket in the log archive account 444455556666, created by the same change.**
Two `aws` provider configurations: the default for the workload account, and an alias that assumes a deployment role in the log archive account. The audit bucket sets `provider = aws.log_archive`. Add `allowed_account_ids` to each block so neither can run against the wrong account.

**4. A security review finds a database master password readable in an S3 object.**
It is the Terraform state. The resource's `password` argument was stored along with every other attribute. Rotate the password, then treat it as an exposure: [state exposure runbook](../../runbooks/terraform-state-exposure.md). Long term, restrict and encrypt the state bucket and move the secret to a write-only argument or to Secrets Manager-managed credentials: see [securing Terraform on AWS](09-securing-terraform-on-aws.md).

## Pitfalls and exam traps

- `required_version` is for the Terraform CLI. Provider versions go in `required_providers`.
- The `version` argument inside a `provider` block is deprecated. Constraints belong in `required_providers`.
- `~> 6.0` allows any 6.x. `~> 6.0.0` allows only 6.0.x. One extra digit changes the meaning.
- The lock file locks **providers, not modules**.
- `terraform init` alone never upgrades a locked provider. `-upgrade` does.
- Commit `.terraform.lock.hcl`. Do not commit `.terraform/` or `*.tfstate`.
- An omitted `source` implies the `hashicorp` namespace. Partner and community providers must state their source.
- `alias` goes in the `provider` block. `provider = aws.NAME` goes in the resource. `providers = { … }` (plural) goes in the `module` block.
- Only one configuration per provider can be the default (no alias).
- In AWS provider v6, a second Region does not need an alias; a second account does.
- The `sensitive` flag does not encrypt or remove anything in state.
- State is required. There is no mode in which Terraform manages resources without it.
- Installing a provider does not configure it. `init` downloads; the `provider` block and credentials configure.

## Self-check

1. Which block declares the acceptable versions of a provider, and which command installs it?
2. What versions does `~> 6.4` allow? What about `~> 6.4.0`?
3. A provider is locked at 6.10.0 and the constraint is `~> 6.0`. Version 6.20.0 is released. What does `terraform init` install, and how do you move to the new version?
4. What does the dependency lock file record, and what does it not record?
5. Why is a committed lock file a security control?
6. Write the resource argument that selects a provider configuration whose alias is `log_archive`.
7. How does a child module receive an aliased provider configuration?
8. Give three reasons Terraform needs state, and one reason the state file is sensitive.

<details>
<summary>Answers</summary>

1. `required_providers` inside the `terraform` block. `terraform init` installs it.
2. `~> 6.4` allows 6.4 and any later 6.x, not 7.0. `~> 6.4.0` allows 6.4.x only.
3. 6.10.0, because the lock file wins while it still satisfies the constraint. Run `terraform init -upgrade` and commit the updated lock file.
4. It records the selected version, the constraint, and package checksums for each provider. It does not record module versions or the Terraform CLI version.
5. Every run installs the same provider build and verifies it against recorded checksums, so a changed or substituted package fails `init`, and upgrades arrive as a reviewable diff.
6. `provider = aws.log_archive`
7. The calling `module` block passes it in the `providers` map, and the child declares it with `configuration_aliases` in its `required_providers` entry.
8. Mapping configuration to real objects; metadata such as dependency order and provider configuration for resources removed from code; a performance cache; a shared, locked record for teams. It is sensitive because it stores resource attributes, including secrets, in plain text.

</details>

## Further reading

- [Provider requirements](https://developer.hashicorp.com/terraform/language/providers/requirements)
- [Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration)
- [Version constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)
- [Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)
- [`terraform providers lock`](https://developer.hashicorp.com/terraform/cli/commands/providers/lock)
- [Purpose of Terraform state](https://developer.hashicorp.com/terraform/language/state/purpose)
- [Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data)
- [AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS provider: enhanced Region support](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/enhanced-region-support)
