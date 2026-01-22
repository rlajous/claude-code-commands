---
description: Stage and commit changes with proper formatting following repo conventions
---

You are helping commit changes for a pull request. Your task is to stage all changes and create a properly formatted commit message.

## Step 1: Check for Context

Load the context from `.claude/.pr-context.json` if it exists.

If the file doesn't exist:

- Ask the user for the ticket ID (e.g., "PROJ-1234")
- Ask the user for the change type (fix, feature, hotfix, epic)
- Store this information for later use

## Step 2: Show Changed Files

Run the following command to show what will be staged:

```bash
git status
git diff --name-only
```

Display the list of modified files to the user and ask for confirmation:

```
The following files will be staged:
- src/file1.ts
- src/file2.ts
- src/file3.ts

Do you want to proceed with staging these files?
```

## Step 3: Ask for Commit Message

Ask the user for a commit message summary (use AskUserQuestion tool):

- Question: "What is the summary of your changes?"
- Example: "Standardize token_info schema across all chains"

## Step 4: Format Commit Message

Format the commit message following the repo convention:

```
[{Type}] {Summary} ({TICKET_ID})
```

Examples:

- `[Fix] Standardize token_info schema across all chains (PROJ-1234)`
- `[Feature] Add holder analysis endpoint (PROJ-1000)`
- `[Hotfix] Fix critical memory leak (PROJ-2000)`

Type capitalization:

- fix → Fix
- feature → Feature
- hotfix → Hotfix
- epic → Epic

## Step 5: Stage and Commit

Run the following commands:

```bash
git add {list of modified files}
git commit -m "{formatted commit message}"
```

**Important**: Let the pre-commit hooks run. If they fail with linting errors:

1. Show the user the errors
2. Fix the lint errors automatically if possible
3. Re-stage the files
4. Retry the commit

## Step 6: Update Context

Update `.claude/.pr-context.json` with the commit information:

```json
{
  "ticket_id": "PROJ-XXXX",
  "ticket_url": "https://your-issue-tracker.com/issue/PROJ-XXXX",
  "branch": "fix/proj-xxxx-description",
  "type": "fix",
  "description": "Short description",
  "started_at": "2025-01-17T12:00:00Z",
  "commit_message": "[Fix] Summary (PROJ-XXXX)",
  "commit_summary": "Summary text",
  "committed_at": "2025-01-17T12:30:00Z"
}
```

## Step 7: Confirm

Output a confirmation message:

```
✅ Staged {N} files
✅ Committed with message: {commit_message}

Next step:
Run `/finish` to create the pull request
```

## Important Notes

- Always show the user what files will be staged before committing
- Let pre-commit hooks run - do NOT use `--no-verify`
- If lint errors occur, fix them automatically and retry
- The commit message MUST follow the format: `[Type] Summary (PROJ-XXXX)`
- Do NOT use co-authored-by in the commit message
- If there are no changes to commit, inform the user
