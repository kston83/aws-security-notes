# Terraform language (HCL) cheatsheet

> **Last reviewed:** 2026-11-11 · **Terraform Associate (004):** 2a, 4a–4h, 5a–5d · **SCS-C03:** 6.2.1 · **Teaching note:** [Configuration](../teaching/terraform/04-configuration.md), [Modules](../teaching/terraform/05-modules.md) · **Lab:** [03 Variables and modules](../labs/03-variables-and-modules/README.md), [07 Tests and guardrails](../labs/07-tests-and-guardrails/README.md) · Checked against Terraform 1.17 docs; the exam tests 1.12.

## Block types

| Block | Labels | Purpose |
|---|---|---|
| `terraform` | none | Settings: required versions, providers, backend or `cloud` |
| `provider` | name | Configure one provider. `alias` for extra configurations. |
| `resource` | type, name | An object Terraform creates, updates, and destroys |
| `data` | type, name | Read an existing object. Never changes it. |
| `ephemeral` | type, name | Fetch or generate a value for this run only. Never stored in state or plan. |
| `variable` | name | Module input |
| `output` | name | Module return value. Root outputs are stored in state. |
| `locals` | none | Named expressions, referenced as `local.NAME` |
| `module` | name | Call another module |
| `moved` | none | Record an address change so state follows it |
| `import` | none | Adopt an existing object into state on the next apply |
| `removed` | none | Drop an object from state, with or without destroying it |
| `check` | name | Assertion evaluated every plan and apply; failure is a warning |

Test files (`*.tftest.hcl`) add `run`, `variables`, `mock_provider`, `override_resource`, `override_data`, and `override_module`.

## References

| Expression | Refers to |
|---|---|
| `aws_s3_bucket.logs.arn` | Managed resource attribute |
| `data.aws_caller_identity.current.account_id` | Data source attribute |
| `ephemeral.aws_secretsmanager_secret_version.db.secret_string` | Ephemeral resource attribute |
| `var.NAME`, `local.NAME`, `module.NAME.OUTPUT` | Input, local, child module output |
| `count.index`, `each.key`, `each.value` | Current instance inside a `count` or `for_each` block |
| `self.ATTR` | The enclosing resource; only in provisioners, connections, and postconditions |
| `path.module`, `path.root`, `path.cwd` | Directory of this module, the root module, the working directory |
| `terraform.workspace` | Current CLI workspace name |

## Types

| Type | Constructor | Literal |
|---|---|---|
| Primitive | `string`, `number`, `bool` | `"a"`, `5`, `true` |
| List: ordered, one element type | `list(string)` | `["a", "b"]` |
| Set: unordered, unique, no index | `set(string)` | `toset(["a", "b"])` |
| Map: string keys, one value type | `map(number)` | `{ a = 1, b = 2 }` |
| Object: named attributes, each its own type | `object({ name = string, port = optional(number, 443) })` | `{ name = "web" }` |
| Tuple: fixed length, per-position types | `tuple([string, number])` | `["a", 1]` |
| Any | `any` | Placeholder; Terraform infers one concrete type |

`null` means "absent": the argument takes its default. List, set, and map are **collection** types; object and tuple are **structural** types.

## Variables and outputs

```hcl
variable "environment" {
  type        = string
  description = "Deployment stage."
  default     = "dev"
  nullable    = false            # a caller passing null gets the default instead
  sensitive   = false            # true redacts it in CLI output; it is still written to state
  ephemeral   = false            # true keeps it out of state and plan files entirely

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

output "bucket_arn" {
  value       = aws_s3_bucket.logs.arn
  description = "ARN of the log bucket."
  sensitive   = false            # must be true if the value derives from anything sensitive
}
```

**Variable definition precedence, highest first.** A higher source overrides a lower one:

1. `-var` and `-var-file` on the command line, in the order given (and variables set in HCP Terraform)
2. `*.auto.tfvars` and `*.auto.tfvars.json`, in lexical order of file name
3. `terraform.tfvars.json`
4. `terraform.tfvars`
5. `TF_VAR_name` environment variables
6. The `default` in the `variable` block

