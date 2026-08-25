---
name: update
description: Update Git Workflow skills and Claude/Codex project agents from a source checkout or installed plugin, with dry-run, pruning, customization detection, and legacy migration support. Use when the user asks to update, refresh, or synchronize Git Workflow.
argument-hint: "[--dry-run] [--prune] [--force] [--source <path>]"
disable-model-invocation: false
allowed-tools: Read, Bash, Write, Glob, Grep, AskUserQuestion
user-invocable: true
---

# Update Git Workflow

Follow [runtime compatibility](../../references/runtime-compatibility.md). Claude Code users invoke this as `/update`; Codex users invoke it as `$update`.

## 1. Parse options

- `--dry-run`: calculate and display changes without writing.
- `--prune`: include previously managed files that no longer exist in the source as removal candidates.
- `--force`: overwrite customized managed files after still showing their diffs.
- `--source <path>`: use an explicit Git Workflow checkout or plugin directory.

Unknown options are errors. Destructive pruning is never implied by `--force` alone.

## 2. Resolve project and source

Resolve the project root from Git, then accept either `.git-workflow/`, `.claude/`, or `.codex/` as evidence of an existing installation. Resolve the source in this order:

1. `--source`
2. `PLUGIN_ROOT`
3. `CLAUDE_PLUGIN_ROOT`
4. `source` recorded in `.git-workflow/version.json`

Validate that the source contains `skills/`, `agents/`, and `.codex/agents/`. Stop without writing if it is incomplete.

## 3. Build the synchronization set

Use `scripts/sync-project.mjs` from the resolved source to calculate and apply this set. Always run it first with `--dry-run`; after the user reviews changes, rerun without `--dry-run`. Add `--force` only when changed files were approved, and add `--confirm-prune` only after separate confirmation of listed prune candidates.

```bash
node <source>/scripts/sync-project.mjs --source <source> --target <project> --host <codex|claude|both> --dry-run
```

Synchronize only components relevant to the installation:

| Source | Target | When |
|---|---|---|
| `skills/*/` | `.claude/skills/*/` | Manual Claude installation |
| `agents/*.md` | `.claude/agents/*.md` | Manual Claude installation |
| `references/*.md` | `.claude/references/*.md` | Manual Claude installation |
| `.codex/agents/*.toml` | `.codex/agents/*.toml` | Codex project agents |

Codex plugin skills are updated by the plugin manager and must not be copied into `.codex/skills/` by this workflow.

For every target, classify it as missing (`+`), changed (`~`), identical (`=`), or orphaned (`?`). Show a unified diff for changed text files.

## 4. Protect customizations

- Without `--force`, ask once before overwriting the listed changed files. A rejection preserves all changed files while still allowing missing files to install.
- With `--force`, overwrite changed managed files only after showing the summary.
- `--prune` may remove only paths recorded as managed in the version ledger. Never remove an untracked local skill or agent merely because the source lacks the same name.
- Show prune candidates and require explicit confirmation even with `--force`.
- `--dry-run` performs no writes, removals, directory creation, or ledger updates.

Use atomic per-file replacement where practical. A failure must not truncate the previous target.

## 5. Migrate and record state

If `.git-workflow/config.yaml` is absent and `.claude/config.yaml` exists, offer the same non-destructive copy used by `$setup`; do not make migration a prerequisite for updating agents.

After a successful non-dry-run update, the synchronizer rewrites `.git-workflow/version.json` with version `2.4.0`, the resolved source, timestamp, hosts, and the exact relative paths managed by this run. Preserve the user's workflow configuration, local hook opt-in, PR context, status report, and reviewed-SHA ledger.

## Output

Report installed, updated, unchanged, preserved, pruned, and failed files separately. If any item fails, return a non-success summary with the exact recovery command. Otherwise suggest `/status` for Claude Code or `$status` for Codex.
