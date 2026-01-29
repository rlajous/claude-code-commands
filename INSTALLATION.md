# Installation Guide

This guide walks you through setting up Claude Code Git Workflow commands in your project.

## Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed
- [Git](https://git-scm.com/) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) for PR creation
- (Optional) MCP servers for Linear/Jira integration

## Quick Setup

### Option 1: Install from Marketplace (Recommended)

The easiest way to install is via the Claude marketplace:

```bash
# Add the marketplace
/plugin marketplace add rlajous/claude-code-commands

# Install the plugin
/plugin install git-workflow@git-workflow-marketplace
```

After installation, commands are available with the `git-workflow:` prefix:

```bash
/git-workflow:setup   # Run interactive setup
/git-workflow:start PROJ-123
/git-workflow:commit
/git-workflow:finish
```

### Option 2: Manual Installation (Shorter Command Names)

For shorter command names (e.g., `/start` instead of `/git-workflow:start`):

```bash
# Clone the repository
git clone https://github.com/rlajous/claude-code-commands.git

# Copy commands to your project
cp -r claude-code-commands/commands your-project/.claude/

# (Optional) Copy agents
cp -r claude-code-commands/agents your-project/.claude/

# (Optional) Copy config template
cp claude-code-commands/templates/config.yaml.template your-project/.claude/config.yaml
```

### Option 3: Plugin Directory

Load as a plugin directory for temporary use:

```bash
# Clone the repository
git clone https://github.com/rlajous/claude-code-commands.git ~/claude-plugins/git-workflow

# Use with --plugin-dir flag
claude --plugin-dir ~/claude-plugins/git-workflow
```

---

## Post-Installation Setup

After installing via any method, run the interactive setup:

```bash
/setup  # or /git-workflow:setup if using marketplace
```

This guides you through configuring:
- **Issue tracker integration** - Linear, Jira, or GitHub Issues
- **MCP server setup** - Automatic configuration for your chosen tracker
- **Workflow settings** - Branch naming, commit formats, and more

---

## Directory Structure

### Marketplace Installation

Commands are installed to Claude's plugin cache. No files in your project.

### Manual Installation

After manual installation, your project should have:

```
your-project/
├── .claude/
│   ├── commands/             # Slash commands (legacy format)
│   │   ├── setup.md
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
│   └── config.yaml           # Optional configuration
├── CLAUDE.md                 # Optional but recommended
└── ... your project files
```

---

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

---

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

---

## Issue Tracker Setup

Commands integrate with issue trackers via **MCP (Model Context Protocol) servers**. MCP servers handle authentication automatically through OAuth.

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

---

## Adding This Marketplace to Team Projects

You can configure your repository so team members are automatically prompted to install this marketplace when they trust the project folder. Add to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "git-workflow-marketplace": {
      "source": {
        "source": "github",
        "repo": "rlajous/claude-code-commands"
      }
    }
  },
  "enabledPlugins": {
    "git-workflow@git-workflow-marketplace": true
  }
}
```

---

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

---

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

---

## Verification

Test your installation:

```bash
# For marketplace installation
/git-workflow:start

# For manual installation
/start

# Claude should recognize the command and ask for ticket info
```

---

## Updating

### Marketplace Installation

```bash
/plugin marketplace update git-workflow-marketplace
```

### Manual Installation

```bash
cd claude-code-commands
git pull
cp -r commands ../your-project/.claude/
```

---

## Troubleshooting

### Commands Not Recognized (Marketplace)

Ensure you're using the prefixed command name:

```bash
/git-workflow:start  # Correct
/start               # Won't work with marketplace install
```

### Commands Not Recognized (Manual)

Ensure commands are in `.claude/commands/*.md` format:

```bash
ls -la .claude/commands/start.md
```

### GitHub CLI Not Authenticated

```bash
gh auth status  # Check status
gh auth login   # Re-authenticate
```

### Issue Tracker Not Connected

Check if MCP servers are configured:

```bash
cat ~/.claude/settings.json | grep mcpServers
```

### Permission Denied

```bash
chmod -R 644 .claude/commands/*.md
```

---

## Migration

No migration needed. This plugin uses `.claude/commands/*.md` for reliable autocomplete.

---

## Next Steps

1. Read [CONFIGURATION.md](./CONFIGURATION.md) for customization options
2. Read [SKILLS.md](./SKILLS.md) for command and workflow documentation
3. Read [AGENTS.md](./AGENTS.md) for subagent documentation
4. Read [HOOKS.md](./HOOKS.md) for hooks documentation
5. Check [examples/](./examples/) for stack-specific configurations
6. Try the workflow: `/start` → make changes → `/commit` → `/finish`
