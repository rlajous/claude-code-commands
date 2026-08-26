---
name: review
description: Perform a comprehensive code review on a GitHub pull request. Use when the user asks to review a PR, review code changes, check a pull request for quality, security, bugs, or best practices, or provides a PR number or GitHub PR URL to review.
argument-hint: "[pr-number-or-url] [--sarif]"
allowed-tools: Read, Grep, Glob, Task, Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), AskUserQuestion, Write
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are performing a comprehensive code review on a GitHub pull request. Your task is to deeply analyze the changes, identify issues across multiple dimensions, and produce a structured review document.

## Step 1: Parse Arguments

Determine the PR to review:

- If a **GitHub URL** was provided: extract `{owner}`, `{repo}`, and `{PR_NUMBER}` from the URL. Set `REPO_FLAG='--repo "{owner}/{repo}"'`
- If a **PR number** was provided as argument: set `REPO_FLAG=""`
- If **no argument**: check for an open PR on the current branch with `REPO_FLAG=""`

```bash
# If no argument provided, try to find PR for current branch
gh pr view --json number,url 2>/dev/null || echo "NO_PR_FOUND"
```

If no PR is found, use the active host user-input mechanism to ask:

**Question**: "Which PR would you like to review? Provide a PR number or GitHub URL."

When `REPO_FLAG` is empty (PR number or current-branch input), resolve `{owner}` and `{repo}` from the PR metadata URL returned by Step 2's `gh pr view` call (which includes the `url` field). Parse `{owner}` and `{repo}` from the URL pattern `https://github.com/{owner}/{repo}/pull/{number}`.

## Step 2: Fetch PR Metadata

```bash
gh pr view {PR_NUMBER} {REPO_FLAG} --json number,title,body,author,state,baseRefName,baseRefOid,headRefName,headRefOid,files,url,additions,deletions,changedFiles,labels,reviewRequests,createdAt
```

If `{owner}` and `{repo}` were not set in Step 1 (i.e., input was a PR number or current branch), extract them from the `url` field in the response (format: `https://github.com/{owner}/{repo}/pull/{number}`).

**Error Handling:**

| Scenario | Action |
|----------|--------|
| `gh` not installed | Provide installation instructions: `brew install gh` or see https://cli.github.com |
| Not authenticated | Instruct to run `gh auth login` |
| PR not found | Show error, ask user to verify PR number |
| PR is merged | Inform user PR is already merged, ask if they still want to review |
| PR is closed | Inform user PR is closed, ask if they still want to review |

## Step 3: Ask for Review Context

Ask the following single question through the active host user-input mechanism:

**Question**: "Any specific focus areas, business context, or known risks for this review? (Type 'skip' to proceed without additional context)"

**Examples:**

- "This touches the payment flow — watch for data integrity issues"
- "Focus on performance, we're seeing slow responses"
- "New developer's first PR, be thorough"
- "skip"

## Step 4: Collect Changes

Resolve `CONFIG_PATH` once: use `.git-workflow/config.yaml` when present, otherwise `.claude/config.yaml` as a legacy read-only fallback. Use defaults only when neither exists.

Get the diff and assess its size:

```bash
# Get diff line count
gh pr diff {PR_NUMBER} {REPO_FLAG} | wc -l
```

**Load from the resolved `CONFIG_PATH` (if one exists):**

```yaml
review:
  maxDiffLines: 3000
```

**Default: 3000 lines**

- If diff ≤ maxDiffLines: ingest the full diff with `gh pr diff {PR_NUMBER} {REPO_FLAG}`
- If diff > maxDiffLines: read files individually in Step 6 (skip full diff)

Also collect the file list:

```bash
gh pr view {PR_NUMBER} {REPO_FLAG} --json files --jq '.files[].path'
```

## Step 5: Categorize Files

Categorize changed files for prioritized review:

**Priority Order:**

1. **New source files** — New code requires the most scrutiny
2. **Business logic** — Core application code (services, models, domain logic)
3. **API layer** — Controllers, routes, handlers, resolvers
4. **Infrastructure** — Config, deployment, CI/CD, environment
5. **Tests** — Test files and fixtures
6. **Auto-generated** — Lock files, compiled output, `dist/`

**Skip auto-generated files:**

- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`
- `dist/`, `build/`, `.next/`, `__pycache__/`
- Files with `// @generated` or `# auto-generated` headers

