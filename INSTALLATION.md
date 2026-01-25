# Installation Guide

This guide walks you through setting up Claude Code Commands in your project.

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Git](https://git-scm.com/) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR creation
- (Optional) MCP servers for Linear/Jira integration

## Quick Setup (Recommended)

After copying the commands to your project, run the interactive setup:

```bash
/setup
```

This guides you through configuring:
- **Issue tracker integration** - Linear, Jira, or GitHub Issues
- **MCP server setup** - Automatic configuration for your chosen tracker
- **Workflow settings** - Branch naming, commit formats, and more

The setup command will:
1. Ask which issue tracker(s) you use
2. Configure MCP servers in your settings.json
3. Optionally set up `.claude/config.yaml` for workflow customization

You can run `/setup` at any time to reconfigure.

---

## Quick Installation

### Option 1: Copy Commands Directly (Recommended)

```bash
# Clone the repository
git clone https://github.com/rlajous/claude-code-commands.git

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
git clone https://github.com/rlajous/claude-code-commands.git ~/claude-plugins/git-workflow

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
curl -o .claude/commands/setup.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/setup.md
curl -o .claude/commands/start.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/start.md
curl -o .claude/commands/tdd.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/tdd.md
curl -o .claude/commands/commit.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/commit.md
curl -o .claude/commands/finish.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/finish.md
curl -o .claude/commands/release.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/release.md
curl -o .claude/commands/release-notes.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/release-notes.md
curl -o .claude/commands/sync.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/sync.md
curl -o .claude/commands/plan-qa.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/plan-qa.md
curl -o .claude/commands/start-qa.md https://raw.githubusercontent.com/rlajous/claude-code-commands/main/.claude/commands/start-qa.md
```

## Directory Structure

After installation, your project should have:

```
your-project/
├── .claude/
│   ├── commands/             # Slash commands
│   │   ├── setup.md          # Interactive setup wizard
│   │   ├── start.md
│   │   ├── tdd.md
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

Commands integrate with issue trackers via **MCP (Model Context Protocol) servers**. MCP servers handle authentication automatically through OAuth or system credentials.

### Linear (via MCP)

1. Add the Linear MCP server to your Claude Code settings:

```json
// In ~/.claude/settings.json or .claude/settings.json
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@anthropic/linear-mcp"]
    }
  }
}
```

2. On first use, the MCP server will prompt for OAuth authentication.

3. Configure issue tracker type (optional):

```yaml
# .claude/config.yaml
issueTracker:
  type: linear
```

### Jira (via MCP)

1. Add the Jira MCP server to your Claude Code settings:

```json
// In ~/.claude/settings.json or .claude/settings.json
{
  "mcpServers": {
    "jira": {
      "command": "npx",
      "args": ["-y", "@anthropic/jira-mcp"],
      "env": {
        "JIRA_INSTANCE_URL": "https://your-company.atlassian.net"
      }
    }
  }
}
```

2. On first use, the MCP server will prompt for Atlassian authentication.

3. Configure issue tracker type:

```yaml
# .claude/config.yaml
issueTracker:
  type: jira
  jira:
    baseUrl: https://your-company.atlassian.net
```

### GitHub Issues

No additional setup required. Uses `gh` CLI (already authenticated).

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

### Issue Tracker Not Connected

Ensure MCP servers are configured in your Claude Code settings:

```bash
# Check if MCP servers are configured
cat ~/.claude/settings.json | grep mcpServers
```

If using environment variables for other integrations, add to your shell profile (`.bashrc`, `.zshrc`):

```bash
export API_BASE_URL=https://api.example.com
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
