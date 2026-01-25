# Claude Code Commands

Production-ready slash commands for Claude Code that automate your Git workflow, PR creation, release management, and QA testing.

## Features

- **Framework-agnostic** - Works with any language or framework
- **Configurable** - Customize everything via `.claude/config.yaml`
- **Issue tracker integration** - Linear, Jira, and GitHub Issues
- **Multi-workflow support** - Staging-based, tag-based, or direct workflows
- **Zero configuration** - Sensible defaults work out of the box
- **Subagents** - Specialized AI assistants for code review, release validation, and QA
- **Hooks** - Automate actions before/after tool use
- **Plugin format** - Installable as a Claude Code plugin

## Quick Start

### 1. Copy Commands to Your Project

```bash
# Clone this repository
git clone https://github.com/your-org/claude-code-commands.git

# Copy commands to your project
cp -r claude-code-commands/.claude/commands your-project/.claude/
```

### 2. (Optional) Add Configuration

Create `.claude/config.yaml` for project-specific settings:

```yaml
# Basic configuration example
workflow:
  developmentBranch: staging
  productionBranch: main

issueTracker:
  type: linear  # or jira, github

pullRequests:
  reviewers:
    - your-team
```

See [CONFIGURATION.md](./CONFIGURATION.md) for all options.

### 3. Use the Commands

```bash
# Start a new feature
/start

# Commit changes
/commit

# Create a PR
/finish
```

## Commands

| Command | Description |
|---------|-------------|
| `/start` | Create a feature branch from a ticket ID |
| `/tdd` | Implement ticket using Test-Driven Development |
| `/commit` | Stage and commit with conventional format |
| `/finish` | Push branch and create PR with full description |
| `/release` | Create release branch with version bump |
| `/release-notes` | Generate GitHub release with detailed notes |
| `/sync` | Back-merge production to development branch |
| `/plan-qa` | Generate QA test plan from ticket |
| `/start-qa` | Execute QA tests from plan file |

## Subagents

Specialized AI assistants for common tasks:

| Agent | Description |
|-------|-------------|
| `pr-reviewer` | Expert code reviewer for quality, security, and best practices |
| `release-validator` | Pre-release validation (tests, build, dependencies) |
| `qa-executor` | Executes QA test plans with detailed reporting |

### Using Subagents

Subagents are invoked automatically when relevant, or explicitly:

```
Review the code changes in this PR
Use the release-validator to check if we're ready to release
```

See [AGENTS.md](./AGENTS.md) for complete documentation.

## Hooks

Automate actions at key points in your workflow:

- **PostToolUse** - Run after file edits (auto-format, lint)
- **PreToolUse** - Validate before execution (prevent dangerous commands)
- **SessionStart/End** - Setup and logging

### Example Hook

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "npm run lint:fix -- $CLAUDE_FILE_PATH"
          }
        ]
      }
    ]
  }
}
```

See [HOOKS.md](./HOOKS.md) for complete documentation.

## Skills

Commands are defined using **YAML frontmatter** in markdown files, following the official Claude Code skills format.

### Using Commands

Commands can be invoked in multiple ways:

```bash
# As slash commands
/start PROJ-123
/commit
/finish

# With arguments
/plan-qa PROJ-123 --url https://api.staging.example.com

# In conversation
"Run /commit and then /finish for me"
```

### Command Format

Each command file uses YAML frontmatter for configuration:

```yaml
---
description: What this command does
argument-hint: "[optional-arg]"
disable-model-invocation: true
---
```

See [SKILLS.md](./SKILLS.md) for complete documentation.

## Workflow

### Standard PR Flow

```
/start → make changes → /commit → /finish
```

1. **`/start`** - Creates feature branch, fetches ticket details
2. **Work** - Make your code changes
3. **`/commit`** - Stages files, creates formatted commit
4. **`/finish`** - Pushes branch, creates comprehensive PR

### TDD Flow

```
/start → /tdd → /commit → /finish
```

1. **`/start`** - Creates feature branch, fetches ticket details
2. **`/tdd`** - Implement using Test-Driven Development:
   - **RED** - Write failing tests based on acceptance criteria
   - **GREEN** - Implement minimum code to pass tests
   - **REFACTOR** - Clean up code while keeping tests green
3. **`/commit`** - Stages files, creates formatted commit
4. **`/finish`** - Pushes branch, creates comprehensive PR

### Release Flow

```
/release → review → merge → /release-notes → /sync
```

1. **`/release`** - Creates release branch, bumps version, opens PR to main
2. **Review** - Team reviews and approves
3. **Merge** - Merge to production branch
4. **`/release-notes`** - Creates GitHub release with categorized notes
5. **`/sync`** - Back-merges main to development branch

## Configuration

Commands work without configuration using sensible defaults:

| Default | Value |
|---------|-------|
| Development branch | `staging` |
| Production branch | `main` |
| Branch format | `{type}/{ticket}-{description}` |
| Commit format | `[{type}] {message} ({ticket})` |
| Issue tracker | Auto-detected |
| Package manager | Auto-detected |

### Override with Config

```yaml
# .claude/config.yaml
workflow:
  developmentBranch: develop
  productionBranch: main

