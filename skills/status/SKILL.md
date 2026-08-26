---
name: status
description: Show where you are in the git-workflow pipeline (branch, ticket, commits, PR, release, QA) and what the recommended next step is. Use when the user asks "where am I", "what's the status", "what's next", "status of this branch/PR/release", or wants a quick summary of the current workflow state.
argument-hint: "[--html]"
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git rev-parse:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh release list:*)
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are reporting the current position in the git-workflow pipeline and the recommended next step. This is **read-only** — never modify Git state, never create branches/commits/PRs. Follow each step in order.

## Step 1: Parse Arguments

- `--html` → also generate a self-contained HTML status report (see Step 6).

## Step 2: Load Context

Read the durable workflow context if present:

- `.git-workflow/pr-context.json` — ticket id/title, branch, type, timestamps written by `/start`, `/tdd`, `/commit`.
- `.git-workflow/config.yaml` — `workflow.developmentBranch`/`productionBranch`, issue tracker.

If a canonical file is absent, read its matching legacy `.claude/` fallback as defined in the compatibility reference. If neither form exists, fall back to live Git/GitHub state only.

## Step 3: Gather Live State (read-only)

```bash
git rev-parse --abbrev-ref HEAD                 # current branch
git status --porcelain                          # uncommitted changes?
git log --oneline origin/{devBranch}..HEAD      # commits ahead of the dev branch
```

If `gh` is available and authenticated, also gather (skip gracefully on failure):

```bash
gh pr view --json number,title,state,reviewDecision,statusCheckRollup,url   # PR for current branch, if any
gh release list --limit 1                                                     # latest release
```

## Step 4: Determine Pipeline Position

Infer which stage the work is in, in this order:

| Signal | Stage |
|--------|-------|
| On dev/prod branch, clean tree | **Idle** — no active feature |
| Feature branch, no commits ahead | **Started** — branch created, nothing committed |
| Feature branch, uncommitted changes | **In progress** — changes not yet committed |
| Commits ahead, no PR | **Committed** — ready to open a PR |
| PR open, checks pending/failing | **In review (CI/{state})** |
| PR open, `CHANGES_REQUESTED` | **In review — changes requested** |
| PR open, `APPROVED` | **Approved — ready to merge** |
| On a `release/*` branch | **Releasing** |

## Step 5: Print the Status Report

Output a compact, scannable summary and an explicit next step:

```text
Workflow status
  Branch:   fix/proj-123-login-timeout  (3 commits ahead of staging)
  Ticket:   PROJ-123 — Fix login timeout
  Changes:  clean working tree
  PR:       #42 (OPEN, CI passing, review required) — https://github.com/...
  Stage:    In review

  Next: wait for review, or run /review 42 to self-review before requesting.
```

Map the stage to the recommended next command:

- Idle → `/start` to begin a feature.
- Started / In progress → make changes, then `/commit`.
- Committed → `/finish` to open a PR.
- In review → `/review <pr>` to self-review; address feedback.
- Approved → merge, then `/release` when ready.
- Releasing → after merge, `/release-notes` then `/sync`.

## Step 6: HTML Report (only with `--html`)

If `--html` was passed, generate a self-contained HTML status page:

```bash
mkdir -p .git-workflow
node "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts/status-report.mjs" > .git-workflow/status.html
```

The script gathers the same `git`/`gh` state as JSON and injects it into `assets/status-template.html`. Tell the user the file path (`.git-workflow/status.html`) and that it is a single self-contained file they can open in a browser. If Node is unavailable, skip the HTML and print the text report only.

## Error Handling

| Scenario | Action |
| -------- | ------ |
| Not a git repository | Report that and stop |
| `gh` unavailable / not authenticated | Skip PR/release sections, note it, show git-only status |
| No `.pr-context.json` | Use live Git state; note context is not being tracked |
| Node unavailable (with `--html`) | Print the text report, skip HTML generation |
