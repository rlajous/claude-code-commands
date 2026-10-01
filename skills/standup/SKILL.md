---
name: standup
description: Generate an async standup update (Did / Next / Blockers) from recent Git and GitHub activity — including org-wide PR and release search, ticket comments, and release-timing verification — and optionally issue-tracker tickets. Use when the user asks for a "standup", "daily update", "async update", "what did I do", "update for the meeting", or wants to summarize their recent work for a team thread.
argument-hint: "[--since <when>] [--author <user>] [--org <org>]"
allowed-tools: Read, Grep, Glob, Bash(git log:*), Bash(git config:*), Bash(gh api:*), Bash(gh repo view:*), Bash(gh search prs:*), Bash(gh search issues:*), Bash(gh pr view:*), Bash(gh issue view:*), Bash(gh release list:*), Bash(gh release view:*)
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

`gh search prs`'s `--merged-at`, `--closed`, and `--created` flags are date qualifiers (an
absolute date or `>=`/`..`-style range), not free-text relative expressions — resolve `SINCE` to
an ISO date yourself (you know today's date) before using it in any search:

```bash
SINCE_DATE="2026-09-30"      # resolve $SINCE ("1 day ago", "last friday", etc.) to YYYY-MM-DD
WINDOW_QUALIFIER=">=$SINCE_DATE"   # multi-day window
# WINDOW_QUALIFIER="$SINCE_DATE"   # use this exact-date form instead for single-day windows (today/yesterday/one date), per ground rule 3 below
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
3. **Single-day windows filter by exact date equality.** When `--since` resolves to `today`, `yesterday`, or one exact date, set `WINDOW_QUALIFIER="$SINCE_DATE"` (exact match, no `>=`) so a one-day update doesn't sweep in later days, and apply the same exact-date check to `publishedAt` when scanning releases. Multi-day windows (e.g. "3 days ago") keep `WINDOW_QUALIFIER=">=$SINCE_DATE"` as shown above.
4. **The final draft is always written in English**, regardless of what language the user is chatting in.

## Step 3: Gather Git Activity (local)

Collect the user's recent commits across the current repository:

```bash
git log --since="$SINCE" --author="$AUTHOR" --pretty=format:'%h %s' --no-merges
```

Group commits by their type/ticket prefix when the repo uses a commit convention (e.g. `[Feature]`, `fix:`, `PROJ-123`). Summarize — do not paste raw commit lists.

## Step 4: Gather GitHub Activity

Use the `gh` CLI (requires authentication). Handle each call defensively — if `gh` is unavailable or a call fails, skip that section and note it, never abort the whole standup. Every search below is scoped org-wide with `--owner "$ORG"`, per the ground rules in Step 2.

**Recently merged PRs (part of "Did"):** filter by `--merged-at` so the window is applied before
the result limit, not after. `gh search prs` doesn't expose a `mergedAt` JSON field — the exact
merge timestamp comes from the `gh pr view` lookup in Step 5a.

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --merged --merged-at "$WINDOW_QUALIFIER" --sort updated \
  --json number,title,repository,url,closedAt --limit 50
```

**Closed-but-possibly-unmerged PRs in the window (needed to verify release timing below):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --state closed --closed "$WINDOW_QUALIFIER" --sort updated \
  --json number,title,repository,url,closedAt --limit 50
```

**Opened PRs in the window (so newly opened work shows even if still open):**

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --created "$WINDOW_QUALIFIER" --sort updated \
  --json number,title,repository,url,createdAt,isDraft --limit 50
```

**Open PRs by the user (part of "Next", and "Blockers" if review is stalled):** `gh search prs`
doesn't expose `reviewDecision` or `statusCheckRollup` either — fetch those per PR in the
interpretation step below.

```bash
gh search prs --author "$AUTHOR" --owner "$ORG" --state open --sort updated \
  --json number,title,repository,url,isDraft --limit 20
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

For each open PR from the two searches above, enrich it with `gh pr view <n> --repo <owner>/<repo> --json reviewDecision,statusCheckRollup` and interpret:

- `reviewDecision: CHANGES_REQUESTED` or failing `statusCheckRollup` → candidate **Blocker**.
- `reviewDecision: REVIEW_REQUIRED` → **Next** (waiting on review).
- `isDraft: true` (from the search results) → **Next** (in progress), not "Did".

Filter releases to the window using `publishedAt` and the same `WINDOW_QUALIFIER` logic (exact-date for single-day windows, `>=` otherwise).

## Step 5: Verify Release Timing

Before composing the standup, reconcile "merged" with "actually shipped":

**a. Merged vs closed-unmerged.** For every PR that appears closed in the window, run:

```bash
gh pr view <n> --repo <owner>/<repo> --json state,mergedAt
```

to confirm its true state. Only PRs confirmed `MERGED` count as "Did". Closed-but-unmerged PRs must be flagged separately (e.g. listed as "abandoned, not shipped") and never counted as Did.

**b. Merged != deployed.** Comparing `mergedAt` against a release's `publishedAt` is only a
candidate filter, never proof — a later-published release can still be cut from a point in
history that doesn't include this merge (e.g. a release branch, or an out-of-order cut). For every
merged PR, first narrow to releases (gathered in Step 4) published after `mergedAt` for the same
repo/app, then **confirm inclusion** rather than assuming it:

```bash
gh api "repos/<owner>/<repo>/compare/<tagName>...<mergeCommitSha>" --jq .status
```

`identical` or `behind` means the merge commit is already reachable from that tag (confirmed
included). `ahead` means it is not yet in that release despite the later timestamp. Classify each
merged PR into exactly one of:

- **Shipped + deployed**: merged AND the ancestry check confirms a release for that repo/app
  includes the merge commit.
- **Merged, awaiting release**: merged but no release yet confirmed to include it (whether because
  none has published since, or a later release's ancestry check came back `ahead`).

In a monorepo with multiple apps sharing one repo, match a release to the correct app using the
repo name or the commit/PR scope prefix (e.g. `feat(app-name): ...`) before running the ancestry
check — never attribute one app's release (e.g. an admin dashboard) to another app's PRs (e.g. a
developer portal) just because they share a repo.

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
# Use the Jira MCP server if available — use the resolved $SINCE_DATE, not a hardcoded window
mcp__jira__search_issues(jql: "assignee = currentUser() AND updated >= '$SINCE_DATE'")
# Also fetch comments on each returned issue
```

### GitHub Issues

```bash
gh search issues --assignee "$AUTHOR" --updated "$WINDOW_QUALIFIER" --sort updated \
  --json number,title,repository,url,state,updatedAt --limit 20
```

(omit `--state` to get both open and closed — `gh search issues --state` only accepts `open`/`closed`, not `all`)

For each returned issue, also fetch its comments (e.g. `gh issue view <n> --repo <owner>/<repo> --json comments` or `gh api repos/<owner>/<repo>/issues/<n>/comments`) — the same "comments carry the real movement" rule from Step 2's ground rules applies here too.

Map ticket status to sections: recently completed → **Did**; in-progress / todo picked up next → **Next**; blocked/needs-info → **Blockers**. A ticket marked Done/completed does not by itself mean the underlying work is deployed — list it under Did as a completed ticket, separate from the PR-based "Shipped + deployed" / "Merged, awaiting release" split in Step 7. If the tracker is unavailable (not configured, MCP not connected, auth failure, etc.), say so explicitly **at the top of the final output** and offer to reconcile later — never drop it silently.

## Step 7: Compose the Standup

Organize everything into three sections. Keep each bullet short and outcome-focused (what shipped / what's happening), not a commit dump. Link PRs/issues as `#<number>` or full URLs when cross-repo. If a section is empty, write a brief honest line rather than padding. The draft is always composed in English, even if the conversation with the user is in another language.

Under **Did**, split merged PRs into "Shipped + deployed" and "Merged, awaiting release" sub-bullets per the classification in Step 5, and list completed tracker tickets separately — a ticket being Done doesn't confirm its PR shipped or deployed; only the ancestry-checked PR classification earns the "Shipped + deployed" label.

Output in this paste-ready format:

```markdown
*Standup — {date}*

*Did*
- Shipped + deployed: {merged PRs confirmed, via ancestry check, to be in a published release}
- Merged, awaiting release: {merged PRs not yet confirmed in a published release}
- Completed tickets: {tracker tickets marked Done/completed in the window}

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