commits:
  format: "{type}: {message}"
  requireTicket: false

issueTracker:
  type: jira  # Uses MCP server for authentication
  jira:
    baseUrl: https://company.atlassian.net
```

See [CONFIGURATION.md](./CONFIGURATION.md) for complete reference.

## Issue Tracker Integration

Commands integrate with issue trackers via **MCP servers** (recommended) for automatic authentication, or can fall back to manual API configuration.

### Linear (via MCP)

```json
// In ~/.claude/settings.json
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@anthropic/linear-mcp"]
    }
  }
}
```

Commands will fetch ticket details, update status, and link PRs.

### Jira (via MCP)

```json
// In ~/.claude/settings.json
{
  "mcpServers": {
    "jira": {
      "command": "npx",
      "args": ["-y", "@anthropic/jira-mcp"],
      "env": {
        "JIRA_INSTANCE_URL": "https://company.atlassian.net"
      }
    }
  }
}
```

### GitHub Issues

```yaml
issueTracker:
  type: github
```

Uses `gh` CLI for issue integration (no additional setup required).

## Examples

Pre-configured examples for common stacks:

- **[NestJS Backend](./examples/nestjs/)** - Node.js API with Prisma
- **[Next.js Frontend](./examples/nextjs/)** - React app with App Router
- **[Python FastAPI](./examples/python/)** - Python API with SQLAlchemy
- **[React Native](./examples/react-native/)** - Mobile app with Expo
- **[Monorepo](./examples/monorepo/)** - Turborepo with multiple apps

## Supported Tech Stacks

### Package Managers

- npm, pnpm, yarn, bun (Node.js)
- uv, pip, poetry (Python)
- cargo (Rust)
- go mod (Go)

### Version Files

Auto-detected from project:

- `package.json` (Node.js)
- `pyproject.toml` (Python)
- `Cargo.toml` (Rust)
- `VERSION` (Generic)

## Installation

### Option 1: Copy Commands (Recommended)

```bash
# Clone and copy to your project
git clone https://github.com/your-org/claude-code-commands.git
cp -r claude-code-commands/.claude your-project/
```

### Option 2: Install as Plugin

```bash
# Install as a Claude Code plugin
claude --plugin-dir /path/to/claude-code-commands
```

See [INSTALLATION.md](./INSTALLATION.md) for detailed setup instructions.

## CLAUDE.md Template

Add a `CLAUDE.md` to your project to provide context:

```markdown
# CLAUDE.md

## Project Overview
Brief description of your project...

## Development Commands
npm install
npm run dev
npm test

## Git Workflow
Uses Claude Code slash commands...
```

See [templates/CLAUDE.md.template](./templates/CLAUDE.md.template) for a complete template.

## Customization

### Custom Commit Format

```yaml
commits:
  format: "{type}({scope}): {message}"
  types: [feat, fix, docs, style, refactor, test, chore]
```

### Custom Branch Naming

```yaml
branches:
  feature: "feature/{ticket}/{description}"
  release: "v{version}"
```

### Custom Reviewers

```yaml
pullRequests:
  reviewers:
    - alice
    - bob
    - team/backend
  labels:
    - needs-review
```

## Best Practices

1. **Start with defaults** - Commands work without config
2. **Add config gradually** - Only configure what you need
3. **Use CLAUDE.md** - Help Claude understand your project
4. **Consistent workflow** - Use the same commands across teams

## Troubleshooting

### Command Not Found

Ensure `.claude/commands/` directory exists with `.md` files.

### GitHub CLI Issues

```bash
# Authenticate with GitHub
gh auth login
```

### Issue Tracker Not Working

Check MCP server configuration in `~/.claude/settings.json`:

```bash
cat ~/.claude/settings.json | grep -A 10 mcpServers
```

See [INSTALLATION.md](./INSTALLATION.md) for MCP server setup instructions.

## Contributing

Contributions welcome! Please read our contributing guidelines.

## License

MIT License - see [LICENSE](./LICENSE) for details.
