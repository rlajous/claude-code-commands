---
description: Create a pull request with comprehensive description following repo best practices
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
---

You are helping create a pull request with a comprehensive description. Your task is to gather information, generate the PR description, push the branch, and create the PR using project conventions.

## Step 1: Load Configuration

Check for configuration and context:

```bash
# Check for config and context files
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
[ -f ".claude/.pr-context.json" ] && echo "CONTEXT=true" || echo "CONTEXT=false"

# Get current branch
git branch --show-current
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
workflow:
  developmentBranch: staging
  productionBranch: main
pullRequests:
  targetBranch: staging
  reviewers: []
  labels: []
issueTracker:
  type: auto
```

**Load from `.claude/.pr-context.json` (if exists):**

```json
{
  "ticket_id": "PROJ-1234",
  "ticket_url": "https://...",
  "ticket_title": "Ticket title",
  "branch": "fix/proj-1234-description",
  "type": "fix",
  "description": "Short description"
}
```

**Default Values (when no config):**

```yaml
pullRequests:
  targetBranch: staging
  reviewers: []
  labels: []
```

If context file is missing or incomplete:

- Inform the user they should run `/start` and `/commit` first
- Ask for missing information (ticket ID, branch name)

## Step 2: Verify State

Check current git state:

```bash
# Current branch
CURRENT_BRANCH=$(git branch --show-current)

# Commits on this branch vs target
TARGET_BRANCH=$(config.pullRequests.targetBranch || "staging")
git log --oneline ${TARGET_BRANCH}..HEAD

# Any uncommitted changes?
git status --short
```

**Warnings:**

- If uncommitted changes exist: "You have uncommitted changes. Run `/commit` first?"
- If no commits on branch: "No commits to create PR. Make changes and run `/commit` first."
- If on target branch: "You're on the target branch. Switch to a feature branch first."

## Step 3: Gather Changed Files

Analyze what changed:

```bash
# Files changed vs target branch
TARGET_BRANCH=$(config.pullRequests.targetBranch || "staging")
git diff --name-only ${TARGET_BRANCH}...HEAD
git diff --stat ${TARGET_BRANCH}...HEAD

# Commit messages on this branch
git log --oneline ${TARGET_BRANCH}..HEAD
```

Display summary:

```
Changes on this branch:

Files changed: 5
Commits: 3

Files:
  M src/services/auth.ts (+45, -12)
  M src/controllers/user.ts (+23, -8)
  A src/utils/validation.ts (+67)
  M tests/auth.test.ts (+89, -0)
  M package.json (+2, -1)

Commits:
  abc1234 [Fix] Update authentication flow (PROJ-1234)
  def5678 [Fix] Add input validation (PROJ-1234)
  ghi9012 [Fix] Add unit tests (PROJ-1234)
```

## Step 4: Gather PR Information

Ask the user for additional context (use AskUserQuestion tool):

### Question 1: Summary of Changes

**Question**: "Briefly describe what this PR does and why"

**Example**: "Fixes authentication timeout by implementing token refresh and adding proper error handling"

### Question 2: What Issues Were Fixed

**Question**: "What issues did this PR fix? List each problem and solution."

**Format**: Numbered list

**Example**:

```
1. Token expiry not handled -> Added automatic token refresh
2. No validation on user input -> Added input sanitization
3. Missing error messages -> Added user-friendly error responses
```

### Question 3: Testing Instructions

**Question**: "How should reviewers test these changes?"

**Options:**

1. Run existing tests (default)
2. Manual testing required - will provide instructions
3. Both automated and manual testing needed

If manual testing, ask for specific test steps.

### Question 4: Breaking Changes

**Question**: "Are there any breaking changes?"

**Options:**

- No breaking changes (default)
- Yes, there are breaking changes

If yes, ask for description of breaking changes.

## Step 5: Generate PR Description

Use this template and fill with collected data:

````markdown
## Description

{Fixes|Closes|Relates to} {ticket_id}

{High-level summary from user input}

### Changes

{For each commit or logical change, create a bullet point}

- **{Component/Area}**: {Description of change}

### Why

{Root cause explanation from user}

{Solution explanation}

---

## Testing

### Automated Tests

```bash
{testing.unit command or auto-detected}
```

### Manual Testing

{If manual testing required, include steps}

{If API endpoint, include curl example:}

```bash
curl -X {METHOD} "{base_url}/{endpoint}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
```

### Expected Result

**Before**: {Description of broken behavior}
**After**: {Description of fixed behavior}

---

## Checklist

- [ ] Tests pass locally
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (if needed)
{If breaking changes:}
- [ ] Breaking changes documented
- [ ] Migration guide provided
````

### Customize for Issue Tracker

**Linear:**

```markdown
## Description

Fixes {ticket_id}

{Linear will auto-link to the ticket}
```

**Jira:**

```markdown
## Description

Fixes [{ticket_id}]({jira_base_url}/browse/{ticket_id})
```