**Never skip migration files:**

Migration SQL files (`migrations/`, `*migration*.sql`, or SQL files altering schema/data) must always be reviewed regardless of size. Migrations can contain destructive schema changes (DROP TABLE, ALTER COLUMN, etc.) that are critical to catch during review.

**For large PRs (30+ changed files):**

Prioritize review in this order: new files → business logic → API layer → infrastructure → tests. Summarize but don't deep-review auto-generated files.

## Step 6: Read Source Files

For each categorized file (in priority order):

```bash
# Read the full source file for architectural context
cat -- "{file_path}"
```

**Important:** Read full files, not just diffs. Diffs show what changed but full files reveal:

- Whether the change fits the existing patterns
- Missing error handling in surrounding code
- Architectural context for the modification

**Also read key dependencies:**

- If a file imports a service/module that was NOT changed, read it to understand the contract
- Read type definitions, interfaces, or schemas referenced by changed files
- Read configuration files if config was changed

## Step 7: Dispatch Specialized Review Agents (parallel)

Instead of reviewing every dimension inline, fan out to focused subagents through the active host's subagent mechanism and aggregate their findings. This yields sharper, single-concern analysis than one monolithic pass.

**Select aspects** from `$ARGUMENTS` (space-separated; default `all`):

- `code` — general quality + bug detection → **`pr-reviewer`** agent
- `errors` — swallowed errors / inadequate error handling → **`silent-failure-hunter`** agent
- `types` — type design, invariants, encapsulation → **`type-design-analyzer`** agent
- `tests` — behavioral coverage gaps → **`pr-test-analyzer`** agent
- `comments` — comment rot / inaccurate docstrings → **`comment-analyzer`** agent
- `all` — every applicable agent (default)

**Map changed files to applicable agents** (only launch what applies):

| Signal in the changed files | Agent to launch |
|-----------------------------|-----------------|
| Always (any code change) | `pr-reviewer` |
| try/catch, error handling, fallbacks | `silent-failure-hunter` |
| New/modified types, interfaces, schemas | `type-design-analyzer` |
| Test files added/changed, or new behavior lacking tests | `pr-test-analyzer` |
| Comments/docstrings added or changed | `comment-analyzer` |

**Launch in parallel:** start every applicable named agent before waiting so the agents run concurrently. Give each agent the PR number/repo, `baseRefOid` as `BASE_SHA`, `headRefOid` as `HEAD_SHA`, changed-file list, and diff (or file paths for large PRs). The `pr-reviewer` must use `BASE_SHA...HEAD_SHA` when it needs to reconstruct the PR diff; it must not substitute the locally checked-out `HEAD`. Wait for every agent and collect all findings before continuing.

> **Review lenses** the general `pr-reviewer` pass (and your own synthesis) applies — architecture, business logic, data integrity, error handling, security, performance, testing, code quality. Use them to fill gaps the specialized agents don't cover. Full checklist: see `references/review-lenses.md`.

## Step 8: Identify Open Questions

Collect questions that **cannot be answered from code alone**:

- Business rule ambiguities ("Should this return 404 or empty array?")
- Design intent ("Is this intentionally different from the pattern in X?")
- Volume/scale expectations ("How many concurrent users are expected?")
- External system behavior ("What does this API return on timeout?")
- Migration concerns ("Do existing records need backfilling?")

## Step 9: Score, Filter, and Categorize Findings

First **aggregate** the findings from all specialized agents plus your own general pass, de-duplicating any that overlap (same file+line+issue).

**Confidence score (0–100).** Assign each finding a confidence that it is a real, actionable defect in the changed code. **Only keep findings with confidence ≥ 80.** Discard the rest (they add noise). This mirrors the high-signal bar used by mature review tooling.

**False-positive taxonomy — drop a finding (do NOT report) if it is:**

- **Pre-existing** — the issue is on lines this PR did not modify (not introduced by this change).
- **Linter/type-checker-catchable** — a lint or type error that CI would already surface.
- **Intentionally silenced** — explicitly suppressed via a lint-ignore/`// eslint-disable`/`# noqa` with a reason.
- **Style-only nit** already handled by a formatter (Prettier/Black/gofmt).
- **Speculative** — depends on runtime facts you cannot verify from the diff (score it below 80).

Then assign each surviving finding a severity:

