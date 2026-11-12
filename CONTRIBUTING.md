# Contributing

## Conventions

**One file, one job.** Teaching notes explain. Cheatsheets list. Runbooks instruct. Control mappings map. Labs make you do it. If a teaching note grows a long reference table, move the table to a cheatsheet and link to it.

**File names** are lowercase, hyphen-separated, and describe the content (`compromised-iam-credentials.md`, not `runbook3.md`).

**Header block.** Every note starts with:

```markdown
# Title

> **Last reviewed:** YYYY-MM-DD · **SCS-C03:** skill IDs covered · **Related:** links
```

Terraform notes name their exam the same way, and list SCS-C03 skills as well only where the note covers them:

```markdown
> **Last reviewed:** YYYY-MM-DD · **Terraform Associate (004):** objective IDs covered · **SCS-C03:** skill IDs covered · **Related:** links
```

**Exam references** use the official skill numbering from the SCS-C03 exam guide (for example `4.2.3`). The full list is in [exam/scs-c03-blueprint.md](exam/scs-c03-blueprint.md).

**Terraform references** use the objective IDs from the Terraform Associate (004) exam content list (for example `6b`). The full list is in [exam/terraform-associate-blueprint.md](exam/terraform-associate-blueprint.md). In a Terraform teaching note, each objective gets its own `## Objective 6b: Short title` heading so the blueprint can link to it.

**Control references** use NIST SP 800-53 Rev. 5 identifiers with enhancements in parentheses: `AC-6(9)`, `SC-28(1)`.

**Volatile facts** (limits, defaults, supported-service lists, pricing tiers, the Terraform or provider version that introduced a feature) get **(verify)** after them and, where possible, a link to the AWS or HashiCorp page that holds the current value.

**Commands** must be copy-pasteable. Use `UPPER_SNAKE` placeholders for values the reader supplies. Mark any command that changes or deletes state with a comment saying so.

**Links** between notes are relative so they work in any clone and on any Git host.

## Templates

- Runbook: [runbooks/_template.md](runbooks/_template.md)
- Control mapping row format: described in [control-mappings/README.md](control-mappings/README.md#row-format)
- Lab: [labs/_template/](labs/_template/README.md)

Teaching notes follow this section order:

1. Why this matters
2. Mental model
3. Core concepts (one subsection per exam task)
4. Worked examples
5. Pitfalls and exam traps
6. Self-check questions, with answers in a collapsed `<details>` block
7. Further reading

## Labs

Each lab is a folder under `labs/` holding a `README.md` and a complete, working Terraform configuration that targets the floci emulator. See [labs/README.md](labs/README.md#how-a-lab-is-laid-out) for the layout and section order.

- **Run it before you commit it.** Every command and every expected output in a lab README comes from a real run against the emulator, top to bottom, including the "Break it" exercises and the clean-up.
- **Say where the emulator lies.** If floci accepts something AWS would reject, or skips enforcement AWS would apply, record it under "What differs on real AWS".
- **Keep the lab provider block intact.** Start `providers.tf` from the template and add one `endpoints` entry per service the lab uses. The fake credentials are deliberate: a call that escapes the emulator fails.
- **Prefix resource names** with the lab number (`lab03-`) so labs can share one emulator.
- **Do not commit** `.terraform/`, `.terraform.lock.hcl`, state files, or saved plans from a lab folder. `.gitignore` excludes them.
- Update the index table in `labs/README.md` and the Labs list in `README.md` when you add a lab, and re-run all labs before changing the "Tested with" line.

## Review cadence

| Trigger | Action |
|---|---|
| AWS re:Invent and re:Inforce | Review all teaching notes and the services-at-a-glance cheatsheet for new or renamed services |
| New exam guide version | Update `exam/` first, then re-tag skill IDs in the notes |
| New Terraform minor release or AWS provider major release | Re-run every lab; re-verify version-marked facts in the Terraform notes and cheatsheets |
| New floci release | Re-run every lab and update "Tested with" in `labs/README.md` |
| After any real incident | Update the runbook you used with what was missing or wrong |
| Every six months | Re-verify everything marked **(verify)** |

Update the `Last reviewed` date only when you have checked the content, not when you fix a typo.

## Commits

Small, single-topic commits with imperative subjects:

```
runbooks: add EKS pod compromise procedure
cheatsheets/kms: correct rotation period range
labs/02-remote-state: show the lock file during apply
```

Run `scripts/check-links.sh` before committing. If you changed a table under `control-mappings/services/`, run `scripts/build-control-matrix.sh` and commit the regenerated CSV with it.

## What not to commit

Account IDs, ARNs from real environments, access keys, internal hostnames, customer names, or incident details that identify a real event. Use `111122223333` and `444455556666` as example account IDs. The emulator account ID `000000000000` and the credentials `test` / `test` are fine in labs.

Terraform state files, saved plans, `.tfvars` files holding secrets, and debug logs (`TF_LOG` output). All of them can contain credentials.
