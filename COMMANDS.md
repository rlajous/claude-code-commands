# Skills reference

Git Workflow provides the same 17 skills to Claude Code and Codex. Invoke a skill as `/name` in Claude and `$name` in Codex; marketplace-installed Claude skills may use `/git-workflow:name`.

## Skill format

Each `skills/<name>/SKILL.md` starts with standard `name` and `description` fields. Claude also consumes its supported frontmatter fields; Codex relies on the standard fields and the parent session's permissions. The host-neutral body is shared.

Reference: https://code.claude.com/docs/en/skills

Discover more command ideas: [skills.sh](https://skills.sh/)

## Frontmatter Fields

The following extended fields are retained for Claude compatibility:

```yaml
---
description: What this command does and when to use it
argument-hint: "[optional-arg]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
model: sonnet
---
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | What the command does and when to use it. Shown in autocomplete. |
| `argument-hint` | string | Hint shown during autocomplete (e.g., `[ticket-id]`, `<required-arg>`). |
| `disable-model-invocation` | boolean | When `true`, prevents Claude from auto-invoking this command. User must explicitly call it. |
| `allowed-tools` | string | Comma-separated list of tools Claude can use without asking permission. |
| `user-invocable` | boolean | When `true` (default), command appears in slash command menu. Set to `false` for internal-only commands. |
| `model` | string | Override the model for this command: `sonnet`, `opus`, or `haiku`. |

### Field Details

#### `description`

A brief description of what the command does. This appears in the slash command menu and helps Claude understand when to suggest the command.

```yaml
description: Create a feature branch from a ticket ID
```

#### `argument-hint`

Shows users what arguments the command accepts:

- `[brackets]` indicate optional arguments
- `<angle-brackets>` indicate required arguments
- Can include multiple parts: `<ticket-id> [--url <url>]`

```yaml
argument-hint: "[ticket-id]"
```

#### `disable-model-invocation`

When set to `true`, Claude will not automatically invoke this command. Codex plugin ingestion requires this shared field to be absent or `false`, so Git Workflow keeps it `false` and puts confirmation requirements for side effects in each skill body.

```yaml
disable-model-invocation: false
```

#### `allowed-tools`

Specifies which tools Claude can use without asking for permission when executing this command. Useful for commands that need to read files or search code.

```yaml
allowed-tools: Read, Grep, Glob
```

Skill bodies describe host-neutral actions such as reading files, searching text, running shell commands, fetching authoritative documentation, and asking the user for a decision. Each host maps those actions to its available tools and current permissions.

**Security Note**: Only grant the tools necessary for the command to function. Read-only commands should not have `Write`, `Edit`, or `Bash` access.

#### `user-invocable`

Controls whether the command appears in the slash command menu. Defaults to `true`.

```yaml
user-invocable: true   # Appears in menu (default)
user-invocable: false  # Hidden from menu, for internal use
```

#### `model`

Override the default model for this command. Useful for complex tasks that benefit from more capable models, or simple tasks that can use faster models.

```yaml
model: sonnet  # Default, balanced performance
model: opus    # Most capable, for complex reasoning
model: haiku   # Fastest, for simple tasks
```

## Available skills

The tables show Claude syntax. Replace the leading `/` with `$` in Codex.

### Setup & Maintenance

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/setup` | Interactive setup for MCP servers and project configuration | - |
| `/status` | Show where you are in the workflow and the recommended next step | `[--html]` |
| `/update` | Update commands and agents from the source repository | `[--host <claude\|codex\|both>] [--dry-run] [--prune] [--force] [--source <path-or-git-url>]` |
| `/clean-gone` | Delete local branches whose upstream is gone on the remote, and remove their worktrees | `[--dry-run]` |

### PR Workflow

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/start` | Create feature branch from ticket | `[ticket-id]` |
| `/tdd` | Implement ticket using TDD (RED-GREEN-REFACTOR) | `<ticket-id>` |
| `/commit` | Stage and commit with formatting | - |
| `/finish` | Create PR with description | - |
| `/review` | Comprehensive code review on a PR | `[pr-number-or-url]` |
| `/review-request` | Draft a paste-ready PR review request | `[pr-number-or-url]` |

### Release Management

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/release` | Create release branch and PR | - |
| `/release-notes` | Generate GitHub release notes | - |
| `/sync` | Back-merge main to staging | - |

### QA Testing

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/plan-qa` | Generate QA test plan | `<ticket-id> [--url <url>]` |
| `/start-qa` | Execute QA tests | `[plan-file]` |

### Documentation

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/rfc` | Create a new RFC document from template with auto-numbering | `<title>` |

### Team & Reporting

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/standup` | Generate an async standup (Did / Next / Blockers) from recent activity | `[--since <when>] [--author <user>]` |

## Using Commands

### Direct invocation

Use a forward slash in Claude or a dollar sign in Codex:

```text
/start PROJ-123
/commit
/finish
$start PROJ-123
$commit
$finish
```

### With Arguments

Arguments are passed after the command name:

```bash
# Start with a ticket ID
/start ENG-456

# Start with a Linear URL
/start https://linear.app/team/issue/ENG-456/add-feature

# Generate QA plan with custom base URL
/plan-qa PROJ-123 --url https://api.staging.example.com

# Run specific test file
/start-qa tests/qa/proj-123-test.yaml
```

### In conversation

You can reference commands naturally:

> "I just finished implementing the feature. Can you run /commit and then /finish?"

The active host can invoke the skills in sequence.

## Workflows

Commands are designed to work together in workflows:

### Standard PR Flow

```
/start → make changes → /commit → /finish → /review
```

1. `/start PROJ-123` - Create branch from ticket
2. Implement your changes
3. `/commit` - Stage and commit
4. `/finish` - Push and create PR
5. `/review` - Comprehensive code review on the PR

### TDD Flow

```text
/start → /tdd → /commit → /finish
```

1. `/start PROJ-123` - Create branch from ticket
2. `/tdd PROJ-123` - Implement using TDD:
   - **RED**: Write failing tests based on acceptance criteria
   - **GREEN**: Implement minimum code to pass tests
   - **REFACTOR**: Clean up code while keeping tests green
3. `/commit` - Stage and commit
4. `/finish` - Push and create PR

### Release Flow

```
/release → review & merge → /release-notes → /sync
```

1. `/release` - Create release branch and PR
2. Review and merge the release PR
3. `/release-notes` - Generate detailed release notes
4. `/sync` - Back-merge to development branch

### QA Testing Flow

```
/plan-qa → review plan → /start-qa
```

1. `/plan-qa PROJ-123` - Generate test plan from ticket
2. Review and customize the generated YAML
3. `/start-qa` - Execute the test plan

## Creating Custom Commands

To add a custom command:

1. Create a skill file:

```bash
mkdir -p .claude/skills/my-skill
touch .claude/skills/my-skill/SKILL.md
```

2. Add command frontmatter and instructions:

```markdown
---
name: my-skill
description: Your command description
argument-hint: "[optional-arg]"
disable-model-invocation: true
---

Your command instructions here...
```

3. Use it with `/my-skill`

## Directory Structure

### Plugin Format (This Repo)

```text
skills/                 # Shared host-neutral skills
├── setup/SKILL.md
├── start/SKILL.md
├── tdd/SKILL.md
├── commit/SKILL.md
├── finish/SKILL.md
├── review/SKILL.md
├── release/SKILL.md
├── release-notes/SKILL.md
├── sync/SKILL.md
├── plan-qa/SKILL.md
├── start-qa/SKILL.md
├── rfc/SKILL.md
├── update/SKILL.md
├── clean-gone/SKILL.md
└── status/SKILL.md

agents/                 # Canonical agent instructions
├── pr-reviewer.md
├── release-validator.md
└── qa-executor.md
```

### Project Installation (Manual Copy)

```text
.claude/
├── skills/             # Skills (each is an invocable slash command)
│   ├── start/SKILL.md
│   ├── commit/SKILL.md
│   └── ...
└── agents/             # Subagents
    ├── pr-reviewer.md
    └── ...
```

Codex plugins expose `skills/` directly. `$setup` installs generated project agents as `.codex/agents/*.toml`.

## Subagents

Agents are specialized assistants whose canonical instructions live in `agents/`. The committed `.codex/agents/*.toml` definitions are generated from those files.

### Agent Frontmatter

```yaml
---
name: agent-name
description: What this agent does and when to use it
tools: Read, Grep, Glob
model: sonnet
---
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique identifier for the agent |
| `description` | string | When to use this agent (enables auto-invocation) |
| `tools` | string | Comma-separated list of allowed tools |
| `model` | string | Model to use: `sonnet`, `opus`, or `haiku` |

See [docs/SUBAGENTS.md](docs/SUBAGENTS.md) for the user-facing catalog. `AGENTS.md` contains concise Codex contributor guidance.

## Configuration

Commands respect the project configuration in `.git-workflow/config.yaml`:

```yaml
# Affects /start, /commit, /finish
workflow:
  developmentBranch: staging
  productionBranch: main

branches:
  feature: "{type}/{ticket}-{description}"

commits:
  format: "[{type}] {message} ({ticket})"

# Affects /finish
pullRequests:
  reviewers:
    - your-team
```

See [CONFIGURATION.md](./CONFIGURATION.md) for all options.

## Troubleshooting

### Command Not Recognized

**For marketplace installation:**
- Use the prefixed command: `/git-workflow:start` instead of `/start`

**For manual installation:**
- Ensure the skill exists as `.claude/skills/{name}/SKILL.md`

### Arguments Not Passed

Arguments are passed after the command name:
- Correct: `/start PROJ-123`
- Incorrect: `/start ticket=PROJ-123`

### Command Conflicts

If a command conflicts with a built-in command, the built-in takes precedence. Rename your command to avoid conflicts.
