# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository is a **Claude Code plugin marketplace** containing production-ready slash commands that automate Git workflows, PR creation, release management, and QA testing. The commands are framework-agnostic and configurable via `.claude/config.yaml`.

## Behavioral Guidelines

- **Strictly Reactive**: Only perform the specific task requested. Do not perform follow-up research, planning for future phases, or speculative actions unless explicitly asked.
- **Seek Confirmation**: Always wait for user confirmation after completing a discrete task before moving to anything else.
- **No Unapproved Side Effects**: Do not apply database migrations, execute scripts, or modify the system state without explicit approval for that specific action.

## Repository Structure

```
.claude-plugin/
├── marketplace.json       # Marketplace catalog for distribution
└── plugin.json            # Plugin manifest

commands/                  # Slash commands (legacy .md format)
├── setup.md               # Interactive setup wizard
├── start.md               # Create feature branch from ticket
├── tdd.md                 # Test-Driven Development workflow
├── commit.md              # Stage and commit with conventions
├── finish.md              # Create PR with full description
├── release.md             # Create release branch and PR
├── release-notes.md       # Generate GitHub release notes
├── sync.md                # Back-merge main to development
├── plan-qa.md             # Generate QA test plan
└── start-qa.md             # Execute QA tests

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
AGENTS.md                  # Subagents documentation
HOOKS.md                   # Hooks documentation
LICENSE                    # MIT license
```

## Commands Format

Commands use YAML frontmatter in `.md` files:

```yaml
---
description: What this command does
argument-hint: "[optional-arg]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---
```

Key frontmatter fields:
- `description`: Shown in autocomplete menu
- `argument-hint`: Shows expected arguments
- `disable-model-invocation`: Prevents auto-invocation (recommended for workflow actions)
- `allowed-tools`: Tools Claude can use without asking permission

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
| `/release`       | Create release branch, bump version, PR to main|
| `/release-notes` | Generate GitHub release with detailed notes    |
| `/sync`          | Back-merge main to development branch          |
| `/plan-qa`       | Generate QA test plan YAML from ticket         |
| `/start-qa`      | Execute QA tests from plan file                |

## Subagents

| Agent              | Purpose                                        |
| ------------------ | ---------------------------------------------- |
| `pr-reviewer`      | Expert code reviewer for quality and security  |
| `release-validator`| Pre-release validation (tests, build, deps)    |
| `qa-executor`      | Execute QA tests with detailed reporting       |

## Standard Workflows

### PR Flow
```
/start → make changes → /commit → /finish
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

See [HOOKS.md](./HOOKS.md) for complete documentation.

## Design Decisions

### Marketplace Structure
- Single plugin containing all commands (cohesive workflow)
- Commands in `commands/*.md` format (legacy, but reliable autocomplete)
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

## Git Commits

When creating git commits, do NOT include Co-Authored-By lines in commit messages.
