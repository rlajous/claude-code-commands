# Git Workflow installation

Git Workflow supports Claude Code and Codex from the same checkout. Git and Bash are required. GitHub operations use the GitHub CLI; setup, update, and HTML status generation use Node.js; hooks use Python 3; synchronization previews use `diff`. Issue trackers are optional and use the active host's MCP configuration.

## Claude Code

### Marketplace

```text
/plugin marketplace add rlajous/claude-code-commands
/plugin install git-workflow@git-workflow-marketplace
```

Marketplace skills use names such as `/git-workflow:start` and `/git-workflow:review`.

### Project-local installation

For unprefixed skills, copy the shared skills and canonical Claude agents:

```bash
git clone https://github.com/rlajous/claude-code-commands.git
mkdir -p your-project/.claude
cp -R claude-code-commands/skills your-project/.claude/skills
cp -R claude-code-commands/agents your-project/.claude/agents
cp -R claude-code-commands/references your-project/.claude/references
```

Claude-specific plugin and contributor behavior remains documented in [CLAUDE.md](CLAUDE.md).

## Codex

Install or load this checkout using Codex's plugin workflow. The root `.codex-plugin/plugin.json` exposes the shared `skills/` directory, and `hooks/hooks.json` contains the Codex-native hook registration.

When developing directly in this checkout, Codex discovers the same skills through
`.agents/skills -> ../skills`. Plugin installation and checkout-local discovery are alternative
modes: do not enable both in the same session, because Codex does not merge duplicate skill names.

After the plugin is available, run this inside the target repository:

```text
$setup
```

Setup creates or migrates `.git-workflow/config.yaml`, then installs the eight project-scoped named agents into `.codex/agents/`. Codex discovers those definitions on its next project instruction/agent refresh. Agent definitions inherit the parent model, reasoning effort, and concurrency settings.

To install agents manually from a checkout:

```bash
mkdir -p your-project/.codex/agents
cp claude-code-commands/.codex/agents/*.toml your-project/.codex/agents/
```

Do not copy over existing project agents without reviewing the diff. `$setup --force` and `$update --force` are the explicit replacement paths. Use `--host codex`, `--host claude`, or `--host both` to select project assets, and use `--dry-run` for a write-free preview.

## Project configuration

Both hosts use the same canonical configuration:

```bash
mkdir -p .git-workflow
cp /path/to/git-workflow/templates/config.yaml.template .git-workflow/config.yaml
```

Or run `/git-workflow:setup` for a Claude marketplace install, `/setup` for a manual Claude project copy, or `$setup` in Codex. Setup reads legacy `.claude/config.yaml` when no canonical file exists and offers to copy its values; it never deletes the legacy file.

The project layout after a typical dual-runtime setup is:

```text
project/
├── .git-workflow/
│   ├── config.yaml
│   └── version.json
├── .codex/
│   └── agents/
│       ├── pr-reviewer.toml
│       └── ...
├── AGENTS.md                 # optional project guidance for Codex
└── CLAUDE.md                 # optional project guidance for Claude
```

Generated state such as `pr-context.json`, `status.html`, the hook opt-in file, and the reviewed-SHA ledger also uses `.git-workflow/`. Matching `.claude/` locations remain read-only fallbacks.

## MCP integrations

MCP authentication belongs to the host, not `.git-workflow/config.yaml`.

For Claude Code, add servers to user or project Claude settings, for example `~/.claude/settings.json`. For Codex, add servers through Codex configuration or its MCP management command. Then set only the tracker selection in the shared config:

```yaml
issueTracker:
  type: linear # linear, jira, github, auto, or none
```

Example remote endpoints:

- Linear: `https://mcp.linear.app/mcp`
- Atlassian: `https://mcp.atlassian.com/v1/mcp/authv2`

Follow the host's authentication flow rather than placing access tokens in the repository.

## Commit-review hook

The package registers an asynchronous re-wake hook for Claude and a synchronous Bash `PostToolUse` hook for Codex. Both are inert until the project opts in:

```yaml
# .git-workflow/git-workflow.local.md
review-on-commit: true
```

Restart or reload the host after changing installed hook definitions. See [HOOKS.md](HOOKS.md) for behavior and troubleshooting.

## Updating

Run `/update` in Claude or `$update` in Codex:

```text
$update --dry-run
$update --source /path/to/checkout
$update --source https://github.com/rlajous/claude-code-commands.git
$update --host both
$update --prune
$update --force
```

The workflow compares source and target files. Unmodified managed files can be synchronized normally; customized files require confirmation unless `--force` is present. `--prune` is explicit and does not remove configuration, generated state, or unrelated project files.

## Review Watch setup

Review Watch requires Bash, Python 3, Node.js, Git, and an authenticated GitHub CLI. It is disabled
until the project opts in:

```yaml
reviewWatch:
  enabled: true
  intervalSeconds: 60
  sound: Glass
  linters: auto
  knownIssues: references/known-issues.md
```

Verify the installed paths, dependencies, configuration, and authentication without querying PRs
or publishing a review:

```text
/review-watch --doctor   # Claude Code
$review-watch --doctor   # Codex
```

Then print an absolute, copy-paste-safe daemon command and run it in another terminal:

```text
/review-watch --daemon-command   # Claude Code
$review-watch --daemon-command   # Codex
```

The daemon notifies once per repository, PR, and head SHA. macOS uses Notification Center and a
system sound; Linux uses the active desktop's `notify-send` presentation and an available sound
player. Grant notification permission to the terminal or AppleScript host if macOS suppresses the
banner.

Read the [Review Watch guide](docs/REVIEW_WATCH.md) for repository filters, queue state, review
decisions, notification examples, and troubleshooting. Clean reviews generate the self-contained
HTML described in the [Change Brief guide](docs/CHANGE_BRIEF.md).

## Verify

Check the expected skills and agents in the host, then try the non-destructive status workflow:

```text
/status   # Claude
$status   # Codex
```

For this package checkout, run:

```bash
bash scripts/validate.sh
```

## Troubleshooting

- If a Claude skill is missing, verify the plugin is enabled or `.claude/skills/<name>/SKILL.md` exists.
- If a Codex skill is missing, verify the plugin is installed/enabled and restart the session after changing its manifest.
- For checkout-local development, verify `.agents/skills` resolves to `../skills`; disable the
  installed plugin for that session to avoid duplicate skill entries.
- If a Codex agent is missing, rerun `$setup` and verify `.codex/agents/<name>.toml` exists and parses.
- If GitHub actions fail, run `gh auth status` and authenticate with `gh auth login`.
- If Review Watch is silent, run the host-correct `review-watch --doctor`, confirm
  `reviewWatch.enabled: true`, and verify OS notification permissions.
- If issue lookup fails, inspect the active host's MCP connection and OAuth state.
- If the hook does nothing, confirm `review-on-commit: true`, start a new host session, and verify the invoked command is `git commit` or `git push`.
