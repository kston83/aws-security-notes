# Terraform 5: Modules

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 5a–5d · **SCS-C03:** 6.2.1 · **Related:** [configuration](04-configuration.md), [HCL cheatsheet](../../cheatsheets/terraform-hcl.md), [CLI cheatsheet](../../cheatsheets/terraform-cli.md), [securing Terraform on AWS](09-securing-terraform-on-aws.md), [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md), [lab 03](../../labs/03-variables-and-modules/README.md), [IaC control mappings](../../control-mappings/services/iac-terraform.md)

## Why this matters

A module is how a security team ships a decision once. A hardened bucket module with encryption, public access block, and TLS-only policy built in means forty teams get those controls without knowing they exist. The same mechanism is a supply-chain risk: a module is third-party code that runs with your deployment role's permissions, and an unpinned source means someone else decides what that code is on your next `terraform init`.

## Mental model

**A module is a directory of `.tf` files with an interface.** Input variables are its parameters, outputs are its return values, and everything else inside is private. The directory you run Terraform in is the **root module**. A module called from another is a **child module**. Calling one is like calling a function: the caller sees only what goes in and what comes out.

```
  root module (the directory you run terraform in)
  ├── provider "aws" { … }                 provider configurations live here
  ├── variable, locals, resources
  │
  ├── module "log_bucket"  ──────────────► child module  (source = "./modules/hardened-bucket")
  │      name        = "audit"   ─ in ──►    variable "name"
  │      kms_key_arn = aws_kms_key…          resources, data sources, locals    (private)
  │      module.log_bucket.bucket_arn ◄─ out ─ output "bucket_arn"
  │
  └── module "vpc"  ─────────────────────► child module  (source = registry, version pinned)
                                              └── may call its own child modules

  terraform init copies remote sources into .terraform/modules/. One state file holds all of it.
```

Two points that follow:

- **Modules do not have their own state.** Every resource in every child module is in the root module's state, addressed as `module.log_bucket.aws_s3_bucket.this`.
- **Modules are installed, not resolved at run time.** `terraform init` (or `terraform get`) downloads them. Change a `source` or `version` and you must run `terraform init` again.

## Objective 5a: Module sources

The `source` argument tells Terraform where to get the module. Its form selects the installer.

| Source type | Example `source` | Version selection |
|---|---|---|
| **Local path** | `"./modules/hardened-bucket"` | None. Must start with `./` or `../`. Used in place, not copied. |
| **Public Terraform Registry** | `"terraform-aws-modules/vpc/aws"` | `version` argument |
| **Private registry** (HCP Terraform or Terraform Enterprise) | `"app.terraform.io/ORG_NAME/hardened-bucket/aws"` | `version` argument |
| **GitHub** | `"github.com/ORG_NAME/terraform-aws-hardened-bucket"` | `?ref=` |
| **Generic Git** | `"git::https://example.com/storage.git?ref=v1.2.0"` or `"git::ssh://git@example.com/storage.git"` | `?ref=` takes a tag, branch, or commit SHA. Without it, the default branch. |
| **Bitbucket, Mercurial** | `"bitbucket.org/ORG_NAME/REPO_NAME"`, `"hg::https://example.com/vpc.hg"` | `?ref=` |
| **HTTP URL** | `"https://example.com/modules/vpc.zip"` | Whatever the URL serves |
| **S3 or GCS bucket** | `"s3::https://s3-us-east-1.amazonaws.com/BUCKET_NAME/vpc.zip"` | Object key (use bucket versioning and integrity controls) |

- A registry address is `NAMESPACE/NAME/PROVIDER`. A private registry address puts the hostname in front.
- A module in a subdirectory of a repository or archive is selected with a double slash: `"git::https://example.com/network.git//modules/vpc?ref=v1.2.0"`.
- Git sources use your local Git credentials, so SSH keys and credential helpers work for private repositories.
- Registry modules are published from repositories named `terraform-PROVIDER-NAME` with semantic version tags.
- In the Terraform version the exam tests, `source` and `version` must be literal strings: no variables, no interpolation. Later releases allow constant variables (`const = true`) there **(verify)**.

