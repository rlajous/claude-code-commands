# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository is the dual-runtime **Git Workflow** package. Claude Code consumes its marketplace/plugin packaging and Claude-specific frontmatter; Codex consumes `.codex-plugin/plugin.json` and generated `.codex/agents/*.toml`. Shared workflow configuration lives in `.git-workflow/config.yaml`, with legacy `.claude/config.yaml` reads retained for compatibility.

## Behavioral Guidelines

- **Strictly Reactive**: Only perform the specific task requested. Do not perform follow-up research, planning for future phases, or speculative actions unless explicitly asked.
- **Seek Confirmation**: Always wait for user confirmation after completing a discrete task before moving to anything else.
- **No Unapproved Side Effects**: Do not apply database migrations, execute scripts, or modify the system state without explicit approval for that specific action.

## Repository Structure

```
.claude-plugin/
├── marketplace.json       # Marketplace catalog for distribution
└── plugin.json            # Plugin manifest

.codex-plugin/
└── plugin.json            # Codex plugin manifest

.codex/agents/             # Generated Codex project agents (do not hand-edit)

skills/                    # Skills (each an invocable slash command via SKILL.md)
├── setup/SKILL.md         # Interactive setup wizard
├── start/SKILL.md         # Create feature branch from ticket
├── tdd/SKILL.md           # Test-Driven Development workflow
├── commit/SKILL.md        # Stage and commit with conventions
├── finish/SKILL.md        # Create PR with full description
├── review/SKILL.md        # Comprehensive code review on a PR
├── release/SKILL.md       # Create release branch and PR
├── release-notes/SKILL.md # Generate GitHub release notes
├── sync/SKILL.md          # Back-merge main to development
├── plan-qa/SKILL.md       # Generate QA test plan
├── start-qa/SKILL.md      # Execute QA tests
├── rfc/SKILL.md           # Create an auto-numbered RFC document
├── review-request/SKILL.md # Draft a paste-ready PR review request
├── standup/SKILL.md       # Async standup from recent activity
├── update/SKILL.md        # Update skills/agents from source
├── clean-gone/SKILL.md    # Delete local branches gone on the remote
├── status/SKILL.md        # Show workflow position and next step
├── review-watch/SKILL.md  # Auto-review PRs that request your review, in a loop
├── notifications/SKILL.md # Opt-in agent and authored-PR activity alerts
└── change-brief/SKILL.md  # Self-contained HTML explainer of a change

agents/                    # Subagents for specialized tasks
├── pr-reviewer.md         # Code review agent
├── release-validator.md   # Release validation agent
└── qa-executor.md         # QA test execution agent

templates/
├── config.yaml.template   # Configuration template
├── settings.json.template # Hooks configuration template
└── CLAUDE.md.template     # CLAUDE.md template for projects

examples/                  # Stack-specific examples
├── nestjs/               # NestJS backend config
├── nextjs/               # Next.js frontend config
├── python/               # Python FastAPI config
├── react-native/         # React Native config
└── monorepo/             # Turborepo monorepo config

README.md                  # Main documentation
INSTALLATION.md            # Setup guide
CONFIGURATION.md           # Configuration reference
COMMANDS.md                # Commands reference documentation
AGENTS.md                  # Concise Codex contributor guidance
docs/SUBAGENTS.md          # User-facing agent catalog
HOOKS.md                   # Hooks documentation
LICENSE                    # MIT license
```

## Skills Format

Each capability is a **skill**: a directory under `skills/` containing a `SKILL.md`
with YAML frontmatter. This is the current, preferred format (the older
`.claude/commands/*.md` layout is legacy). A skill with `user-invocable: true`
still works as a manual slash command (`/start`), and — unless
`disable-model-invocation: true` is set — can also be auto-invoked by Claude when
its `description` matches the task.

```yaml
---
name: start
description: What this skill does, with trigger phrases for auto-invocation
argument-hint: "[optional-arg]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---
```

Key frontmatter fields:
- `name`: Skill identifier (required); also the slash command name
- `description`: Shown in the menu and used to decide auto-invocation
- `argument-hint`: Shows expected arguments
- `disable-model-invocation`: Prevents auto-invocation (kept on side-effecting workflow actions; omitted on read-only skills like `review`)
- `allowed-tools`: Tools Claude can use without asking permission
- `user-invocable`: Makes the skill available as a `/name` slash command

Skills may bundle `references/`, `scripts/`, `examples/`, or `assets/` in their
directory for progressive disclosure (loaded on demand, keeping `SKILL.md` lean).

## Marketplace Format

This repo serves as both a plugin and a marketplace:

- **marketplace.json**: Catalog of plugins in this marketplace
- **plugin.json**: Metadata for the git-workflow plugin

