# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Markdown working notes covering two domains, AWS security (SCS-C03) and Terraform (Terraform Associate 004): exam blueprint maps, teaching notes, cheatsheets, incident runbooks, NIST SP 800-53 Rev. 5 control mappings, and hands-on Terraform labs under `labs/` that run against the floci local AWS emulator. There is no application code, so there is no build step. The tooling is two Bash scripts, plus Terraform for the labs. `README.md` explains what each folder is for, and `CONTRIBUTING.md` holds the writing conventions. Read both before adding content.

## Commands

Run these from Git Bash or the Bash tool, not PowerShell:

```bash
bash scripts/check-links.sh           # checks every relative link and #anchor; exits 1 if any are broken. Run before every commit.
bash scripts/build-control-matrix.sh  # regenerates control-mappings/control-impact-matrix.csv (needs gawk)
```

If you edit any table under `control-mappings/services/`, run the matrix script and commit the regenerated CSV together with the table change. Never edit the CSV by hand.

Labs are tested by running them. With floci listening on `http://localhost:4566` (`docker compose up -d` in `labs/`; see `labs/README.md`), run a lab from its folder:

```bash
terraform init && terraform apply    # then the lab's Verify commands, each Break it exercise, and terraform destroy
terraform test                        # labs that ship .tftest.hcl files (07)
```

If you change a lab's `.tf` files or README, re-run that lab top to bottom and paste real output into the README. Never invent expected output.

## How the pieces connect

The content is heavily cross-linked, so a change in one file usually means updates in others:

- **`exam/scs-c03-blueprint.md`** maps every SCS-C03 skill ID (such as `4.2.3`) to the notes that cover it, often down to a heading anchor. If you add, move, or rename coverage, update the blueprint. If you rename a heading, find every link to its anchor and fix it.
- **`exam/terraform-associate-blueprint.md`** does the same for Terraform Associate (004) objective IDs (such as `6b`). Each Terraform teaching note under `teaching/terraform/` has one `## Objective 6b: Short title` heading per objective, and the blueprint links to those anchors. Note `09-securing-terraform-on-aws.md` is not an exam domain; it bridges to the AWS security notes.
- **Header block.** Every note's second line is a `> **Last reviewed:** YYYY-MM-DD · **SCS-C03:** … · …` block that lists the skill IDs the note covers and links related notes. Terraform notes use `**Terraform Associate (004):**` with objective IDs, and add `**SCS-C03:**` only where the note covers that skill. Runbooks add **Severity** and **NIST 800-53** fields (see `runbooks/_template.md`). Change `Last reviewed` only when you actually re-verify the content, not for typo fixes.
- **Indexes to keep in sync** when you add a file: the Contents section of `README.md`, the index table in `runbooks/README.md`, the files table in `control-mappings/README.md`, and the index table in `labs/README.md`.
- **Control mappings have two views.** `services/*.md` is the forward view (configuration → controls), and it is the source of the CSV. `by-family.md` is the reverse view (control → configurations), and it is maintained by hand. A new mapping row in a service file usually needs a matching entry in `by-family.md`.

## Script parsing constraints

**`build-control-matrix.sh`** parses `control-mappings/services/*.md` line by line:
- Each `## ` heading becomes the `section` value. The filename becomes `service_group`.
- Any line starting with `| ` that has 6 or more cells is read as a mapping row. Other 6-column tables in these files would be ingested by mistake. Only header rows whose first cell is `Configuration` are skipped.
- Column order is fixed: Configuration | Controls | Type | If absent or misconfigured | Evidence | Automated check.
- Controls are comma-separated, and each one becomes its own CSV row. Type uses the abbreviations `I`, `S`, and `E`, comma-separated.
- A literal `|` inside a cell, even inside backticks, breaks the row.

**`check-links.sh`** only reads links of the form `](target)` where the target has no spaces, and ignores anything inside fenced code blocks or inline code spans. It builds anchor slugs GitHub-style by lowercasing, dropping characters other than `a-z0-9 _-`, and turning spaces into `-`. For example, `### Task 1.1: Monitoring and alerting` becomes `#task-11-monitoring-and-alerting`. It doesn't handle the `-1` suffixes GitHub adds to duplicate headings, so avoid linking to duplicate headings.

## Content rules worth remembering

These come from CONTRIBUTING.md:
- One file, one job. Teaching notes explain, cheatsheets list, runbooks instruct, and mappings map. Move long reference tables out of teaching notes and into cheatsheets.
- Teaching notes use a fixed section order, with self-check answers inside a collapsed `<details>` block (see CONTRIBUTING.md).
- Mark volatile facts (limits, defaults, supported-service lists, Config rule names, Security Hub control IDs) with **(verify)**.
- Commands must be copy-pasteable, with `UPPER_SNAKE` placeholders. Label commands that change state (cheatsheets use **[changes state]**).
- Write NIST control IDs with enhancements in parentheses, like `AC-6(9)`. Use `111122223333` and `444455556666` as example account IDs. Never commit real account IDs, ARNs, hostnames, or incident details.
- Commit subjects are prefixed with a scope, like `runbooks: add EKS pod compromise procedure` or `cheatsheets/kms: correct rotation period range`.
- `.gitattributes` forces LF line endings for `.md`, `.sh`, and `.csv` files.
- Labs follow `labs/_template/`: a `README.md` with fixed sections (Goal, Before you start, Steps, Verify, Break it, Clean up, What differs on real AWS) next to a complete configuration. Keep the lab provider block (fake `test` credentials, `skip_*` flags, one `endpoints` entry per service used) as it is in the template, prefix resource names with the lab number (`lab03-`), and record every place the emulator is more forgiving than AWS. floci does not enforce IAM by default.
- Terraform facts tied to a version (when a feature appeared, what is deprecated) get **(verify)**. The 004 exam tests Terraform 1.12; the labs were last run on the versions listed under "Tested with" in `labs/README.md`.
- `.gitignore` excludes `.terraform/`, `.terraform.lock.hcl`, `*.tfstate*`, and saved plans. Never commit state, plans, or `TF_LOG` output.
