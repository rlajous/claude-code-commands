---
description: Stage and commit changes with proper formatting following repo conventions
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Edit
---

You are helping commit changes for a pull request. Your task is to stage changes, generate a properly formatted commit message following project conventions, and handle pre-commit hooks.

## Step 1: Load Configuration

Check for configuration and context:

```bash
# Check for config and context files
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
[ -f ".claude/.pr-context.json" ] && echo "CONTEXT=true" || echo "CONTEXT=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
commits:
  format: "[{type}] {message} ({ticket})"
  types: [Feature, Fix, Hotfix, Refactor, Docs, Test, Chore]
  requireTicket: false
  ticketPattern: "^[A-Z]+-\\d+$"
attribution:
  enabled: false
  format: "Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Load from `.claude/.pr-context.json` (if exists):**

```json
{
  "ticket_id": "PROJ-1234",
  "type": "fix",
  "branch": "fix/proj-1234-description"
}
```

**Default Values (when no config):**

```yaml
commits:
  format: "[{type}] {message} ({ticket})"
  types: [Feature, Fix, Hotfix, Refactor, Docs, Test, Chore]
  requireTicket: false
attribution:
  enabled: false
```

## Step 2: Gather Context

If `.pr-context.json` doesn't exist or is incomplete, ask for missing information:

### Missing Ticket ID

If `commits.requireTicket: true` or no ticket found in context:

**Question**: "What is the ticket ID for this commit?"

- Example: `PROJ-1234`, `ENG-456`
- Allow skipping if `requireTicket: false`

### Missing Change Type

If type not found in context:

**Question**: "What type of change is this?"

**Options**: Feature, Fix, Hotfix, Refactor, Docs, Test, Chore

## Step 3: Show Changed Files

Display what will be staged:

```bash
# Show git status
git status --short

# Show detailed diff stats
git diff --stat
git diff --cached --stat
```

Present to user:

```
Changes to be committed:

Staged:
  M src/file1.ts
  A src/file2.ts

Unstaged:
  M src/file3.ts
  M tests/file1.test.ts

Do you want to stage all changes, or select specific files?
```

**Options:**

1. Stage all changes (default)
2. Stage only unstaged changes
3. Select specific files
4. Review diff before staging

If user wants to review diff:

```bash
git diff
```

## Step 4: Stage Files

Based on user's choice:

### Stage All

```bash
git add -A
```

### Stage Specific Files

```bash
git add {file1} {file2} ...
```

### Confirmation

```bash
# Show what's staged
git diff --cached --name-only
```

## Step 5: Generate Commit Message

### Ask for Summary

**Question**: "What is the summary of your changes?"

**Guidelines:**

- Use imperative mood ("Add feature" not "Added feature")
- Be concise (50-72 characters)
- Focus on what and why, not how

**Examples:**

- "Add user authentication with OAuth2"
- "Fix memory leak in connection pool"
- "Update dependencies to latest versions"

### Format Message

Apply commit format from config (default: `[{type}] {message} ({ticket})`):

| Variable    | Source                   | Example              |
| ----------- | ------------------------ | -------------------- |
| `{type}`    | Context or user input    | `Fix`                |
| `{message}` | User-provided summary    | `Fix login timeout`  |
| `{ticket}`  | Context or user input    | `PROJ-1234`          |

**Type Capitalization:**

- `fix` -> `Fix`
- `feature` -> `Feature`
- `hotfix` -> `Hotfix`

**Result Examples:**

- `[Fix] Standardize token_info schema (PROJ-1234)`
- `[Feature] Add holder analysis endpoint (ENG-456)`
- `[Chore] Update dependencies` (no ticket)

### Handle Missing Ticket

If no ticket and format includes `({ticket})`:

- If `requireTicket: true`: Prompt for ticket
- If `requireTicket: false`: Omit the `({ticket})` part

```
Without ticket: [Fix] Update dependencies
With ticket: [Fix] Update dependencies (PROJ-1234)
```

## Step 6: Commit Changes

### Create Commit

```bash
git commit -m "{formatted_commit_message}"
```

**Important:** Let pre-commit hooks run. Do NOT use `--no-verify`.

### Handle Pre-commit Failures

If commit fails due to pre-commit hooks:

1. **Identify the issue:**

   ```bash
   # Check hook output for errors
   # Common issues: linting, formatting, type errors
   ```

2. **Auto-fix if possible:**

   ```bash
   # For ESLint/Prettier
   npm run lint:fix 2>/dev/null || pnpm lint:fix 2>/dev/null || yarn lint:fix 2>/dev/null

   # For Python
   black . 2>/dev/null || ruff format . 2>/dev/null
   ```

3. **Re-stage fixed files:**

   ```bash
   git add -A
   ```

4. **Retry commit:**
   ```bash
   git commit -m "{formatted_commit_message}"
   ```

5. **If still failing:**
   - Show the error to the user
   - Ask if they want to fix manually or skip hooks (not recommended)

### Attribution (If Enabled)

If `attribution.enabled: true` in config:

```bash
git commit -m "{message}

