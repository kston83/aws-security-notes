# Lab NN: Title

> **Last reviewed:** YYYY-MM-DD · **Terraform Associate (004):** objective IDs · **SCS-C03:** skill IDs · **Time:** minutes · **Related:** links to the teaching note and cheatsheet this lab exercises

## Goal

Two or three sentences: what the reader builds and what they will be able to do afterward.

## Before you start

- floci is running and the AWS CLI points at it. See [labs/README.md](../README.md#start-the-emulator).
- Notes to read first, as links.

## Steps

Numbered steps. Every command copy-pasteable from inside this lab's folder. Show the part of the configuration each step is about, say what to look for in the output, and label commands that change state with `# [changes state]`.

## Verify

Commands that prove the result independently of Terraform (usually the AWS CLI), each with the output to expect.

## Break it

Three or more deliberate mistakes. For each: what to change, the command to run, the error or plan output to expect, why it happens, and how to put it back.

## Clean up

```bash
terraform destroy    # [changes state]
```

Plus anything `destroy` does not remove.

## What differs on real AWS

Where the emulator is more forgiving than AWS, what a real apply would need (permissions, time, cost), and what replaces the lab-only provider settings.
