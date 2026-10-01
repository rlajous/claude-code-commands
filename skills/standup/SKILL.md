---
name: standup
description: Generate an async standup update (Did / Next / Blockers) from recent Git and GitHub activity — including org-wide PR and release search, ticket comments, and release-timing verification — and optionally issue-tracker tickets. Use when the user asks for a "standup", "daily update", "async update", "what did I do", "update for the meeting", or wants to summarize their recent work for a team thread.
argument-hint: "[--since <when>] [--author <user>] [--org <org>]"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git config:*), Bash(gh api:*), Bash(gh repo view:*), Bash(gh search prs:*), Bash(gh search issues:*), Bash(gh pr view:*), Bash(gh release list:*), Bash(gh release view:*)
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are generating a concise, paste-ready async standup update. Your task is to gather the user's recent work from Git, GitHub (via the `gh` CLI, searched org-wide), and — if configured — the issue tracker (including comments), then verify what actually shipped versus merely merged, and organize everything into **Did / Next / Blockers**. Follow each step in order.

This skill must stay fully generic: never hardcode a real org, author, or tracker instance anywhere in this file. Always use placeholders (`<org>`, `<author>`, example ticket prefix like `PROJ-123`) and resolve real values from arguments, config, or `gh`/`git` at runtime.

## Step 1: Parse Arguments

Extract options from `$ARGUMENTS`:

- `--since <when>` → time window for "Did" (e.g. `yesterday`, `2 days ago`, `2024-01-15`, `last friday`). Default: `1 day ago` (use `3 days ago` if today is Monday).
- `--author <user>` → GitHub username / git author to filter by. Default: the current user.
- `--org <org>` → GitHub org/owner to search across. Default: the org/owner of the current repo, resolved via `gh repo view --json owner --jq .owner.login`. Always refer to this as `your-org` in examples — never a real org name.

**Defaults:**

```bash
SINCE="1 day ago"           # widen to "3 days ago" on Mondays
AUTHOR="$(gh api user --jq .login 2>/dev/null || git config user.name)"
ORG="$(gh repo view --json owner --jq .owner.login 2>/dev/null)"
```

## Step 2: Load Configuration

Resolve `.git-workflow/config.yaml` first, then `.claude/config.yaml` as a legacy read-only fallback, to determine the repository and issue tracker:

- `issueTracker.type` → `auto` | `linear` | `jira` | `github` | `none`
- `issueTracker.github.repository` or the current repo (via `gh repo view`)
- `pullRequests.*` for context

If no config exists, use auto-detection and sensible defaults. The standup must work with zero configuration.

### Ground rules (apply to every gathering step below)

1. **Always query GitHub org-wide, never repo-scoped.** Every `gh search prs` call must include `--owner "$ORG"`, not a single `--repo` filter.
2. **Always re-pull fresh data on every run.** Never reuse a previous draft or a cached query result — the user may ask for a standup multiple times in a session, and each must reflect current state.
3. **Single-day windows filter by exact date equality.** When `--since` resolves to `today`, `yesterday`, or one exact date, filter by the date portion of the relevant timestamp (e.g. `closedAt`/`mergedAt`/`publishedAt`) being **equal to** the target date — not `>=` — so a one-day update doesn't sweep in later days. Multi-day windows (e.g. "3 days ago") keep `>=` semantics as before.
4. **The final draft is always written in English**, regardless of what language the user is chatting in.

## Step 3: Gather Git Activity (local)

Collect the user's recent commits across the current repository:

```bash
git log --since="$SINCE" --author="$AUTHOR" --pretty=format:'%h %s' --no-merges
```

Group commits by their type/ticket prefix when the repo uses a commit convention (e.g. `[Feature]`, `fix:`, `PROJ-123`). Summarize — do not paste raw commit lists.

## Step 4: Gather GitHub Activity

Use the `gh` CLI (requires authentication). Handle each call defensively — if `gh` is unavailable or a call fails, skip that section and note it, never abort the whole standup. Every search below is scoped org-wide with `--owner "$ORG"`, per the ground rules in Step 2.

**Recently merged PRs (part of "Did"):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --merged --sort updated \
  --json number,title,repository,url,closedAt,mergedAt --limit 50
```

**Closed-but-possibly-unmerged PRs in the window (needed to verify release timing below):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --state closed --sort updated \
  --json number,title,repository,url,closedAt --limit 50
```

**Opened PRs in the window (so newly opened work shows even if still open):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --created ">=$SINCE" --sort updated \
  --json number,title,repository,url,createdAt,isDraft --limit 50
```

**Open PRs by the user (part of "Next", and "Blockers" if review is stalled):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --state open --sort updated \
  --json number,title,repository,url,reviewDecision,isDraft,statusCheckRollup --limit 20
```

**PRs awaiting the user's review (part of "Next"):**

```bash
gh search prs --review-requested "$AUTHOR" --owner "$ORG" --state open \
  --json number,title,repository,url --limit 20
```

**Releases:**

