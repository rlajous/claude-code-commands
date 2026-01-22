---
description: Create a pull request with comprehensive description following repo best practices
---

You are helping create a pull request with a comprehensive description. Your task is to gather information, generate the PR description, push the branch, and create the PR.

## Step 1: Load Context

Load the context from `.claude/.pr-context.json`.

If the file doesn't exist or is incomplete:

- Ask the user for missing information (ticket ID, branch name, commit message)
- Inform them they should run `/start` and `/commit` first for the best experience

## Step 2: Gather Changed Files

Run the following commands to understand what changed:

```bash
git diff --name-only staging...HEAD
git diff --stat staging...HEAD
```

Show the user the list of changed files.

## Step 3: Gather PR Information

Ask the user for the following information (use AskUserQuestion tool with multiple questions):

### Question 1: Issues Fixed

**Question**: "What issues did this PR fix? List each problem and its solution."
**Format**: Provide as a numbered list
**Example**:

```
1. Missing token_info for some tokens → Always returns object
2. Inconsistent field names → Standardized to name, symbol, logo
3. Loose typing → Strong typing with ConsolidatedTokenMetadata
```

### Question 2: Why (Root Cause)

**Question**: "Explain the root cause of the problem and why this fix was necessary."
**Example**:

```
Some chains could return undefined instead of empty object. Type was any instead of proper ConsolidatedTokenMetadata.
```

### Question 3: Test Tokens/Addresses

**Question**: "What tokens or addresses can be used to test this fix? Include chain and expected behavior."
**Format**: Table with Token/Address, Chain, Expected Result
**Example**:

```
| Token | Chain | Address | Expected |
|-------|-------|---------|----------|
| KRI | eth | 0xb3c22eb9... | 1 LP entry |
| PEPE | eth | 0x69825081... | Multiple DEXes |
```

### Question 4: Breaking Changes

**Question**: "Are there any breaking changes? If yes, describe them."
**Options**: "Yes" / "No"
**Follow-up if Yes**: "Describe the breaking changes"

## Step 4: Generate PR Description

Use this standardized template:

````markdown
## Description

Fixes {ticket_id}

{High-level overview from commit message and context}

### Issues Fixed

1. ❌ **{Problem}** → ✅ {Solution}

### Why

**Root Cause**: {Explain the root cause}

**Fix**: {Explain what was changed to fix it}

### What Changed

| File          | Change                        |
| ------------- | ----------------------------- |
| `{file_path}` | {Brief description of change} |

---

## Testing

### Run Tests

```bash
npm run test -- {relevant test files}
```

### Local API Testing

```bash
# Start services
docker-compose up -d
npm run start:dev

# Test endpoint
curl -H "x-api-key: xxx" \
  "http://localhost:3000/api/v1/{endpoint}" \
  | jq '{relevant_field}'
```

### Expected Result

**Before (bug):** {Describe broken behavior}
**After (fixed):** {Describe correct behavior}

```json
{
  // Expected response
}
```

### Test Tokens

| Token  | Chain   | Address     |
| ------ | ------- | ----------- |
| {name} | {chain} | `{address}` |

---

## Checklist

- [x] Tests pass locally
- [x] Local API testing verified
- [x] No breaking changes
````

## Step 5: Push Branch

Run the following command:

```bash
git push -u origin {branch_name}
```

If the branch is already pushed and has changes, inform the user and ask if they want to force push or just update.

## Step 6: Create PR

Format the PR title as: `[{Type}] {Summary} ({TICKET_ID})`

Examples:

- `[Fix] Standardize token_info schema across all chains (PROJ-1234)`
- `[Feature] Add holder analysis endpoint (PROJ-1000)`

Run the following command:

```bash
gh pr create --base staging --title "{PR_TITLE}" --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)" --reviewer your-org/engineers  # Change to your reviewer team
```

After creating the PR, assign it to the current user:

```bash
gh pr edit {PR_NUMBER} --add-assignee @me
```

## Step 7: Confirm and Cleanup

Output a confirmation message:

```
✅ Branch pushed: {branch_name}
✅ PR created: {PR_URL}
✅ Title: {PR_TITLE}
✅ Assigned to: @me
✅ Reviewers: @your-org/engineers

PR #{number} is ready for review!
```

Optionally clean up the context file:

```bash
rm .claude/.pr-context.json
```

## Important Notes

- Always use `--base staging` for the PR (not main)
- The PR title MUST match the commit message format: `[Type] Summary (PROJ-XXXX)`
- Always include the **Testing** section with:
  - Test commands to run
  - Local API testing curl commands (use `x-api-key: xxx` for local or configure your local API key)
  - Expected results with JSON examples
  - Test tokens/addresses table
- Keep the PR description concise - use tables for file changes
- Show the PR URL to the user after creation
- If `gh` command fails, provide instructions for manual PR creation

## Error Handling

- If `gh` is not installed, instruct user to install it or create PR manually
- If branch is not pushed, push it first
- If user is not authenticated with GitHub, provide instructions
- If PR creation fails, show the full error message and suggest fixes
