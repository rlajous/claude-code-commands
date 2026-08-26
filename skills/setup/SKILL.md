---
name: setup
description: Configure Git Workflow for Claude Code or Codex, migrate legacy configuration, install Codex project agents, and optionally configure issue-tracker MCP servers. Use when the user asks to set up, install, configure, or migrate Git Workflow.
argument-hint: "[--host <claude|codex|both>] [--dry-run] [--force]"
disable-model-invocation: false
allowed-tools: Read, Write, Bash(mkdir:*), Bash(cp:*), Bash(diff:*), Bash(git rev-parse:*), AskUserQuestion, Glob
user-invocable: true
---

# Set up Git Workflow

Follow [runtime compatibility](../../references/runtime-compatibility.md). Claude Code users invoke this as `/setup`; Codex users invoke it as `$setup`.

## 1. Resolve roots and runtime

Parse these options before resolving paths:

- `--host <claude|codex|both>` selects exactly which project assets to synchronize. When omitted, detect the active host and ask only if the target remains ambiguous.
- `--dry-run` previews migration and installation without creating directories, files, or ledgers.
- `--force` is explicit approval to replace customized selected-host files, but differences must still be shown first.
- Reject unknown options and missing option values without writing.

Resolve `{SKILL_DIR}` to the absolute, physical directory containing this loaded `SKILL.md`.
Codex includes that path in its skill metadata; Claude Code can resolve the loaded skill path too.
Only when the host does not expose the path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, to locate
`skills/setup/SKILL.md` and verify that it exists. Never substitute an empty variable or silently
fall back to `/scripts`.

Derive `{PACKAGE_ROOT}` as the physical `{SKILL_DIR}/../..` directory and require
`{PACKAGE_ROOT}/.codex-plugin/plugin.json`. Resolve the project root with
`git rev-parse --show-toplevel`, falling back to the current directory.

Detect the active host from available environment and configuration. If both Claude and Codex appear active and the requested target is unclear, ask which host or hosts to configure.

Never edit a user-global configuration unless the user explicitly selects global scope.

## 2. Migrate workflow configuration

Canonical configuration is `<project>/.git-workflow/config.yaml`.

- If only `.claude/config.yaml` exists, explain that it is the legacy location and offer to copy it to the canonical path.
- Create `.git-workflow/` before copying.
- Never delete or modify the legacy file automatically.
- If both files exist, use the canonical file. Show a diff when they differ and do not merge or overwrite without an explicit user decision.
- If neither exists, ask only for values that differ from the documented defaults, then write the canonical file from `templates/config.yaml.template`.

Default commit attribution is disabled. Preserve an existing explicit `attribution.enabled` or `attribution.format` value during migration.

## 3. Install Codex project agents

For Codex, copy every source `<plugin>/.codex/agents/*.toml` to `<project>/.codex/agents/`.

Use the package synchronizer so classification, atomic replacement, and ledger behavior stay consistent:

```bash
node "{SKILL_DIR}/scripts/sync-project.mjs" --source "{PACKAGE_ROOT}" --target <project> --host codex --migrate-config --initialize-config --dry-run
```

After showing the result and receiving confirmation for customized files, rerun without `--dry-run` and add `--force` only for replacements the user approved. When the skill itself was invoked with `--dry-run`, do not perform the second run.

For each agent:

- Missing target: list it as `+` and install it.
- Identical target: list it as `=` and leave it unchanged.
- Different target: list it as `~`, show a unified diff, and ask before overwriting.

Create `.codex/agents/` when needed. Do not set a model, reasoning effort, concurrency limit, or permission mode; installed agents inherit the parent Codex session. The plugin-bundled Codex hook is discovered separately from `hooks/hooks.json` and requires the host's normal hook trust review.

Claude Code loads the existing plugin agents directly. For a manual Claude installation, synchronize `skills/`, `agents/*.md`, and the shared `references/` directory into `.claude/skills/`, `.claude/agents/`, and `.claude/references/` with the same missing/identical/different rules. Use `--host claude` (or `both`) with the synchronizer.

## 4. Configure issue-tracker MCP (optional)

Ask which integrations are needed: none, Linear, Jira, GitHub Issues, or more than one.

- Codex: update the selected project `.codex/config.toml` or explicit user `~/.codex/config.toml` MCP tables without replacing unrelated settings.
- Claude Code: update the selected `.claude/settings.json` or explicit user `~/.claude/settings.json` MCP configuration without replacing unrelated settings.
- GitHub Issues can use the authenticated `gh` CLI and does not require an MCP server.

Never print or persist access tokens in workflow configuration. If a server needs credentials, reference environment variables and tell the user which variables must be set.

## 5. Record installation

The synchronizer writes `.git-workflow/version.json` with:

```json
{
  "version": "2.5.2",
  "source": "<resolved-plugin-source>",
  "installed_at": "<ISO-8601 timestamp>",
  "hosts": ["codex"],
  "managed_files": [".codex/agents/pr-reviewer.toml"]
}
```

Report created, migrated, skipped, and user-preserved files separately. End with host-specific invocation examples, including `/status` for Claude Code and `$status` for Codex.

## Failure handling

- Missing plugin source: stop before writing and report how source resolution failed.
- Invalid existing YAML, JSON, or TOML: report the file and parse error; do not replace it.
- Permission failure: report the exact target and leave existing files unchanged.
- Partial agent installation: report every completed and failed file so `$update` or `/update` can resume safely.