For each distinct repo encountered among the window's PRs (loop over the distinct repos found — never assume a single repo), run:

```bash
gh release list --repo <owner>/<repo> --json tagName,publishedAt,name
```

Filter to the window where a timestamp is available. Interpret signals:

- `reviewDecision: CHANGES_REQUESTED` or failing `statusCheckRollup` → candidate **Blocker**.
- `reviewDecision: REVIEW_REQUIRED` on an open PR → **Next** (waiting on review).
- `isDraft: true` → **Next** (in progress), not "Did".

## Step 5: Verify Release Timing

Before composing the standup, reconcile "merged" with "actually shipped":

**a. Merged vs closed-unmerged.** For every PR that appears closed in the window, run:

```bash
gh pr view <n> --repo <owner>/<repo> --json state,mergedAt
```

to confirm its true state. Only PRs confirmed `MERGED` count as "Did". Closed-but-unmerged PRs must be flagged separately (e.g. listed as "abandoned, not shipped") and never counted as Did.

**b. Merged != deployed.** For every merged PR, compare its `mergedAt` timestamp against that repo/app's releases (`publishedAt`, gathered in Step 4, sorted ascending). Classify each merged PR into exactly one of:

- **Shipped + deployed**: merged AND a release for that repo/app was published strictly after `mergedAt`.
- **Merged, awaiting release**: merged but no release has been published after `mergedAt` yet (it's on the default branch but not live).

⚠️ A PR that merges a few minutes **after** a release tag is NOT included in that release — always compare actual timestamps, never assume proximity means inclusion. In a monorepo with multiple apps sharing one repo, match a release to the correct app using the repo name or the commit/PR scope prefix (e.g. `feat(app-name): ...`) — never attribute one app's release (e.g. an admin dashboard) to another app's PRs (e.g. a developer portal) just because they share a repo.

**c. Ticket/PR day attribution.** When a tracker ticket shows Done/closed but its underlying PR actually merged or released on an earlier day, attribute the work to the day it merged/released — not the day the ticket was closed — so it isn't double-counted in a later standup.

## Step 6: Gather Issue Tracker Tickets (optional)

If `issueTracker.type` is not `none` and the relevant MCP server is available, fetch BOTH tickets assigned to the user that changed in the window AND their comments — not just status — because real movement/decisions often land in a comment while the status field is unchanged.

### Linear

```
# Use the Linear MCP server if available
mcp__linear__list_issues(assignee: me, updatedAfter: <window>)
# Also fetch comments on each returned issue (e.g. via the Linear comments tool/API)
```

### Jira

```
# Use the Jira MCP server if available
mcp__jira__search_issues(jql: "assignee = currentUser() AND updated >= -1d")
# Also fetch comments on each returned issue
```

### GitHub Issues

```bash
gh search issues --assignee "$AUTHOR" --state all --sort updated \
  --json number,title,repository,url,state --limit 20
```

Map ticket status to sections: recently completed → **Did**; in-progress / todo picked up next → **Next**; blocked/needs-info → **Blockers**. If the tracker is unavailable (not configured, MCP not connected, auth failure, etc.), say so explicitly **at the top of the final output** and offer to reconcile later — never drop it silently.

## Step 7: Compose the Standup

Organize everything into three sections. Keep each bullet short and outcome-focused (what shipped / what's happening), not a commit dump. Link PRs/issues as `#<number>` or full URLs when cross-repo. If a section is empty, write a brief honest line rather than padding. The draft is always composed in English, even if the conversation with the user is in another language.

Under **Did**, split merged PRs into "Shipped + deployed" and "Merged, awaiting release" sub-bullets, per the classification in Step 5.

Output in this paste-ready format:

```markdown
*Standup — {date}*

*Did*
- Shipped + deployed: {merged PRs confirmed live in a release, completed tickets}
- Merged, awaiting release: {merged PRs not yet in a published release}

*Next*
- {open PRs awaiting review, in-progress tickets, planned work}

*Blockers*
- {failing CI, changes requested, waiting-on items — or "None"}
```

## Step 8: Present

If the issue tracker was unavailable, print that caveat as the FIRST line of the output, above `*Standup — {date}*`. Then print the standup as a single copy-pasteable block. After it, add a one-line trailing note listing any other sources that were unavailable (e.g. "Note: `gh` not authenticated; based on Git only.") so the user knows the coverage.

## Configuration Reference

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `issueTracker.type` | `auto` | `linear`, `jira`, `github`, or `none` |
| `issueTracker.github.repository` | current repo | `owner/repo` for GitHub queries |
| `--org` | current repo's owner (via `gh repo view`) | GitHub org/owner to search across — never repo-scoped |

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `gh` not installed or not authenticated | Skip GitHub sections, note it, continue with Git |
| Not inside a git repository | Skip Git section, rely on GitHub search |
| Issue tracker MCP unavailable | Note at the top of the output; offer to reconcile later |
| No release found after a PR's merge | Report as "Merged, awaiting release", not an error |
| No activity in the window | Say so plainly and suggest widening `--since` |
