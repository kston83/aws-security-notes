# Contributing

## Conventions

**One file, one job.** Teaching notes explain. Cheatsheets list. Runbooks instruct. Control mappings map. If a teaching note grows a long reference table, move the table to a cheatsheet and link to it.

**File names** are lowercase, hyphen-separated, and describe the content (`compromised-iam-credentials.md`, not `runbook3.md`).

**Header block.** Every note starts with:

```markdown
# Title

> **Last reviewed:** YYYY-MM-DD · **SCS-C03:** skill IDs covered · **Related:** links
```

**Exam references** use the official skill numbering from the SCS-C03 exam guide (for example `4.2.3`). The full list is in [exam/scs-c03-blueprint.md](exam/scs-c03-blueprint.md).

**Control references** use NIST SP 800-53 Rev. 5 identifiers with enhancements in parentheses: `AC-6(9)`, `SC-28(1)`.

**Volatile facts** (limits, defaults, supported-service lists, pricing tiers) get **(verify)** after them and, where possible, a link to the AWS page that holds the current value.

**Commands** must be copy-pasteable. Use `UPPER_SNAKE` placeholders for values the reader supplies. Mark any command that changes or deletes state with a comment saying so.

**Links** between notes are relative so they work in any clone and on any Git host.

## Templates

- Runbook: [runbooks/_template.md](runbooks/_template.md)
- Control mapping row format: described in [control-mappings/README.md](control-mappings/README.md#row-format)

Teaching notes follow this section order:

1. Why this matters
2. Mental model
3. Core concepts (one subsection per exam task)
4. Worked examples
5. Pitfalls and exam traps
6. Self-check questions, with answers in a collapsed `<details>` block
7. Further reading

## Review cadence

| Trigger | Action |
|---|---|
| AWS re:Invent and re:Inforce | Review all teaching notes and the services-at-a-glance cheatsheet for new or renamed services |
| New exam guide version | Update `exam/` first, then re-tag skill IDs in the notes |
| After any real incident | Update the runbook you used with what was missing or wrong |
| Every six months | Re-verify everything marked **(verify)** |

Update the `Last reviewed` date only when you have checked the content, not when you fix a typo.

## Commits

Small, single-topic commits with imperative subjects:

```
runbooks: add EKS pod compromise procedure
cheatsheets/kms: correct rotation period range
```

Run `scripts/check-links.sh` before committing. If you changed a table under `control-mappings/services/`, run `scripts/build-control-matrix.sh` and commit the regenerated CSV with it.

## What not to commit

Account IDs, ARNs from real environments, access keys, internal hostnames, customer names, or incident details that identify a real event. Use `111122223333` and `444455556666` as example account IDs.
