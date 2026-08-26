# Runtime compatibility

Use these rules in every Git Workflow skill.

## Invocation and interaction

- Claude Code users invoke a skill as `/skill-name`; Codex users invoke it as `$skill-name`. Plain-language requests work when the skill description matches.
- Ask the user through the active host's user-input mechanism. Do not depend on a tool being named `AskUserQuestion`.
- Delegate through the active host's subagent mechanism. In Codex, use the named project agents installed under `.codex/agents/`; in Claude Code, use the plugin agents under `agents/`.
- Resolve the installed plugin directory from `PLUGIN_ROOT` first, then use `CLAUDE_PLUGIN_ROOT` as a compatibility fallback.

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