No value from any source and no default: Terraform prompts, or fails with `-input=false`. A child module sees only the variables passed in its `module` block; nothing is inherited.

## Meta-arguments

| Meta-argument | On | Effect |
|---|---|---|
| `count = N` | resource, data, module, ephemeral | N instances, addressed `NAME[0]`. Removing a middle item renumbers the rest. |
| `for_each = MAP_OR_SET` | resource, data, module, ephemeral | One instance per key, addressed `NAME["key"]`. Keys must be known at plan time and not sensitive. |
| `depends_on = [REF]` | resource, data, module, ephemeral, output, check | Explicit ordering when no attribute reference expresses it |
| `provider = aws.ALIAS` | resource, data, ephemeral | Use a non-default provider configuration |
| `providers = { aws = aws.ALIAS }` | module | Pass provider configurations to a child module |
| `lifecycle { }` | resource (some arguments on data and ephemeral) | See below |

`count` and `for_each` cannot be combined on one block.

| `lifecycle` argument | Effect |
|---|---|
| `create_before_destroy = true` | On replacement, create the new object first. Plan shows `+/-`. |
| `prevent_destroy = true` | Any plan that would destroy this resource fails. Deleting the whole block removes the guard with it. |
| `ignore_changes = [tags, ATTR]` | Do not plan updates for these arguments after creation. `all` ignores everything. |
| `replace_triggered_by = [REF]` | Replace this resource when the referenced resource or attribute changes |
| `precondition { }`, `postcondition { }` | Custom conditions; see below |

## Expressions

```hcl
locals {
  # Conditional
  instance_type = var.environment == "prod" ? "m7g.large" : "t4g.small"

  # for: list result, map result, filter, grouping
  upper_names = [for n in var.names : upper(n)]
  arn_by_name = { for b in aws_s3_bucket.this : b.bucket => b.arn }
  admins      = [for u in var.users : u.name if u.admin]
  by_team     = { for u in var.users : u.team => u.name... }

  # Splat: shorthand for [for s in aws_subnet.private : s.id]; lists and count only, not for_each maps
  subnet_ids = aws_subnet.private[*].id
  bucket_ids = values(aws_s3_bucket.this)[*].id

  # String template and heredoc
  name   = "${var.project}-${var.environment}"
  script = <<-EOT
    #!/bin/bash
    echo "${var.environment}"
  EOT
}

resource "aws_security_group" "web" {
  name   = "web"
  vpc_id = var.vpc_id

  dynamic "ingress" {                  # one nested block per element
    for_each = var.ingress_rules
    iterator = rule                    # optional; the default iterator name is the block label
    content {
      from_port   = rule.value.port
      to_port     = rule.value.port
      protocol    = "tcp"
      cidr_blocks = rule.value.cidrs
    }
  }
}
```

`dynamic` generates nested blocks only. It cannot generate `resource` or `lifecycle` blocks.

## Built-in functions

There are no user-defined functions in the language. Try any of these in `terraform console`.