**GitHub Issues:**

```markdown
## Description

Fixes #{issue_number}
```

## Step 6: Push Branch

```bash
# Push branch to remote with upstream tracking
git push -u origin {branch_name}
```

**Error Handling:**

- If branch already pushed with changes: Ask to force push or just update
- If push fails: Show error and suggest solutions

## Step 7: Create PR

### Format PR Title

Use commit message format from config (default: `[{type}] {message} ({ticket})`):

```
[Fix] Update authentication flow (PROJ-1234)
[Feature] Add dark mode support (ENG-456)
[Hotfix] Fix critical security issue (ABC-789)
```

### Create PR with gh CLI

```bash
# Determine target branch
TARGET_BRANCH=$(config.pullRequests.targetBranch || "staging")

# Create PR
gh pr create \
  --base "${TARGET_BRANCH}" \
  --title "{PR_TITLE}" \
  --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)"
```

### Add Reviewers (If Configured)

```bash
# From config.pullRequests.reviewers
gh pr edit {PR_NUMBER} --add-reviewer "user1,user2,team/name"
```

### Add Labels (If Configured)

```bash
# From config.pullRequests.labels
gh pr edit {PR_NUMBER} --add-label "needs-review,bug"
```

### Assign to Self

```bash
gh pr edit {PR_NUMBER} --add-assignee @me
```

## Step 8: Link to Issue Tracker

### Linear (via MCP)

If Linear MCP server is available, update ticket status:

```
mcp__linear__update_issue(id: ticket_id, state: "In Review")
```

The MCP server handles authentication automatically.

### Jira (via MCP)

If Jira MCP server is available, add PR link and update status:

```
mcp__jira__add_comment(issueKey: ticket_id, body: "PR: {PR_URL}")
```

### GitHub Issues

GitHub automatically links PRs with "Fixes #123" syntax (no additional action needed).

## Step 9: Confirm and Cleanup

Output confirmation:

```
Branch pushed: {branch_name}
PR created: {PR_URL}
Title: {PR_TITLE}
Target: {target_branch}
Reviewers: {reviewers_list or "None configured"}
Labels: {labels_list or "None"}

PR is ready for review!
```

### Optional Cleanup

Ask if user wants to clean up context:

```bash
# Remove context file (optional)
rm .claude/.pr-context.json
```

Or keep for reference until PR is merged.

## Configuration Reference

| Setting                   | Default    | Description                     |
| ------------------------- | ---------- | ------------------------------- |
| `pullRequests.targetBranch` | `staging`  | Default base branch for PRs     |
| `pullRequests.reviewers`  | `[]`       | Default reviewers               |
| `pullRequests.labels`     | `[]`       | Default labels                  |
| `issueTracker.type`       | `auto`     | Issue tracker integration       |
| `workflow.developmentBranch` | `staging` | Development branch name        |

## Error Handling

| Scenario                   | Action                                          |
| -------------------------- | ----------------------------------------------- |
| `gh` not installed         | Provide installation instructions               |
| Not authenticated          | Run `gh auth login` instructions                |
| No commits on branch       | Suggest running `/commit` first                 |
| Uncommitted changes        | Suggest running `/commit` first                 |
| Branch not pushed          | Push automatically before PR                    |
| PR already exists          | Show existing PR URL, ask to update             |
| Context file missing       | Gather info manually, suggest `/start`          |
| Target branch doesn't exist | Error with suggestion                          |

## Examples

### Standard Flow

```
User: /finish
Agent: [Shows 5 files changed, 3 commits]
Agent: Describe what this PR does? -> "Fixes auth timeout"
Agent: What issues were fixed? -> "1. Token expiry -> Added refresh"
Agent: How to test? -> "Run existing tests"
Agent: Breaking changes? -> "No"
Result: PR #123 created
        URL: https://github.com/org/repo/pull/123
```

### With Reviewers and Labels

```
User: /finish
Agent: [Gathers info]
Result: PR #124 created
        Reviewers: @alice, @bob, @team/backend
        Labels: needs-review, feature
```

### With Linear Integration

```
User: /finish
Agent: [Creates PR]
Agent: [Updates Linear ticket ENG-456 to "In Review"]
Result: PR #125 created
        Ticket ENG-456 updated to "In Review"
```

## PR Description Templates

### Bug Fix Template

```markdown
## Description

Fixes {ticket_id}

This PR fixes {brief description of bug}.

### Root Cause

{Explanation of why the bug occurred}

### Solution

{How the fix addresses the root cause}

### Changes

- {Change 1}
- {Change 2}

## Testing

{Test instructions}
```

### Feature Template

```markdown
## Description

Implements {ticket_id}

This PR adds {feature name} which allows users to {capability}.

### Implementation

{High-level overview of implementation approach}

### Changes

- {Change 1}
- {Change 2}

## Testing

{Test instructions}

## Screenshots

{If UI changes, include before/after screenshots}
```
