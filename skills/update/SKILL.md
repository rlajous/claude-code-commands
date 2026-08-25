---
name: update
description: Update skills and agents from the source repository
argument-hint: "[--dry-run] [--prune] [--force] [--source <path>]"
disable-model-invocation: true
allowed-tools: Read, Bash, Write, Glob, Grep, AskUserQuestion
user-invocable: true
---

You are helping the user update their installed skills and agents from the source repository. Parse arguments from `$ARGUMENTS` and follow each step in order.

## Step 1: Parse Arguments

Extract flags from `$ARGUMENTS`:

- `--dry-run` → preview changes only, do not modify files
- `--prune` → remove orphaned files not present in source
- `--force` → update even if already at latest version
- `--source <path|url>` → custom source (local path or git URL)

**Defaults:**

```bash
DRY_RUN=false
PRUNE=false
FORCE=false
SOURCE="https://github.com/rlajous/claude-code-commands.git"
```

## Step 2: Detect Project Root

Find the project root by locating the `.claude/` directory:

```bash
# Walk up from current directory to find .claude/
DIR="$(pwd)"
while [ "$DIR" != "/" ]; do
  if [ -d "$DIR/.claude" ]; then
    echo "PROJECT_ROOT=$DIR"
    break
  fi
  DIR="$(dirname "$DIR")"
done
```

If `.claude/` is not found, stop and tell the user:

```text
Could not find .claude/ directory. Run this command from within your project.
```

## Step 3: Resolve Source

**If `--source` is a local directory path:**

```bash
if [ ! -d "$SOURCE" ]; then
  # stop with error: "Source directory not found: $SOURCE"
fi
SOURCE_DIR="$(cd "$SOURCE" && pwd)"
SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || date +%s)"
```

**Otherwise, clone from remote:**

```bash
TEMP_DIR="$(mktemp -d)"
git clone --depth 1 "$SOURCE" "$TEMP_DIR"
SOURCE_DIR="$TEMP_DIR"
SOURCE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
```

If clone fails, stop and report the error.

## Step 4: Version Check

Read `$PROJECT_ROOT/.claude/.tooling-version` (if it exists) and compare the stored `commit` value against `$SOURCE_COMMIT`.

- If commits match and `--force` is NOT set: print "Already up to date (commit {short_hash}). Use --force to update anyway." and stop.
- If commits differ or `--force` is set: continue.
- If `.tooling-version` does not exist: continue (first update).

## Step 5: Discover Managed Files

Find all managed files in the source repository. Skills are directories, each containing a `SKILL.md` (plus optional `references/`, `scripts/`, `examples/`, `assets/`):

| Source path | Target path |
|-------------|-------------|
| `skills/*/` (each skill directory, including `SKILL.md` and any bundled files) | `.claude/skills/*/` |
| `agents/*.md` | `.claude/agents/*.md` |

> **Migrating from the legacy layout:** older installs stored slash commands as `.claude/commands/*.md`. This source now ships them as `.claude/skills/<name>/SKILL.md`. Treat any matching `.claude/commands/*.md` as superseded — with `--prune`, list them as orphans to remove after the equivalent skill is installed.

Also check for these individual files:

| Source path | Target path |
|-------------|-------------|
| `docs/rfcs/RFC_TEMPLATE.md` | `docs/rfcs/RFC_TEMPLATE.md` |
| `docs/rfcs/RFC_BEST_PRACTICES.md` | `docs/rfcs/RFC_BEST_PRACTICES.md` |

## Step 6: Compare Files

For each discovered source file, compare it against the corresponding target file in the project:

- **Added** (`+`): target file does not exist
- **Updated** (`~`): target file exists but content differs (use `cmp -s` or `diff -q`)
- **Unchanged** (`=`): target file exists and content is identical

## Step 7: Detect Orphans

Find skill directories in `.claude/skills/` and `*.md` files in `.claude/agents/` that do NOT have a corresponding entry in the source. Mark these as orphans (`?`). Also treat legacy `.claude/commands/*.md` files as orphans when a same-named skill now exists in the source.

## Step 8: Print Summary

Display the comparison results with status indicators:

```text
Summary

  + .claude/skills/new-skill/SKILL.md
  ~ .claude/skills/commit/SKILL.md
  = .claude/skills/start/SKILL.md
  ? .claude/commands/commit.md  (legacy command superseded by skill)

  + 1 added  ~ 1 updated  = 8 unchanged  ? 1 orphaned
```

## Step 9: Dry Run Check

If `--dry-run` is set, print "Dry run - no files were modified." and stop here (after cleaning up any temp directory).

## Step 10: Apply Changes

If there are no added or updated files (and no orphans to prune), print "All files are up to date." and skip to Step 12.

Otherwise, for each **added** and **updated** file:

1. Create the target directory if it doesn't exist (`mkdir -p`)
2. Copy the source file to the target path

Print: "Copied {N} file(s)."

## Step 11: Handle Orphans

If orphaned files were detected:

- If `--prune` is set: list the files that will be removed and delete them. Print confirmation for each.
- If `--prune` is NOT set: print a warning: "{N} orphaned file(s) found. Use --prune to remove them."

## Step 12: Write Version File

Write `$PROJECT_ROOT/.claude/.tooling-version` with:

```json
{
  "source": "{SOURCE}",
  "commit": "{SOURCE_COMMIT}",
  "updatedAt": "{ISO_8601_TIMESTAMP}"
}
```

## Step 13: Clean Up

If a temp directory was created (remote clone), remove it:

```bash
rm -rf "$TEMP_DIR"
```

Print: "Update complete."

## File Ownership Boundary

**Files this command manages (will create/update/delete):**

- skill directories in `.claude/skills/` (each `SKILL.md` and any bundled `references/`, `scripts/`, `examples/`, `assets/`)
- `*.md` files in `.claude/agents/`
- legacy `*.md` files in `.claude/commands/` (only removed with `--prune`, when superseded by a skill)
- `docs/rfcs/RFC_TEMPLATE.md`
- `docs/rfcs/RFC_BEST_PRACTICES.md`
- `.claude/.tooling-version`

**Files this command NEVER touches:**

- `.claude/config.yaml`
- `.claude/settings.json`
- `CLAUDE.md`
- `.claude/.pr-context.json`
- `docs/rfcs/rfc-*.md` (user-created RFCs)

## Error Handling

| Scenario | Action |
|----------|--------|
| `.claude/` not found | Stop with instructions to run from project root |
| Git clone fails | Stop with error message |
| Source directory missing expected files | Warn but continue with available files |
| File copy fails | Report error, continue with remaining files |
| No changes needed | Report "up to date" and write version file |