| Category | Function and example | Result |
|---|---|---|
| String | `format("%s-%03d", "web", 7)` | `"web-007"` |
| String | `join("-", ["a", "b"])`, `split(",", "a,b")` | `"a-b"`, `["a", "b"]` |
| String | `lower("AbC")`, `upper("abc")`, `trimspace(" a ")` | `"abc"`, `"ABC"`, `"a"` |
| String | `replace("a.b", ".", "-")`, `substr("terraform", 0, 5)` | `"a-b"`, `"terra"` |
| String | `startswith("prod-app", "prod")`, `regex("[a-z]+", "ab12")` | `true`, `"ab"` |
| Numeric | `min(3, 1)`, `max(3, 1)`, `ceil(1.2)`, `floor(1.8)`, `abs(-4)` | `1`, `3`, `2`, `1`, `4` |
| Collection | `length(["a", "b"])`, `element(["a", "b"], 3)` | `2`, `"b"` (index wraps) |
| Collection | `contains(["a", "b"], "a")`, `index(["a", "b"], "b")` | `true`, `1` |
| Collection | `concat(["a"], ["b"])`, `flatten([["a"], ["b", "c"]])` | `["a", "b"]`, `["a", "b", "c"]` |
| Collection | `distinct(["a", "a"])`, `sort(["b", "a"])`, `compact(["a", "", null])` | `["a"]`, `["a", "b"]`, `["a"]` |
| Collection | `merge({ a = 1 }, { b = 2 })` | `{ a = 1, b = 2 }`; later arguments win |
| Collection | `lookup({ a = 1 }, "b", 0)`, `keys({ a = 1 })`, `values({ a = 1 })` | `0`, `["a"]`, `[1]` |
| Collection | `zipmap(["a", "b"], [1, 2])`, `slice(["a", "b", "c"], 0, 2)` | `{ a = 1, b = 2 }`, `["a", "b"]` |
| Collection | `one([])`, `coalesce(null, "x")`, `setunion(["a"], ["b"])` | `null`, `"x"`, set of `a` and `b` |
| Type | `toset(["a", "a"])`, `tolist(...)`, `tomap(...)`, `tostring(5)`, `tonumber("5")` | Conversions |
| Type | `try(var.obj.missing, "fallback")`, `can(regex("^ami-", var.ami))` | First expression without an error; `true` or `false` |
| Type | `sensitive(x)`, `nonsensitive(x)`, `ephemeralasnull(x)` | Add or remove the mark; replace an ephemeral value with `null` |
| Encoding | `jsonencode({ a = 1 })`, `jsondecode("{\"a\":1}")`, `yamldecode(...)`, `base64encode("x")` | Use `jsonencode` for IAM policies, never hand-built strings |
| Filesystem | `file("${path.module}/policy.json")`, `templatefile("${path.module}/user-data.tftpl", { env = var.environment })`, `fileset(path.module, "policies/*.json")` | Read at plan time |
| Date and time | `timestamp()`, `formatdate("YYYY-MM-DD", timestamp())`, `timeadd(timestamp(), "24h")`, `plantimestamp()` | `timestamp()` changes on every apply; `plantimestamp()` is fixed for the plan |
| Hash and crypto | `sha256("x")`, `filebase64sha256("lambda.zip")`, `md5("x")`, `uuid()` | Hex digests; `uuid()` changes on every run |
| IP network | `cidrsubnet("10.0.0.0/16", 8, 2)`, `cidrhost("10.0.2.0/24", 5)`, `cidrsubnets("10.0.0.0/16", 4, 4)` | `"10.0.2.0/24"`, `"10.0.2.5"`, two /20 ranges |

## Version constraints

| Operator | Meaning | Example |
|---|---|---|
| `=` or none | Exactly this version | `= 6.4.0` |
| `!=` | Exclude a version | `!= 6.3.0` |
| `>`, `>=`, `<`, `<=` | Comparison | `>= 1.12, < 2.0` |
| `~>` | Pessimistic: only the **rightmost** given part may increase | `~> 6.0` allows 6.x; `~> 6.4.0` allows 6.4.x only |

Combine with commas (logical AND). Root modules: pin tightly and commit the lock file. Reusable modules: set a minimum (`>= 6.0`) and let the root decide.

## Custom conditions

| | `validation` | `precondition` | `postcondition` | `check` with `assert` |
|---|---|---|---|---|
| Where | `variable` block | `lifecycle` of resource, data, ephemeral; also `output` | `lifecycle` of resource, data, ephemeral | Top-level `check "NAME"` block |
| Evaluated | Before planning the module | Before the object is planned or applied | After the object is planned or applied | End of every plan and apply |
| Can reference | The variable; other objects too since 1.9 **(verify)** | Anything except `self` | `self` and anything else | Anything, plus one scoped `data` block |
| On failure | **Error**: run stops | **Error**: run stops | **Error**: dependents are not processed | **Warning** only: run continues |
| Use for | Reject bad input early | Assumptions about inputs and dependencies | Guarantees about the result | Ongoing health and posture assertions |

