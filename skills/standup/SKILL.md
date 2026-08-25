---
name: standup
description: Generate an async standup update (Did / Next / Blockers) from recent Git and GitHub activity, and optionally issue-tracker tickets. Use when the user asks for a "standup", "daily update", "async update", "what did I do", "update for the meeting", or wants to summarize their recent work for a team thread.
argument-hint: "[--since <when>] [--author <user>]"
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

You are generating a concise, paste-ready async standup update. Your task is to gather the user's recent work from Git, GitHub (via the `gh` CLI), and — if configured — the issue tracker, then organize it into **Did / Next / Blockers**. Follow each step in order.

## Step 1: Parse Arguments

Extract options from `$ARGUMENTS`:

- `--since <when>` → time window for "Did" (e.g. `yesterday`, `2 days ago`, `2024-01-15`, `last friday`). Default: `1 day ago` (use `3 days ago` if today is Monday).
- `--author <user>` → GitHub username / git author to filter by. Default: the current user.

**Defaults:**

```bash
SINCE="1 day ago"           # widen to "3 days ago" on Mondays
AUTHOR="$(gh api user --jq .login 2>/dev/null || git config user.name)"
```

## Step 2: Load Configuration

Check for `.claude/config.yaml` to resolve the repository and issue tracker:

- `issueTracker.type` → `auto` | `linear` | `jira` | `github` | `none`
- `issueTracker.github.repository` or the current repo (via `gh repo view`)
- `pullRequests.*` for context

If no config exists, use auto-detection and sensible defaults. The standup must work with zero configuration.

## Step 3: Gather Git Activity (local)

Collect the user's recent commits across the current repository:

```bash
git log --since="$SINCE" --author="$AUTHOR" --pretty=format:'%h %s' --no-merges
```

Group commits by their type/ticket prefix when the repo uses a commit convention (e.g. `[Feature]`, `fix:`, `PROJ-123`). Summarize — do not paste raw commit lists.

## Step 4: Gather GitHub Activity

Use the `gh` CLI (requires authentication). Handle each call defensively — if `gh` is unavailable or a call fails, skip that section and note it, never abort the whole standup.

**Recently merged PRs (part of "Did"):**

```bash
gh search prs --author "$AUTHOR" --merged --sort updated \
  --json number,title,repository,url,closedAt --limit 20
```

**Open PRs by the user (part of "Next", and "Blockers" if review is stalled):**

```bash
gh search prs --author "$AUTHOR" --state open --sort updated \
  --json number,title,repository,url,reviewDecision,isDraft,statusCheckRollup --limit 20
```

**PRs awaiting the user's review (part of "Next"):**

```bash
gh search prs --review-requested "$AUTHOR" --state open \
  --json number,title,repository,url --limit 20
```

Filter to the window where a timestamp is available. Interpret signals:

- `reviewDecision: CHANGES_REQUESTED` or failing `statusCheckRollup` → candidate **Blocker**.
- `reviewDecision: REVIEW_REQUIRED` on an open PR → **Next** (waiting on review).
- `isDraft: true` → **Next** (in progress), not "Did".

## Step 5: Gather Issue Tracker Tickets (optional)

If `issueTracker.type` is not `none` and the relevant MCP server is available, fetch tickets assigned to the user that changed in the window.

### Linear

```
# Use the Linear MCP server if available
mcp__linear__list_issues(assignee: me, updatedAfter: <window>)
```

### Jira

```
# Use the Jira MCP server if available
mcp__jira__search_issues(jql: "assignee = currentUser() AND updated >= -1d")
```

### GitHub Issues

```bash
gh search issues --assignee "$AUTHOR" --state all --sort updated \
  --json number,title,repository,url,state --limit 20
```

Map ticket status to sections: recently completed → **Did**; in-progress / todo picked up next → **Next**; blocked/needs-info → **Blockers**. If no tracker is configured or reachable, skip this step silently.

## Step 6: Compose the Standup

Organize everything into three sections. Keep each bullet short and outcome-focused (what shipped / what's happening), not a commit dump. Link PRs/issues as `#<number>` or full URLs when cross-repo. If a section is empty, write a brief honest line rather than padding.

Output in this paste-ready format:

```markdown
*Standup — {date}*

*Did*
- {shipped work, merged PRs, completed tickets}

*Next*
- {open PRs awaiting review, in-progress tickets, planned work}

*Blockers*
- {failing CI, changes requested, waiting-on items — or "None"}
```

## Step 7: Present

Print the standup as a single copy-pasteable block. After it, add a one-line note listing any sources that were unavailable (e.g. "Note: issue tracker not configured; based on Git + GitHub only.") so the user knows the coverage.

## Configuration Reference

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `issueTracker.type` | `auto` | `linear`, `jira`, `github`, or `none` |
| `issueTracker.github.repository` | current repo | `owner/repo` for GitHub queries |

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `gh` not installed or not authenticated | Skip GitHub sections, note it, continue with Git |
| Not inside a git repository | Skip Git section, rely on GitHub search |
| Issue tracker MCP unavailable | Skip tracker section silently |
| No activity in the window | Say so plainly and suggest widening `--since` |
