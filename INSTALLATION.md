# Installation Guide

This guide walks you through setting up Claude Code Commands in your project.

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Git](https://git-scm.com/) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR creation
- (Optional) Issue tracker API keys for Linear/Jira integration

## Quick Installation

### Option 1: Copy Commands Directly (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-org/claude-code-commands.git

# Copy commands to your project
cp -r claude-code-commands/.claude/commands your-project/.claude/

# (Optional) Copy agents
cp -r claude-code-commands/.claude/agents your-project/.claude/

# (Optional) Copy config template
cp claude-code-commands/templates/config.yaml.template your-project/.claude/config.yaml

# (Optional) Copy CLAUDE.md template
cp claude-code-commands/templates/CLAUDE.md.template your-project/CLAUDE.md
```

### Option 2: Install as Plugin

Install the entire repository as a Claude Code plugin:

```bash
# Clone the repository
git clone https://github.com/your-org/claude-code-commands.git ~/claude-plugins/git-workflow

# Use with --plugin-dir flag
claude --plugin-dir ~/claude-plugins/git-workflow
```

Or add to your Claude Code configuration to load automatically.

### Option 3: Manual Setup

1. Create the commands directory:

```bash
mkdir -p .claude/commands
```

2. Download individual command files:

```bash
# Download commands
curl -o .claude/commands/start.md https://raw.githubusercontent.com/.../start.md
curl -o .claude/commands/commit.md https://raw.githubusercontent.com/.../commit.md
curl -o .claude/commands/finish.md https://raw.githubusercontent.com/.../finish.md
curl -o .claude/commands/release.md https://raw.githubusercontent.com/.../release.md
curl -o .claude/commands/release-notes.md https://raw.githubusercontent.com/.../release-notes.md
curl -o .claude/commands/sync.md https://raw.githubusercontent.com/.../sync.md
curl -o .claude/commands/plan-qa.md https://raw.githubusercontent.com/.../plan-qa.md
curl -o .claude/commands/start-qa.md https://raw.githubusercontent.com/.../start-qa.md
```

## Directory Structure

After installation, your project should have:

```
your-project/
├── .claude/
│   ├── commands/             # Slash commands
│   │   ├── start.md
│   │   ├── commit.md
│   │   ├── finish.md
│   │   ├── release.md
│   │   ├── release-notes.md
│   │   ├── sync.md
│   │   ├── plan-qa.md
│   │   └── start-qa.md
│   ├── agents/               # Subagents (optional)
│   │   ├── pr-reviewer.md
│   │   ├── release-validator.md
│   │   └── qa-executor.md
│   └── config.yaml           # Optional
├── CLAUDE.md                 # Optional but recommended
└── ... your project files
```

## Configuration

### Without Configuration (Defaults)

Commands work immediately with these defaults:

- Development branch: `staging`
- Production branch: `main`
- Branch format: `{type}/{ticket}-{description}`
- Commit format: `[{type}] {message} ({ticket})`
- Issue tracker: Auto-detected
- Package manager: Auto-detected

### With Configuration

Create `.claude/config.yaml`:

```yaml
# Minimal configuration
workflow:
  developmentBranch: develop
  productionBranch: main

pullRequests:
  reviewers:
    - your-team
```

See [CONFIGURATION.md](./CONFIGURATION.md) for all options.

## GitHub CLI Setup

The `/finish`, `/release`, and `/release-notes` commands require GitHub CLI:

```bash
# Install GitHub CLI
# macOS
brew install gh

# Ubuntu/Debian
sudo apt install gh

# Windows
winget install --id GitHub.cli

# Authenticate
gh auth login
```

## Issue Tracker Setup

### Linear

1. Get your API key from [Linear Settings](https://linear.app/settings/api)
2. Set environment variable:

```bash
export LINEAR_API_KEY=lin_api_xxxxx
```

3. Configure (optional):

```yaml
issueTracker:
  type: linear
  linear:
    apiKey: ${LINEAR_API_KEY}
```

### Jira

1. Generate API token from [Atlassian Account](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Set environment variables:

```bash
export JIRA_API_TOKEN=your-token
export JIRA_EMAIL=your-email@company.com
```

3. Configure:

```yaml
issueTracker:
  type: jira
  jira:
    baseUrl: https://your-company.atlassian.net
    apiToken: ${JIRA_API_TOKEN}
    email: ${JIRA_EMAIL}
```

### GitHub Issues

No additional setup required. Uses `gh` CLI.

```yaml
issueTracker:
  type: github
```

## Hooks Setup (Optional)

Hooks automate actions during Claude Code execution.

1. Copy the hooks template:

```bash
cp templates/settings.json.template ~/.claude/settings.json
```

2. Or copy to project for project-specific hooks:

```bash
cp templates/settings.json.template .claude/settings.json
```

3. Customize hooks as needed. See [HOOKS.md](./HOOKS.md) for documentation.

## CLAUDE.md Setup

Create a `CLAUDE.md` in your project root to help Claude understand your project:

```markdown
# CLAUDE.md

## Project Overview
Brief description of your project.

## Development Commands
npm install
npm run dev
npm test

## Project Structure
src/ - Source code
tests/ - Test files

## Git Workflow
Uses staging-based workflow with Claude Code commands.
```

Use `templates/CLAUDE.md.template` as a starting point.

## Verification

Test your installation:

```bash
# Open Claude Code in your project
cd your-project

# Try the /start command
# Claude should recognize the command and ask for ticket info
```

## Updating Commands

To update to the latest version:

```bash
# Pull latest changes
cd claude-code-commands
git pull

# Copy updated commands
cp -r .claude/commands ../your-project/.claude/
```

## Troubleshooting

### Commands Not Recognized

Ensure commands are in `.claude/commands/` with `.md` extension.

### GitHub CLI Not Authenticated

```bash
gh auth status  # Check status
gh auth login   # Re-authenticate
```

### Environment Variables Not Set

Add to your shell profile (`.bashrc`, `.zshrc`):

```bash
export LINEAR_API_KEY=your-key
export JIRA_API_TOKEN=your-token
```

### Permission Denied

Ensure files are readable:

```bash
chmod -R 644 .claude/commands/*.md
```

## Next Steps

1. Read [CONFIGURATION.md](./CONFIGURATION.md) for customization options
2. Read [SKILLS.md](./SKILLS.md) for skills and workflow documentation
3. Read [AGENTS.md](./AGENTS.md) for subagent documentation
4. Read [HOOKS.md](./HOOKS.md) for hooks documentation
5. Check [examples/](./examples/) for stack-specific configurations
6. Try the workflow: `/start` → make changes → `/commit` → `/finish`