The **standard module structure** is `main.tf`, `variables.tf`, `outputs.tf`, and a `README.md` at the root of the module, with nested modules under `modules/` and usage examples under `examples/`.

## Objective 5b: Variable scope in modules

**Each module is its own namespace.** Names declared in one module are invisible in every other.

| From inside a child module, can you reference… | Answer |
|---|---|
| The parent's `var.x`, `local.x`, or resources | No. The parent must pass the value in as an input variable. |
| A sibling module's outputs | No. The parent wires `module.a.out` into module `b`'s input. |
| Your own variables, locals, resources, data sources | Yes |
| Provider configurations from the root | Yes, the default (unaliased) ones are inherited automatically |
| **From the parent, can you reference…** | |
| A child's resources, such as `module.log_bucket.aws_s3_bucket.this.arn` | No. Only declared outputs: `module.log_bucket.bucket_arn`. |
| A child's variables or locals | No |
| A grandchild's outputs | No. The child must re-export them as its own outputs. |

There are no global variables. Data crosses a module boundary in exactly two ways: **down** through input variables set as arguments in the `module` block, and **up** through outputs.

```hcl
# modules/hardened-bucket/variables.tf
variable "kms_key_arn" {
  type        = string
  description = "Customer managed key for default encryption."   # no default: required
}

# modules/hardened-bucket/outputs.tf
output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
```

Scope rules with a security angle:

- **A variable with no default is required.** A module author makes a control mandatory by not giving it a default, and enforces its shape with `validation`.
- **What a module does not expose cannot be changed by the caller.** If the public access block is hard-coded inside the module and has no variable, callers cannot switch it off. That is the point of a hardened module.
- **Sensitivity crosses the boundary.** A child output built from a sensitive value must be marked `sensitive = true`, or Terraform returns an error. The value is still in state; see [configuration](04-configuration.md).
- **Ephemeral values can cross too.** A variable or a child module output marked `ephemeral = true` passes a secret through a module without it being stored (Terraform 1.10 and later **(verify)**).
- Variable precedence rules (`-var`, tfvars files, `TF_VAR_`) apply only to the **root** module. Child module variables get values only from the `module` block or their defaults.

## Objective 5c: Using modules

```hcl
module "log_bucket" {
  source = "./modules/hardened-bucket"

  name        = "audit"
  kms_key_arn = aws_kms_key.logs.arn
}

resource "aws_cloudtrail" "org" {
  name           = "org-trail"
  s3_bucket_name = module.log_bucket.bucket_name     # module output
  kms_key_id     = aws_kms_key.logs.arn
}
```

Arguments in a `module` block:

| Argument | Purpose |
|---|---|
| `source` | Required. Where the module comes from. |
| `version` | Version constraint. Registry sources only. |
| Any other name | Sets the child's input variable of that name |
| `count`, `for_each` | Create several instances of the whole module |
| `providers` | Map of provider configurations to hand to the child |
| `depends_on` | Make everything in the module wait for the listed resources or modules |

**The workflow:** add the block, run `terraform init` to install it, then plan and apply as usual. Installed copies live in `.terraform/modules/`, which should not be committed.

**Multiple instances.** `for_each` on a module works like it does on a resource, and outputs are then addressed by key:

```hcl
module "team_bucket" {
  source   = "./modules/hardened-bucket"
  for_each = toset(["payments", "identity", "platform"])

  name        = each.key
  kms_key_arn = aws_kms_key.logs.arn
}
```

A single instance is `module.team_bucket["payments"].bucket_arn`; all of them, `{ for team, m in module.team_bucket : team => m.bucket_arn }`. With `count`, it is `module.NAME[0].OUTPUT_NAME`.

