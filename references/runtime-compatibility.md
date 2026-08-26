# Runtime compatibility

Use these rules in every Git Workflow skill.

## Invocation and interaction

- Claude Code users invoke a skill as `/skill-name`; Codex users invoke it as `$skill-name`. Plain-language requests work when the skill description matches.
- Ask the user through the active host's user-input mechanism. Do not depend on a tool being named `AskUserQuestion`.
- Delegate through the active host's subagent mechanism. In Codex, use the named project agents installed under `.codex/agents/`; in Claude Code, use the plugin agents under `agents/`.
- Resolve `{SKILL_DIR}` from the absolute path of the loaded `SKILL.md`; Codex includes that path
  in its skill metadata. Resolve scripts, references, and assets relative to `{SKILL_DIR}`.
- Derive `{PACKAGE_ROOT}` as the physical `{SKILL_DIR}/../..` path only for package-wide files, and
  verify `.codex-plugin/plugin.json` before using it.
- If a host cannot expose the loaded skill path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, only
  as compatibility fallbacks to locate and verify the expected `skills/<name>/SKILL.md`.
- Stop with the unresolved or missing path when validation fails. Never turn an empty variable
  into `/scripts/...`, and never silently fall back from a skill-local helper to a root wrapper.

## Configuration and state

Resolve workflow configuration in this order:

1. `.git-workflow/config.yaml`
2. `.claude/config.yaml` (legacy read-only fallback)

Resolve pull-request context in this order:

1. `.git-workflow/pr-context.json`
2. `.claude/.pr-context.json` (legacy read-only fallback)

Write all new workflow-owned files under `.git-workflow/`:

- `config.yaml`
- `pr-context.json`
- `status.html`
- `git-workflow.local.md`
- `version.json`
- `.git-workflow-reviewed-shas`

Create the directory when needed. Never delete a legacy `.claude/` file during automatic migration. If both canonical and legacy files exist, the canonical file wins.

## Permissions

Claude-specific `allowed-tools` frontmatter remains for Claude Code. In Codex, respect the parent session's permissions and approval mode. Ask before destructive actions, external writes not already authorized by the invoked workflow, or overwriting customized configuration.
