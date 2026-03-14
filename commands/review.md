---
description: Perform a comprehensive code review on a GitHub PR
argument-hint: "[pr-number-or-url]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Write
user-invocable: true
---

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

If no PR is found, use AskUserQuestion to ask:

**Question**: "Which PR would you like to review? Provide a PR number or GitHub URL."

When `REPO_FLAG` is empty (PR number or current-branch input), resolve `{owner}` and `{repo}` from the PR metadata URL returned by Step 2's `gh pr view` call (which includes the `url` field). Parse `{owner}` and `{repo}` from the URL pattern `https://github.com/{owner}/{repo}/pull/{number}`.

## Step 2: Fetch PR Metadata

```bash
gh pr view {PR_NUMBER} {REPO_FLAG} --json number,title,body,author,state,baseRefName,headRefName,files,url,additions,deletions,changedFiles,labels,reviewRequests,createdAt
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

Use AskUserQuestion with a single question:

**Question**: "Any specific focus areas, business context, or known risks for this review? (Type 'skip' to proceed without additional context)"

**Examples:**

- "This touches the payment flow — watch for data integrity issues"
- "Focus on performance, we're seeing slow responses"
- "New developer's first PR, be thorough"
- "skip"

## Step 4: Collect Changes

Get the diff and assess its size:

```bash
# Get diff line count
gh pr diff {PR_NUMBER} {REPO_FLAG} | wc -l
```

**Load from `.claude/config.yaml` (if exists):**

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

## Step 7: Deep Analysis

Review across these dimensions:

### Architecture & Design

- Does the change follow existing patterns in the codebase?
- Is there proper separation of concerns?
- Are dependencies flowing in the right direction?
- Is coupling appropriate or excessive?
- Are new abstractions justified?

### Business Logic & Correctness

- Trace the execution end-to-end from entry point to response
- Check edge cases: empty inputs, null values, boundary conditions
- Look for race conditions in concurrent operations
- Verify state transitions are valid
- Check that error paths don't leave data in an inconsistent state

### Data Integrity

- Are database operations wrapped in transactions where needed?
- Is idempotency handled for operations that could retry?
- What happens on partial failure?
- Are foreign key relationships maintained?

### Error Handling & Resilience

- Are errors caught at appropriate levels?
- Do catch blocks handle errors meaningfully (not silently swallowed)?
- Are retries implemented where appropriate?
- Are error messages helpful for debugging?
- Are external service failures handled gracefully?

### Security & Validation

- Is user input validated before use?
- Are there injection risks (SQL, command, template)?
- Are secrets kept out of code and logs?
- Are authentication/authorization checks in place?
- Is sensitive data properly handled (no logging PII, proper encryption)?

### Performance

- Are there N+1 query patterns?
- Could operations be batched?
- Are there memory concerns with large datasets?
- Are blocking operations in async contexts?
- Are expensive operations cached where appropriate?

### Testing

- Are there tests for the new functionality?
- Do tests cover edge cases and error scenarios?
- Are tests testing behavior, not implementation details?
- Is test coverage adequate for the risk level of the change?

### Code Quality

- Does naming follow project conventions?
- Is there dead code or unnecessary complexity?
- Are comments used appropriately (explaining why, not what)?
- Is the code readable and maintainable?

## Step 8: Identify Open Questions

Collect questions that **cannot be answered from code alone**:

- Business rule ambiguities ("Should this return 404 or empty array?")
- Design intent ("Is this intentionally different from the pattern in X?")
- Volume/scale expectations ("How many concurrent users are expected?")
- External system behavior ("What does this API return on timeout?")
- Migration concerns ("Do existing records need backfilling?")

## Step 9: Categorize Findings

Assign each finding a severity:

| Severity | Criteria | Examples |
|----------|----------|----------|
| **BLOCKING** | Deployment-preventing issues | Data loss risk, security vulnerability, broken functionality |
| **HIGH** | Correctness or business logic bugs | Wrong calculation, missing validation, race condition |
| **MEDIUM** | Robustness and maintainability | Missing error handling, tight coupling, missing tests |
| **LOW** | Polish and minor improvements | Naming, style, minor optimizations, documentation |

Each finding should include:

- **File and line reference**: `src/services/auth.ts:45`
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

**Load from `.claude/config.yaml` (if exists):**

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

**Load from `.claude/config.yaml` (if exists):**

```yaml
review:
  postToGitHub: ask  # ask | always | never
```

**Default:** `ask`

If `postToGitHub` is `always`: skip to Step 14.
If `postToGitHub` is `never`: skip to Step 15.
If `postToGitHub` is `ask`: use AskUserQuestion:

**Question**: "How would you like to proceed with this review?"

**Options:**

1. Post review as a comment on the PR
2. Save locally only — choosing this option overrides `saveLocally` config and writes the review file locally even if automatic saving was disabled in Step 12
3. Let me edit the review first, then I'll tell you when to post

## Step 14: Post to GitHub

If the user chose to post:

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