**Providers.** Provider *configurations* (`provider "aws" { … }`) belong in the root module only. Provider *requirements* (`required_providers`) belong in every module, because a child does not inherit source or version requirements.

- A child inherits the root's default configuration for each provider with no extra work.
- Aliased configurations are never inherited. Pass them with `providers`, and declare the names the child expects with `configuration_aliases`.
- A module that contains its own `provider` block cannot be used with `count`, `for_each`, or `depends_on`. It also cannot be removed cleanly, because Terraform needs the provider configuration to destroy its resources.

```hcl
# Root module, which also holds a default provider "aws" block
provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

module "replicated_logs" {
  source = "./modules/replicated-bucket"

  providers = {
    aws.src = aws           # key: name inside the child. value: configuration in the caller.
    aws.dst = aws.replica
  }
}

# modules/replicated-bucket/versions.tf
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0"
      configuration_aliases = [aws.src, aws.dst]
    }
  }
}
```

With AWS provider v6 many resources also take a per-resource `region` argument, which can replace an aliased provider when only the Region differs **(verify)**; an alias is still needed for a different account or role. See the [AWS provider security cheatsheet](../../cheatsheets/terraform-aws-provider-security.md).

## Objective 5d: Module versions

The `version` argument takes a **version constraint** and works only for registry sources (public or private). Using it with a local path or a Git source is an error.

| Constraint | Allows |
|---|---|
| `"6.0.1"` or `"= 6.0.1"` | Exactly that version |
| `">= 6.0.0"` | That version or newer, with no upper bound |
| `"~> 6.0"` | 6.0 and any later 6.x, not 7.0 (only the right-most component may increase) |
| `"~> 6.0.1"` | 6.0.1 and later 6.0.x patch releases, not 6.1.0 |
| `">= 6.0.0, < 6.2.0"` | Both conditions must hold |
| `"!= 6.0.3"` | Excludes one version |

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"                       # exact pin
}

