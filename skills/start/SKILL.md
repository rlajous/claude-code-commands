---
description: Start a new PR by creating a feature branch following repo conventions
argument-hint: "[ticket-id]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Write
---

You are helping create a new pull request. Your task is to create a properly named feature branch, optionally fetch ticket details, and store context for subsequent commands.

## Step 1: Load Configuration

Check for `.claude/config.yaml` to load project-specific settings:

```bash
# Check if config exists
if [ -f ".claude/config.yaml" ]; then
  echo "CONFIG_EXISTS=true"
else
  echo "CONFIG_EXISTS=false"
fi
```

**Configuration Priority:**

1. `.claude/config.yaml` (if exists)
2. Auto-detection (package.json, pyproject.toml, etc.)
3. Sensible defaults

**Default Values (when no config):**

```yaml
workflow:
  type: staging
  developmentBranch: staging
  productionBranch: main
branches:
  feature: "{type}/{ticket}-{description}"
commits:
  types: [Feature, Fix, Hotfix, Refactor, Docs, Test, Chore]
  requireTicket: false
  ticketPattern: "^[A-Z]+-\\d+$"
issueTracker:
  type: auto
```

## Step 2: Gather Information

Ask the user for the following information (use AskUserQuestion tool):

### Question 1: Ticket ID

**Question**: "What is the ticket ID or URL?"

- Examples:
  - `PROJ-1234` (Jira format)
  - `ENG-456` (Linear format)
  - `#789` (GitHub issue)
  - `https://linear.app/team/issue/ENG-456/...`
  - `https://your-org.atlassian.net/browse/PROJ-1234`

**Parsing Logic:**

- Extract ticket ID from URL if provided
- Linear: Pattern `/issue/([A-Z]+-\d+)/`
- Jira: Pattern `/browse/([A-Z]+-\d+)`
- GitHub: Pattern `issues/(\d+)` or `#(\d+)`

**Validation:**

- If `commits.requireTicket: true` in config, ticket is required
- Validate against `commits.ticketPattern` if provided
- If no ticket provided and not required, proceed without it

### Question 2: Change Type

**Question**: "What type of change is this?"

**Options** (from config or defaults):

- `feature` - New feature or enhancement
- `fix` - Bug fix
- `hotfix` - Urgent production fix
- `chore` - Maintenance, dependencies, etc.
- `refactor` - Code refactoring
- `docs` - Documentation changes

### Question 3: Short Description

**Question**: "Provide a brief description (will be converted to kebab-case)"

**Examples:**

- "add user authentication" -> `add-user-authentication`
- "fix memory leak in parser" -> `fix-memory-leak-in-parser`

## Step 3: Fetch Ticket Details (Optional)

If a ticket ID was provided and issue tracker is configured:

### Auto-Detect Issue Tracker Type

Based on ticket format and available MCP servers:

- `^[A-Z]+-\d+$` with Linear MCP available -> Linear
- `^[A-Z]+-\d+$` with Jira config/MCP available -> Jira
- `^#?\d+$` or GitHub URL -> GitHub Issues (via `gh` CLI)

### Linear Integration

If Linear ticket format is detected, use the Linear MCP server:

```
# Fetch ticket details via Linear MCP
mcp__linear__get_issue(id: ticketId)
```

The MCP server handles authentication automatically via OAuth.

### Jira Integration

If Jira is configured, use the Jira MCP server:

```
# Fetch ticket details via Jira MCP
mcp__jira__get_issue(issueKey: ticketId)
```

The MCP server handles authentication automatically. The `jira.baseUrl` from config is used to identify the Jira instance.

### GitHub Issues

If GitHub format detected:

```bash
# Use gh CLI to fetch issue
gh issue view {issue_number} --json title,body,state
```

**Store Fetched Data:**

```json
{
  "ticket_title": "Fetched title from issue tracker",
  "ticket_description": "Description from issue tracker",
  "ticket_status": "In Progress"
}
```

## Step 4: Create Branch

### Generate Branch Name

Apply the branch pattern from config (default: `{type}/{ticket}-{description}`):