```hcl
resource "aws_instance" "app" {
  ami           = data.aws_ami.app.id
  instance_type = local.instance_type

  lifecycle {
    precondition {
      condition     = data.aws_ami.app.architecture == "arm64"
      error_message = "The AMI must be arm64."
    }
    postcondition {
      condition     = self.metadata_options[0].http_tokens == "required"
      error_message = "IMDSv2 must be required."
    }
  }
}

check "bucket_encrypted" {
  assert {
    condition     = length(aws_s3_bucket_server_side_encryption_configuration.logs.rule) > 0
    error_message = "The log bucket has no default encryption rule."
  }
}
```

## Refactoring blocks

```hcl
moved {                                   # rename or move without destroy and re-create
  from = aws_s3_bucket.log
  to   = module.logging.aws_s3_bucket.this
}

import {                                  # adopt an existing object; a matching resource block must exist or be generated
  to = aws_iam_role.app
  id = "app-role"
}

import {                                  # many at once
  for_each = toset(["audit", "access"])
  to       = aws_s3_bucket.logs[each.key]
  id       = "example-${each.key}-logs"
}

removed {                                 # delete the resource block and add this
  from = aws_s3_bucket.legacy
  lifecycle {
    destroy = false                       # false: forget only. true: destroy the real object.
  }
}
```

`import` also accepts `identity = { ... }` in place of `id` for resource types that publish a resource identity (1.12 and later **(verify)**). All three blocks can be deleted once every state they apply to has been applied; shared modules keep `moved` blocks longer.

## Sensitive, ephemeral, write-only

| Mechanism | Hidden in CLI output | Kept out of state and plan | Notes |
|---|---|---|---|
| `sensitive = true` on variable or output | Yes | **No** | Redaction only. Anything that derives from it is also marked. |
| `ephemeral = true` on variable or child-module output | Yes | Yes | Usable only in ephemeral contexts. Root module outputs cannot be ephemeral. |
| `ephemeral "TYPE" "NAME"` block | Yes | Yes | Opened on every plan and apply. Introduced in 1.10 **(verify)**. |
| Write-only argument (`NAME_wo`) | Yes | Yes | Sent to the provider, never read back. Change the paired `NAME_wo_version` to send a new value. Introduced in 1.11 **(verify)**. |

Ephemeral values may be used in: write-only arguments, other `ephemeral` blocks, `locals`, ephemeral variables and outputs, `provider` blocks, and provisioner and `connection` blocks. Worked AWS example: [AWS provider security cheatsheet](terraform-aws-provider-security.md).

## terraform block

```hcl
terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"          # HOSTNAME/NAMESPACE/TYPE; hostname defaults to registry.terraform.io
      version = "~> 6.0"
    }
  }

  backend "s3" {                         # one backend, or one cloud block, never both; root module only
    bucket = "STATE_BUCKET"
    key    = "PROJECT/terraform.tfstate"
    region = "eu-west-1"
  }
}
```

The `terraform` block takes literal values only: no variables, locals, or functions. Backend detail: [state and backends cheatsheet](terraform-state-and-backends.md).

## Module sources

| Source | `source =` | Version pin |
|---|---|---|
| Local path | `"./modules/network"` (must start `./` or `../`) | None; follows the repo |
| Public registry | `"terraform-aws-modules/vpc/aws"` (NAMESPACE/NAME/PROVIDER) | `version = "~> 6.0"` |
| Private registry | `"app.terraform.io/ORG_NAME/vpc/aws"` | `version` |
| GitHub | `"github.com/ORG_NAME/REPO_NAME//modules/vpc?ref=v1.2.0"` | `?ref=` tag or commit SHA |
| Generic Git | `"git::https://example.com/network.git?ref=COMMIT_SHA"` or `"git::ssh://git@example.com/network.git"` | `?ref=` |
| HTTP archive | `"https://example.com/network.zip"` | In the URL |
| S3 or GCS | `"s3::https://BUCKET.s3.eu-west-1.amazonaws.com/network.zip"`, `"gcs::https://www.googleapis.com/storage/v1/BUCKET/network.zip"` | In the object key |

The `version` argument works **only** with registry sources. `//` separates the repository from a subdirectory. Pin Git sources to a commit SHA when supply-chain integrity matters, since tags can be moved. After changing `source` or `version`, run `terraform init`.