{attribution.format}"
```

Example:

```
[Fix] Update token schema (PROJ-1234)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Note:** Attribution is disabled by default.

## Step 7: Update Context

Update `.claude/.pr-context.json`:

```json
{
  "ticket_id": "PROJ-1234",
  "ticket_url": "https://...",
  "branch": "fix/proj-1234-description",
  "type": "fix",
  "description": "Short description",
  "started_at": "2025-01-17T12:00:00Z",
  "commits": [
    {
      "hash": "abc123",
      "message": "[Fix] Summary (PROJ-1234)",
      "timestamp": "2025-01-17T12:30:00Z"
    }
  ],
  "last_commit_at": "2025-01-17T12:30:00Z"
}
```

## Step 8: Confirm

Output a confirmation message:

```
Staged: {N} files
Committed: {commit_hash_short}
Message: {commit_message}

Next step: Run /finish to create the pull request
```

If there were pre-commit fixes:

```
Pre-commit hooks auto-fixed some issues:
- Formatted 3 files with Prettier
- Fixed 2 ESLint warnings

Staged: 5 files
Committed: abc1234
Message: [Fix] Update token schema (PROJ-1234)
```

## Configuration Reference

| Setting              | Default                           | Description                    |
| -------------------- | --------------------------------- | ------------------------------ |
| `commits.format`     | `[{type}] {message} ({ticket})`   | Commit message format          |
| `commits.types`      | Feature, Fix, Hotfix...           | Allowed commit types           |
| `commits.requireTicket` | `false`                        | Require ticket ID              |
| `attribution.enabled` | `false`                          | Add AI co-author               |
| `attribution.format` | `Co-Authored-By: Claude <...>`    | Attribution line format        |

## Error Handling

| Scenario                  | Action                                           |
| ------------------------- | ------------------------------------------------ |
| No changes to commit      | Inform user, suggest checking `git status`       |
| Pre-commit hook fails     | Attempt auto-fix, show errors if still failing   |
| Ticket required but missing | Prompt for ticket ID                           |
| Invalid commit type       | Show allowed types, ask again                    |
| Context file missing      | Proceed with user input, create new context      |
| Git not in repo           | Error with clear message                         |

## Common Commit Formats

The command supports various commit format patterns:

### Conventional Commits

```yaml
commits:
  format: "{type}: {message}"
  # Result: fix: update token schema
```

### With Scope

```yaml
commits:
  format: "{type}({scope}): {message}"
  # Result: fix(api): update token schema
```

### Ticket Prefix

```yaml
commits:
  format: "{ticket}: {message}"
  # Result: PROJ-1234: Update token schema
```

### Custom Format

```yaml
commits:
  format: "[{ticket}] {type} - {message}"
  # Result: [PROJ-1234] Fix - Update token schema
```

## Examples

### Standard Flow

```
User: /commit
Agent: [Shows staged/unstaged files]
Agent: Stage all changes? -> Yes
Agent: What is the summary? -> "Fix login timeout issue"
Result: Committed abc1234
        Message: [Fix] Fix login timeout issue (PROJ-1234)
```

### With Auto-fix

```
User: /commit
Agent: [Stages files]
Agent: Summary? -> "Update API response"
[Pre-commit fails - ESLint errors]
Agent: Auto-fixing lint errors...
Agent: Fixed 3 files, retrying commit...
Result: Committed def5678
        Message: [Fix] Update API response (PROJ-1234)
```

### No Context File

```
User: /commit
Agent: No context found. What's the ticket ID? -> "ENG-789"
Agent: What type of change? -> "Feature"
Agent: Summary? -> "Add dark mode support"
Result: Committed ghi9012
        Message: [Feature] Add dark mode support (ENG-789)
```
