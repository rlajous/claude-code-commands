---
description: Start a new PR by creating a feature branch following repo conventions
---

You are helping create a new pull request. Your task is to create a properly named feature branch and store context for the next commands.

## Step 1: Gather Information

Ask the user for the following information (use AskUserQuestion tool):

1. **Ticket**: Ask for the ticket ID or URL

   - Examples: "PROJ-1234" or "https://your-issue-tracker.com/issue/PROJ-1234/..."
   - If URL provided, extract the ticket number (e.g., "PROJ-1234")

2. **Type**: Ask what type of change this is

   - Options: fix, feature, hotfix, epic
   - Default: fix

3. **Short Description**: Ask for a brief description (will be converted to kebab-case)
   - Example: "standardize token info schema"
   - Will become: "standardize-token-info-schema"

## Step 2: Create Branch

Format the branch name as: `{type}/{ticket_id}-{description}`

Examples:

- `fix/proj-1234-standardize-token-info-schema`
- `feature/proj-1000-add-holder-analysis`
- `hotfix/proj-2000-fix-critical-bug`

Run the following commands:

```bash
git checkout -b {branch_name}
```

## Step 3: Store Context

Create a file `.claude/.pr-context.json` with the following structure:

```json
{
  "ticket_id": "PROJ-XXXX",
  "ticket_url": "https://your-issue-tracker.com/issue/PROJ-XXXX",
  "branch": "fix/proj-xxxx-description",
  "type": "fix",
  "description": "Short description",
  "started_at": "2025-01-17T12:00:00Z"
}
```

## Step 4: Confirm

Output a confirmation message:

```
✅ Created branch: {branch_name}
✅ Linear ticket: {ticket_id}

Next steps:
1. Make your code changes
2. Run `/commit` to stage and commit your changes
3. Run `/finish` to create the pull request
```

## Important Notes

- If the branch already exists, ask the user if they want to switch to it or create a new one with a different name
- If `.claude/.pr-context.json` already exists, ask the user if they want to overwrite it
- Always use `git checkout -b` to create AND switch to the new branch
- Ensure the branch name follows the convention: `{type}/{ticket-id}-{kebab-case-description}`