Users can install via:
```bash
/plugin marketplace add rlajous/claude-code-commands
/plugin install git-workflow@git-workflow-marketplace
```

## Workflow Commands

| Command          | Purpose                                        |
| ---------------- | ---------------------------------------------- |
| `/setup`         | Interactive setup for MCP servers and config   |
| `/start`         | Create feature branch from ticket ID           |
| `/tdd`           | Implement ticket using TDD (RED-GREEN-REFACTOR)|
| `/commit`        | Stage and commit with formatted message        |
| `/finish`        | Push branch and create PR                      |
| `/review`        | Comprehensive code review on a PR              |
| `/release`       | Create release branch, bump version, PR to main|
| `/release-notes` | Generate GitHub release with detailed notes    |
| `/sync`          | Back-merge main to development branch          |
| `/plan-qa`       | Generate QA test plan YAML from ticket         |
| `/start-qa`      | Execute QA tests from plan file                |
| `/rfc`           | Create an auto-numbered RFC document           |
| `/review-request`| Draft a paste-ready PR review request          |
| `/standup`       | Async standup (Did / Next / Blockers)          |
| `/update`        | Update skills/agents from source repo          |
| `/clean-gone`    | Delete local branches gone on the remote and their worktrees |
| `/status`        | Show workflow position and the recommended next step         |
| `/review-watch`  | Auto-review PRs that request your review, in a loop (REQUEST_CHANGES / APPROVE) |
| `/notifications` | Diagnose opt-in main-agent and authored-PR review notifications               |
| `/change-brief`  | Generate a self-contained HTML explainer of a change         |

## Subagents

| Agent              | Purpose                                        |
| ------------------ | ---------------------------------------------- |
| `pr-reviewer`      | Expert code reviewer for quality and security  |
| `release-validator`| Pre-release validation (tests, build, deps)    |
| `qa-executor`      | Execute QA tests with detailed reporting       |
| `silent-failure-hunter` | Hunts swallowed errors, over-broad catch blocks, and silent fallbacks in changed code |
| `type-design-analyzer` | Rates type design: encapsulation, invariant expression, usefulness, enforcement (1-10 each) |
| `pr-test-analyzer` | Finds behavioral test-coverage gaps, rating each missing test's criticality and the regression it catches |
| `comment-analyzer` | Detects comment rot and docstrings that no longer match the code |
| `version-delta-analyst` | Catalogs breaking changes, deprecations, and migration steps between two versions of a dependency/stack/API |

## Standard Workflows

### PR Flow
```
/start → make changes → /commit → /finish → /review
```

### TDD Flow
```
/start → /tdd → /commit → /finish
```

### Release Flow
```
/release → review → merge → /release-notes → /sync
```

## Hooks

Hooks automate actions during Claude Code execution. Configure in `settings.json`:

- `PostToolUse`: Run after file edits (auto-format, lint)
- `PreToolUse`: Validate before execution (block dangerous commands)
- `SessionStart/End`: Setup and logging

The repo also ships opt-in hooks. Claude selects `hooks/claude-hooks.json`; Codex discovers
`hooks/hooks.json`. Both call `hooks/review-commit.sh` after eligible Git commands and the
notification adapter after the main turn stops. Enable commit review with `review-on-commit: true`
in `.git-workflow/git-workflow.local.md`; enable completion alerts with
`notifications.agentComplete: true` in `.git-workflow/config.yaml`. The old `.claude/` paths remain
read-only fallbacks.

See [HOOKS.md](./HOOKS.md) for complete documentation.

## Design Decisions

### Marketplace Structure
- Single plugin containing all commands (cohesive workflow)
- Skills in `skills/<name>/SKILL.md` format
- Agents in `agents/` at root level

### Configuration System
- Zero-config design with sensible defaults
- Cascading config: explicit config > auto-detection > defaults
- Context persistence via `.pr-context.json`

### Issue Tracker Support
- Auto-detection from ticket format
- Linear, Jira, and GitHub Issues integration
- MCP servers for automatic authentication

### Multi-Stack Support

- Auto-detects package manager from lock files
- Supports multiple version file formats
- Examples for common tech stacks

## Testing Changes

When modifying commands:

1. Verify YAML frontmatter is valid
2. Check command steps are numbered correctly
3. Ensure config references match schema
4. Test with and without config file

Run `bash scripts/validate.sh` to check manifests (valid JSON, aligned versions),
skill/agent frontmatter, and SKILL.md sizes. CI runs the same check on every PR
(`.github/workflows/validate.yml`).

## Git Commits

When creating git commits, do NOT include Co-Authored-By lines in commit messages.
