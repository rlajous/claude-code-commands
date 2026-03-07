---
description: Create a new RFC document from template with auto-numbering
argument-hint: "<title>"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, AskUserQuestion
---

You are helping create a new RFC (Request for Comments) document. Your task is to generate a properly numbered RFC file from the template with pre-filled metadata.

## Step 1: Parse Arguments

Extract the RFC title from `$ARGUMENTS`.

- If `$ARGUMENTS` is empty or not provided, use AskUserQuestion to prompt: "What is the title for this RFC? (e.g., 'add deploy command', 'config schema v2')"
- Validate the title contains only alphanumeric characters, spaces, and hyphens
- If invalid characters are found, strip them and confirm with the user

## Step 2: Auto-Determine RFC Number

Scan for existing RFC files to determine the next number:

```bash
# Find existing RFCs and determine next number
latest=$(ls docs/rfcs/rfc-*.md 2>/dev/null | sort -V | tail -1)
if [ -n "$latest" ]; then
  current=$(basename "$latest" | sed 's/rfc-\([0-9]*\)-.*/\1/')
  next=$((10#$current + 1))
else
  next=1
fi
printf -v rfc_num "%03d" $next
```

**Logic:**

- If no existing RFCs found, start at `001`
- If existing RFCs found, extract the highest NNN from `rfc-NNN-*.md` and increment by 1
- Zero-pad to 3 digits (001, 002, ..., 999)

## Step 3: Generate Filename

Convert the title to a kebab-case filename:

- Convert to lowercase
- Replace spaces with hyphens
- Remove special characters (keep alphanumeric and hyphens)
- Collapse multiple hyphens into one
- Trim leading/trailing hyphens

```bash
kebab_title=$(echo "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9 -]//g' \
  | tr ' ' '-' \
  | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')
```

**Result:** `rfc-${rfc_num}-${kebab_title}.md`

**Examples:**

- "Add Deploy Command" -> `rfc-001-add-deploy-command.md`
- "Config Schema v2" -> `rfc-002-config-schema-v2.md`

## Step 4: Create Directory

```bash
mkdir -p docs/rfcs
```

## Step 5: Copy and Customize Template

Read the template from `docs/rfcs/RFC_TEMPLATE.md` and replace placeholders:

| Placeholder | Replacement |
| ----------- | ----------- |
| `RFC-NNN` | `RFC-{number}` (e.g., `RFC-001`) |
| `[Title]` | The user-provided title |
| `[Month Year]` | Current month and year (e.g., `March 2026`) |
| `[Your name or team name]` | Result of `$AUTHOR` (see below) |

Resolve the author name with a fallback:

```bash
AUTHOR="$(git config user.name 2>/dev/null)"
if [ -z "$AUTHOR" ]; then
  # Use AskUserQuestion to prompt: "Could not detect git user name. What name should be used as the RFC author?"
fi
```

Write the customized content to `docs/rfcs/rfc-{NNN}-{kebab-title}.md`.

## Step 6: Confirm

Output a confirmation message:

```text
Created RFC: docs/rfcs/rfc-{NNN}-{kebab-title}.md
Author: {git user name}
Date: {month year}

Next steps:
1. Edit the RFC to fill in the sections
2. Create a PR with the RFC for review
3. Request review from maintainers
4. See docs/rfcs/RFC_BEST_PRACTICES.md for guidelines
```

## Error Handling

| Scenario | Action |
| -------- | ------ |
| No title provided | Prompt with AskUserQuestion |
| Template file missing | Error: "RFC template not found at docs/rfcs/RFC_TEMPLATE.md. Please ensure the template exists." |
| File already exists | Ask: "RFC file already exists. Overwrite or choose a different title?" |
| Invalid characters in title | Strip invalid characters and confirm with user |