```
Pattern: {type}/{ticket}-{description}
Type: fix
Ticket: proj-1234
Description: add-user-auth

Result: fix/proj-1234-add-user-auth
```

**Branch Naming Rules:**

- Convert ticket to lowercase
- Convert description to kebab-case (lowercase, hyphens)
- Remove special characters
- Limit total length to 100 characters

**Examples:**

- `fix/proj-1234-standardize-token-info-schema`
- `feature/eng-456-add-holder-analysis`
- `hotfix/abc-789-fix-critical-bug`
- `chore/update-dependencies` (no ticket)

### Create and Checkout Branch

```bash
# Ensure we're on the development branch and up-to-date
git checkout {workflow.developmentBranch} 2>/dev/null || git checkout main
git pull

# Create feature branch
git checkout -b {branch_name}
```

**Error Handling:**

- If branch already exists, ask: "Branch exists. Switch to it or create a new name?"
- If not on expected base branch, warn and confirm

## Step 5: Store Context

Create `.claude/.pr-context.json` with collected information:

```json
{
  "ticket_id": "PROJ-1234",
  "ticket_url": "https://issue-tracker.com/PROJ-1234",
  "ticket_title": "Title from issue tracker (if fetched)",
  "branch": "fix/proj-1234-description",
  "type": "fix",
  "description": "Human readable description",
  "started_at": "2025-01-17T12:00:00Z",
  "config": {
    "workflow": "staging",
    "developmentBranch": "staging",
    "productionBranch": "main"
  }
}
```

**Important:**

- Create `.claude/` directory if it doesn't exist
- If `.pr-context.json` exists, ask before overwriting

## Step 6: Confirm

Output a confirmation message:

```
Created branch: {branch_name}
Ticket: {ticket_id} {ticket_title if fetched}
Type: {type}

Next steps:
1. Make your code changes
2. Run /commit to stage and commit your changes
3. Run /finish to create the pull request
```

If ticket details were fetched, include:

```
Ticket Details:
- Title: {ticket_title}
- Status: {ticket_status}
```

## Configuration Reference

All configurable options from `.claude/config.yaml`:

| Setting                     | Default                          | Description                       |
| --------------------------- | -------------------------------- | --------------------------------- |
| `workflow.developmentBranch` | `staging`                        | Base branch for feature branches  |
| `branches.feature`          | `{type}/{ticket}-{description}` | Branch naming pattern             |
| `commits.types`             | Feature, Fix, Hotfix...          | Allowed change types              |
| `commits.requireTicket`     | `false`                          | Enforce ticket ID                 |
| `commits.ticketPattern`     | `^[A-Z]+-\d+$`                   | Regex for ticket validation       |
| `issueTracker.type`         | `auto`                           | linear, jira, github, none        |

## Error Handling

| Scenario                    | Action                                          |
| --------------------------- | ----------------------------------------------- |
| Branch already exists       | Ask to switch or rename                         |
| Ticket required but missing | Prompt for ticket ID                            |
| Invalid ticket format       | Show expected format, ask to retry              |
| Issue tracker API fails     | Warn and continue without ticket details        |
| Not on expected branch      | Warn and ask for confirmation                   |
| Uncommitted changes         | Warn and ask to stash or commit first           |
| `.pr-context.json` exists   | Ask to overwrite or abort                       |

## Examples

### Basic Usage (No Config)

```
User: /start
Agent: What is the ticket ID? -> "PROJ-123"
Agent: What type of change? -> "fix"
Agent: Brief description? -> "fix login timeout"
Result: Branch fix/proj-123-fix-login-timeout created
```

### With Linear Integration (via MCP)

```
User: /start
Agent: What is the ticket ID? -> "ENG-456"
[Uses Linear MCP to fetch: "Add OAuth2 support"]
Agent: What type? -> "feature"
Agent: Description? -> "oauth2-authentication"
Result: Branch feature/eng-456-oauth2-authentication created
        Ticket: ENG-456 - Add OAuth2 support
```

### Without Ticket (When Not Required)

```
User: /start
Agent: What is the ticket ID? -> (skip)
Agent: What type? -> "chore"
Agent: Description? -> "update dependencies"
Result: Branch chore/update-dependencies created
```
