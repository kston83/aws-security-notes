---
name: run-lab
description: Run one Terraform lab under labs/ end to end against the floci emulator and make its README match reality (real output, fixed steps, emulator differences recorded). Use when finishing or re-testing a lab, or after changing a lab's .tf files or README. Also covers running several labs in sequence via subagents and the wrap-up (commit, labs/README.md table, issue checkbox).
---

# Run a lab end to end

CLAUDE.md requires that a lab whose `.tf` files or README change is re-run top to bottom with real output pasted in. This is that procedure. Run **one lab at a time**: floci plus Terraform is memory-heavy, and two emulators would also fight over port 4566.

## 1. Start the emulator

Check first that nothing is already listening: `curl -s http://localhost:4566/_floci/health`. If something answers, find out what before starting another.

- **Docker available:** `cd labs && docker compose up -d`, as `labs/README.md` describes.
- **No Docker (native floci build):** the binary never exits; even `--help` starts the server and hangs the calling shell. Always start it fully detached, with the same settings as `labs/docker-compose.yml`:

  ```bash
  FLOCI_DEFAULT_REGION=us-east-1 FLOCI_STORAGE_MODE=memory \
    setsid nohup FLOCI_BINARY > FLOCI_LOG 2>&1 < /dev/null &
  ```

  Then poll the health endpoint until it answers. Where the binary and toolchain live depends on the machine, so keep that in your own setup notes, not in the repo.

Lab shell: `AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_ENDPOINT_URL=http://localhost:4566`.

floci does not enforce IAM by default. `FLOCI_SERVICES_IAM_ENFORCEMENT_ENABLED=true` **(verify)** turns enforcement on; use it only when an exercise depends on enforcement, and say in the README that you did.

## 2. Run the lab from a copy

Copy `labs/NN-name/` to a scratch directory outside the repo and run Terraform there, never inside the repo: that keeps `.terraform/`, state, plans, and `TF_LOG` output out of the working tree. On WSL, use the Linux filesystem, not `/mnt/c`.

Do the lab exactly as a learner would: every Step, every Verify command, every **Break it** exercise (make the mistake, capture the real error or plan, revert), and Clean up. If the issue for the lab names specific things to test, test each one and capture the evidence.

## 3. Make the README match reality

- Replace output described in words or written by hand with real captured output. Trim to the lines that prove the point, mark cuts with `...`, and never alter, tidy, or invent output.
- Replace machine-specific text (home paths, usernames) with neutral text like `~/labs/NN-name`. floci's account ID `000000000000` is fine. Timestamps may keep their local offset; say it is local.
- If a step, command, or claim is wrong, fix the README, or the `.tf` files if the configuration is at fault. **After any `.tf` change, re-run the lab top to bottom** so every pasted output comes from the final configuration, then copy the changed files back into the repo.
- If a Break-it exercise only breaks on real AWS, say so in that exercise rather than implying it fails on floci.
- Record every place floci is more forgiving or behaves differently in **What differs on real AWS**. Mark untested real-AWS claims **(verify)**.
- Remove the `> **Test status:** ...` line once the lab is fully run.
- Keep the fixed section order (Goal, Before you start, Steps, Verify, Break it, Clean up, What differs on real AWS) and keep the README lean: a few lines of output per step. Do not grow a README past 370 lines while the length question in issue #4 is open.

## 4. Stop and check

- `terraform destroy` anything still applied, then stop the emulator (`docker compose down`, or `pkill -f FLOCI_BINARY` for the native build) and confirm it is gone.
- `bash scripts/check-links.sh` from the repo root (Git Bash): 0 broken.
- `git status`: only `labs/NN-name/` changed, with no state, lock file, plan, or `.terraform/` in it.

## Running several labs (orchestration)

Run each lab in its own background `general-purpose` subagent, **strictly one after another**. Start the next only once the previous has reported, and confirm the emulator is stopped between runs. Brief each subagent with this skill, the lab path, and the issue text for that lab, and tell it:
- not to edit anything outside its lab folder (and not `labs/README.md`)
- not to commit or comment on GitHub
- to report pass/fail per Step, Verify, and Break-it, files changed and why, new emulator differences, exact versions (`terraform version`, the lock file, `aws --version`, floci version from the health endpoint), and what is unresolved

Doc-only work that needs no emulator, such as fact-checking or trimming notes, can run in parallel, provided each agent owns a disjoint set of files.

## Wrap-up (main session)

1. Review the lab's diff: scan for usernames, home paths, and real 12-digit account IDs, and confirm no new output appeared that the run didn't produce.
2. Commit only that lab's folder: subject `labs/NN: run end to end on floci and paste real output`, a body listing the fixes and the floci differences found, `Refs #ISSUE`, and the attribution trailer.
3. Update the **Tested with** table in `labs/README.md` (versions, and which labs are run end to end versus smoke-tested), and commit it with scope `labs:`.
4. Tick the lab's checkbox in the issue body (`gh issue edit N --body-file ...`) and add a comment with the findings. Push and update the PR description only when the user asks.