| Severity | Criteria | Examples |
|----------|----------|----------|
| **BLOCKING** | Deployment-preventing issues | Data loss risk, security vulnerability, broken functionality |
| **HIGH** | Correctness or business logic bugs | Wrong calculation, missing validation, race condition |
| **MEDIUM** | Robustness and maintainability | Missing error handling, tight coupling, missing tests |
| **LOW** | Polish and minor improvements | Naming, style, minor optimizations, documentation |

Each finding should include:

- **File and line reference**: `src/services/auth.ts:45`
- **Confidence**: `0–100` (only findings ≥ 80 are reported)
- **Issue description**: What's wrong and why it matters
- **Suggested fix**: Concrete code or approach to resolve it
- **Severity justification**: Why this severity level

## Step 10: Build Architecture Flow

Create an ASCII diagram tracing execution from entry point through the call chain:

```text
Request → Controller → Service → Repository → Database
                    ↓
              Validation
                    ↓
              External API
```

Include:

- Entry points (HTTP endpoints, event handlers, cron jobs)
- Key function calls in order
- External system interactions (databases, APIs, queues, caches)
- Error/retry paths

## Step 11: Generate Review Document

Produce a structured markdown document:

````markdown
# Code Review: PR #{number} — {title}

## Metadata

| Field | Value |
|-------|-------|
| **PR** | #{number} |
| **Author** | {author} |
| **Branch** | `{head}` → `{base}` |
| **Files Changed** | {count} |
| **Additions** | +{additions} |
| **Deletions** | -{deletions} |
| **Reviewed** | {date} |

## Overall Assessment

