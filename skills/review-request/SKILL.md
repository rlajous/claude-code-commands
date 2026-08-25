---
name: review-request
description: Draft a short, paste-ready message asking teammates to review a pull request. Pulls the PR title, link, size, and CI status via the gh CLI, and reviewers from project config. Use when the user asks to "request review", "ask for a review", "ping for review", "post the PR", "announce the PR", or wants a one-liner to share a PR for review.
argument-hint: "[pr-number-or-url]"
allowed-tools: Read, Grep, Glob, Bash(gh pr view:*)
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are drafting a concise, professional message that asks teammates to review a pull request. Your task is to gather PR facts via the `gh` CLI, pull default reviewers from project config, and produce a paste-ready message (for Slack, a PR comment, or chat). Follow each step in order. Requires GitHub CLI (`gh`) authenticated.

## Step 1: Resolve the Pull Request

Determine which PR to announce:

- If `$ARGUMENTS` contains a PR number or GitHub URL, use it.
- Otherwise, resolve the PR for the current branch:

```bash
gh pr view --json number,title,url,additions,deletions,changedFiles,isDraft,reviewDecision,statusCheckRollup,baseRefName,headRefName,body
```

If no PR exists for the current branch, stop and tell the user to create one first (e.g. with `/finish`).

## Step 2: Load Configuration

Check for `.git-workflow/config.yaml`:

- `pullRequests.reviewers` → default reviewers (GitHub usernames or `org/team` slugs). Use these as the people/teams to @-mention.
- `pullRequests.labels` → for context only.

If no reviewers are configured, do not invent any. Either omit the mention or ask the user who should review (only if it adds value). Never hardcode a specific person or team.

## Step 3: Gather PR Facts

From the `gh` data:

- **Title** and **URL**.
- **Size**: `+{additions} / -{deletions}` across `{changedFiles}` files. Classify roughly: `XS` (<10 lines), `S` (<50), `M` (<200), `L` (<500), `XL` (500+). This helps reviewers budget time.
- **CI status**: summarize `statusCheckRollup` as passing / failing / pending.
- **Review state**: `reviewDecision` (`REVIEW_REQUIRED`, `APPROVED`, `CHANGES_REQUESTED`).
- **Draft**: if `isDraft`, note it's a draft (or suggest marking ready first).
- **Base ← head** branches.

Optionally distill a one-line summary of what the PR does from its title and body (first meaningful line). Keep it factual — do not overstate.

## Step 4: Compose the Message

Write a short, direct message. Guidelines:

- Lead with the ask and the link.
- Include the one-line purpose and the size so reviewers know the scope.
- Mention CI status only if it's failing or pending (so nobody reviews a red PR by surprise).
- @-mention the configured reviewers/teams once, if any.
- Keep it to 2–4 lines. No filler, no emoji unless the project's own conventions use them.

Default template:

```text
Review please: {one-line purpose} — {url}
Size: {size} ({+adds}/{-dels}, {files} files){, CI: {status} if not passing}
{@reviewer1 @org/team if configured}
```

Adapt tone to the destination if the user specifies one (Slack vs. formal PR comment). Do not impose any particular personal writing style.

## Step 5: Present

Print the message as a single copy-pasteable block. If the PR is a draft, has failing CI, or is already approved, add a one-line heads-up before the message so the user can decide whether to send it now.

## Configuration Reference

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `pullRequests.reviewers` | `[]` | GitHub usernames / `org/team` slugs to @-mention |

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `gh` not installed or not authenticated | Stop with a short setup hint (`gh auth login`) |
| No PR for the current branch | Ask the user to create one first (e.g. `/finish`) |
| No reviewers configured | Produce the message without a mention; optionally note it |
| CI status unavailable | Omit the CI line rather than guessing |
