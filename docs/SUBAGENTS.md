# Git Workflow agents

Git Workflow includes eight specialized agents. The Markdown files in `agents/` are canonical; setup installs generated Codex definitions into `.codex/agents/` and Claude continues to discover the canonical files through its plugin package.

| Agent | Purpose | Codex sandbox |
| --- | --- | --- |
| `pr-reviewer` | Reviews code quality, security, performance, tests, and documentation | `read-only` |
| `silent-failure-hunter` | Finds swallowed errors and misleading fallbacks | `read-only` |
| `type-design-analyzer` | Evaluates invariants and type design | `read-only` |
| `pr-test-analyzer` | Identifies behavioral test-coverage gaps | `read-only` |
| `comment-analyzer` | Detects inaccurate comments and documentation | `read-only` |
| `version-delta-analyst` | Researches breaking changes and migration steps | `read-only` |
| `release-validator` | Runs pre-release checks and reports readiness | `workspace-write` |
| `qa-executor` | Executes QA plans and records results | `workspace-write` |

## Invocation

The workflow skills delegate to these agents when appropriate:

- `/review` in Claude or `$review` in Codex fans out to the review specialists and waits for every report.
- `/release` or `$release` delegates release validation and, when dependencies or APIs changed, version-delta analysis.
- `/start-qa` or `$start-qa` delegates large QA plans to `qa-executor`.

You can also request an agent explicitly, for example: “Use the `pr-reviewer` agent to review these changes.” Routine edits do not automatically create agent sessions.

## Maintaining agents

Edit `agents/<name>.md`, then regenerate Codex TOML files:

```bash
node scripts/generate-codex-agents.mjs
node scripts/generate-codex-agents.mjs --check
```

Generated definitions intentionally omit model and reasoning settings so they inherit the parent Codex session.