module "storage" {
  source = "git::https://example.com/storage.git?ref=51d462976d84fdea54b47d80dcabbf680badcdb8"   # commit pin
}
```

How selection behaves:

- With no `version`, `terraform init` installs the **latest** version. With a range, it installs the newest version that satisfies it.
- Once installed, a module stays at its version until you run `terraform init -upgrade` or change the constraint.
- **The dependency lock file (`.terraform.lock.hcl`) records provider versions and checksums only. It does not lock modules.** A clean checkout on a CI runner has no `.terraform/modules/`, so a range can resolve to a newer release there than on your laptop. The constraint in the configuration is the only pin.
- Local modules have no version. They change when the files change, and they are versioned with the repository that holds them.

**Pinning as a supply-chain control.** A module runs inside your plan and apply with the deployment role's permissions and can add any resource, including an IAM role that trusts another account.

| Source | Weak | Strong |
|---|---|---|
| Registry | No `version`, or `>=` | Exact version, upgraded on purpose through a reviewed change |
| Git | No `ref`, or a branch name | Full commit SHA. A tag can be moved to different code; a commit hash cannot. |
| Any third party | Used directly from the internet | Reviewed, then mirrored into a private registry or your own repository |

Read the plan after every module upgrade: new resource types, IAM changes, and new providers are the things to look for. HashiCorp's general advice is that reusable modules set only a minimum provider version (`>= 6.0`) and root modules set the upper bound, so a shared module does not block its callers from upgrading. More on pipeline controls: [securing Terraform on AWS](09-securing-terraform-on-aws.md). If a module or pipeline is suspected of tampering: [pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md).

## Worked examples

**1. Every team must get S3 buckets with a customer managed key, versioning, public access block, and a TLS-only policy.**
Write one `hardened-bucket` module. Make `kms_key_arn` a required variable with a validation rule, hard-code the public access block with no variable to disable it, and output the bucket name and ARN. Publish it to the private registry with semantic version tags. Teams call it with an exact `version`. Build it by hand in [lab 03](../../labs/03-variables-and-modules/README.md).

**2. A root module needs the ARN of a KMS key created inside a child module, and `module.keys.aws_kms_key.this.arn` fails.**
Resources inside a child are private. Add `output "key_arn" { value = aws_kms_key.this.arn }` to the child and reference `module.keys.key_arn`. If the key is created in a grandchild, each level must re-export it.

**3. A plan on the CI runner shows new IAM resources that nobody added.**
The module block had `version = "~> 5.0"`, and the runner installed a newer release than the author tested, since modules are not in the lock file. Pin an exact version, review the release that introduced the IAM resources, and treat unexplained resources as a possible compromise until shown otherwise ([pipeline compromise runbook](../../runbooks/terraform-pipeline-compromise.md), [unexpected drift runbook](../../runbooks/terraform-unexpected-drift.md)).
## Pitfalls and exam traps

- `version` works only with registry sources. For Git, use `?ref=`.
- The dependency lock file does not pin modules. Only providers.
- After adding a module or changing its `source` or `version`, run `terraform init`. Plan fails with "Module not installed" otherwise.
- A parent cannot read a child's resources, only its outputs. A child cannot read anything from the parent that is not passed in.
- A local path must begin with `./` or `../`. Without that prefix, `"modules/vpc"` is read as a remote address and `terraform init` fails.
- Aliased provider configurations are not inherited. Default ones are. Version requirements are never inherited: each module declares its own `required_providers`.
- A module with its own `provider` block cannot use `count`, `for_each`, or `depends_on`.
- `~> 6.0` allows 6.9. `~> 6.0.1` does not allow 6.1.
- A Git tag is not immutable. A commit SHA is.
- All modules share one state file. Splitting state means separate root modules, not separate child modules.
- Marking a child output `sensitive` does not keep it out of state.

## Self-check

1. Which module source types accept the `version` argument?
2. A root module declares `var.environment`. How does a child module get that value?
3. What is the address of an output named `bucket_arn` from the `"payments"` instance of a module that uses `for_each`?
4. Your configuration has `version = "~> 3.2"`. Which of 3.2.5, 3.9.0, and 4.0.0 can be installed?
5. Why does committing `.terraform.lock.hcl` not protect you from a changed module?
6. A child module needs to create resources in two Regions. What must the root module and the child module each contain?
7. Give the strongest way to pin a module sourced from Git, and say why a tag is weaker.

<details>
<summary>Answers</summary>

1. Registry sources only: the public Terraform Registry and private registries (HCP Terraform, Terraform Enterprise). Git sources select a revision with `?ref=`. Local paths have no version.
2. The root passes it as an argument in the `module` block (`environment = var.environment`), and the child declares its own `variable "environment"`. Nothing is inherited.
3. `module.MODULE_NAME["payments"].bucket_arn`.
4. 3.2.5 and 3.9.0. Not 4.0.0, because only the right-most stated component (the minor version) may increase.
5. The lock file records provider versions and checksums, not modules. Module versions are fixed only by the `version` constraint or the Git `ref` in the configuration.
6. Root: two `aws` provider configurations (one aliased) and a `providers` map in the `module` block. Child: `required_providers` with `configuration_aliases` naming the configurations it expects, and no `provider` blocks.
7. `?ref=` set to a full commit SHA. A tag or branch can be re-pointed at different code by anyone with write access to the repository; a commit hash identifies exact content.

</details>

## Further reading

- [Modules overview](https://developer.hashicorp.com/terraform/language/modules)
- [Module sources](https://developer.hashicorp.com/terraform/language/modules/sources)
- [`module` block reference](https://developer.hashicorp.com/terraform/language/block/module)
- [Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)
- [Standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
- [Version constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)
- [Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)