{1-2 paragraph summary: what the PR does, whether it's ready to merge, and the most important concerns}

**Verdict**: {APPROVE | REQUEST CHANGES | NEEDS DISCUSSION}

## Architecture Flow

```
{ASCII diagram from Step 10}
```

## Questions for Author

{Numbered list from Step 8. If none, write "No open questions."}

## Findings

### BLOCKING

{Each finding with file reference, description, and suggested fix. If none, write "No blocking issues found."}

### HIGH

{Each finding with file reference, description, and suggested fix. If none, write "No high-severity issues found."}

### MEDIUM

{Each finding with file reference, description, and suggested fix. If none, omit section.}

### LOW

{Each finding with file reference, description, and suggested fix. If none, omit section.}

## What's Done Well

{Bullet list of positive observations — good patterns, thorough tests, clean design}

## Summary

| Severity | Count |
|----------|-------|
| BLOCKING | {n} |
| HIGH | {n} |
| MEDIUM | {n} |
| LOW | {n} |
| **Total** | **{n}** |

**Recommended fix priority:**

1. {Most important fix}
2. {Second most important}
3. {Third most important}
````

## Step 12: Save Review

**Load from the resolved `CONFIG_PATH` (if one exists):**

```yaml
review:
  saveLocally: true
  reviewsDir: docs
```

**Defaults:** `saveLocally: true`, `reviewsDir: docs`

If `saveLocally` is true:

```bash
# Extract feature name from branch
FEATURE_NAME=$(echo "{head_branch}" | sed 's|.*/||' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Ensure directory exists
mkdir -p -- "{reviewsDir}"

# Save review document
# Write to: "{reviewsDir}/code-review-{feature-name}.md"
```

Write the review document to the file. Do NOT commit it.

If `saveLocally` is false: the review content is held in memory for posting or display. No file is written.

## Step 13: Confirm Before Posting

**Load from the resolved `CONFIG_PATH` (if one exists):**

```yaml
review:
  postToGitHub: ask  # ask | always | never
```

**Default:** `ask`

If `postToGitHub` is `always`: skip to Step 14.
If `postToGitHub` is `never`: skip to Step 15.
If `postToGitHub` is `ask`: use the active host user-input mechanism:

**Question**: "How would you like to proceed with this review?"

**Options:**

1. Post review as a comment on the PR
2. Save locally only — choosing this option overrides `saveLocally` config and writes the review file locally even if automatic saving was disabled in Step 12
3. Let me edit the review first, then I'll tell you when to post

## Step 14: Post to GitHub

If the user chose to post:

**Use SHA-based permalinks for every file reference** so the links stay valid even after the branch moves. First capture the PR head commit SHA:

```bash
# Full head SHA of the PR (do NOT inline $(git rev-parse HEAD) into the Markdown — the link must be literal)
HEAD_SHA=$(gh pr view {PR_NUMBER} {REPO_FLAG} --json headRefOid --jq '.headRefOid')
```

Render each finding's location as a literal permalink:

```text
https://github.com/{owner}/{repo}/blob/{HEAD_SHA}/{file_path}#L{start}-L{end}
```

Build the URL with the resolved SHA already substituted (a literal 40-char hash in the Markdown) — never leave a `$(...)` command substitution or a branch name in the posted text.

```bash
# Post review as a PR review comment
gh api "repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews" \
  --method POST \
  -f body="$(cat <<'REVIEW_EOF'
{REVIEW_CONTENT}
REVIEW_EOF
)" \
  -f event="COMMENT"
```

**Handle body size limit:**

GitHub has a ~65,000 character limit for review bodies. If the review exceeds this:

1. Truncate the review at the Summary section
2. If the review was saved locally, add a note: "Full review available locally at `{file_path}`". Otherwise, add: "Review was truncated due to GitHub size limits."
3. Post the truncated version

**Error Handling:**

| Scenario | Action |
|----------|--------|
| Not authorized | Inform user, suggest `gh auth login` with required scopes |
| API rate limit | Inform user, suggest waiting or posting manually |
| Network error | Save locally, inform user the post failed |

## Step 15: Confirm

Output final summary:

```text
Review complete for PR #{number}: {title}

Findings:
  BLOCKING: {n}
  HIGH:     {n}
  MEDIUM:   {n}
  LOW:      {n}

{If saved locally:}
Review saved: {file_path}

{If posted to GitHub:}
Review posted: {pr_url}

{If BLOCKING or HIGH issues found:}
⚠ This PR has issues that should be addressed before merging.

{If no BLOCKING or HIGH issues:}
✓ No critical issues found. PR looks good for merge.
```

## Configuration Reference

| Setting | Default | Description |
|---------|---------|-------------|
| `review.saveLocally` | `true` | Save review document to local file |
| `review.reviewsDir` | `docs` | Directory for review documents |
| `review.postToGitHub` | `ask` | Post to PR: `ask`, `always`, or `never` |
| `review.maxDiffLines` | `3000` | Max diff lines before file-by-file reading |

### SARIF Export (`--sarif`)

If `--sarif` was passed as an argument, also export the findings from Step 9 as a SARIF 2.1.0 log for CI / code-scanning ingestion. Serialize the findings to the JSON array shape `[{ file, line, severity, confidence, message, rule }]` and pipe it through the converter script:

```bash
echo '{FINDINGS_JSON}' | node "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts/to-sarif.mjs" > review.sarif
```

Tell the user the SARIF file was written to `review.sarif` (e.g. for `github/codeql-action/upload-sarif`).

## Error Handling

| Scenario | Action |
|----------|--------|
| `gh` not installed | Provide installation instructions |
| Not authenticated | Run `gh auth login` instructions |
| PR not found | Show error, ask user to verify |
| PR is merged/closed | Inform user, ask if they still want to review |
| Diff too large | Switch to file-by-file reading |
| Review too long for GitHub | Truncate and note full review location |
| No files changed | Inform user the PR has no file changes |
| Network error on post | Save locally, report error |

## Examples

### Standard Review

```text
User: /review 123
Agent: [Fetches PR #123 metadata]
Agent: Any focus areas? -> "skip"
Agent: [Reads 8 changed files, analyzes across all dimensions]
Agent: [Generates review with 0 BLOCKING, 2 HIGH, 3 MEDIUM, 1 LOW]
Agent: How to proceed? -> "Post to PR"
Result: Review posted to PR #123
        Review saved: docs/code-review-add-auth-flow.md
```

### Review with Context

```text
User: /review https://github.com/org/repo/pull/456
Agent: [Fetches PR #456]
Agent: Focus areas? -> "This changes the billing flow, watch for data integrity"
Agent: [Deep analysis with focus on transactions and idempotency]
Agent: [Finds 1 BLOCKING issue: missing transaction wrapper]
Result: Review posted with REQUEST CHANGES verdict
```

### Large PR Review

```text
User: /review 789
Agent: [Fetches PR #789 — 45 files changed, 4200 line diff]
Agent: [Switches to file-by-file reading, prioritizes business logic]
Agent: [Reviews top 30 files in priority order, summarizes remainder]
Result: Review saved locally (too large to post as single comment)
```
