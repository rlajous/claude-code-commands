# Skills Reference

This library provides slash commands (also known as skills) for Claude Code. Skills are markdown files with YAML frontmatter that define custom commands Claude can execute.

## Official Skills Format

Skills in Claude Code use **YAML frontmatter** in markdown files. There is no JSON manifest file - skills are discovered directly from the command files.

Reference: https://code.claude.com/docs/en/skills

Discover more skills: [skills.sh](https://skills.sh/)

## Frontmatter Fields

Each skill file (`SKILL.md`) can include the following frontmatter fields:

```yaml
---
description: What this skill does and when to use it
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
| `description` | string | What the skill does and when to use it. Shown in autocomplete. |
| `argument-hint` | string | Hint shown during autocomplete (e.g., `[ticket-id]`, `<required-arg>`). |
| `disable-model-invocation` | boolean | When `true`, prevents Claude from auto-invoking this skill. User must explicitly call it. |
| `allowed-tools` | string | Comma-separated list of tools Claude can use without asking permission. |
| `user-invocable` | boolean | When `true` (default), skill appears in slash command menu. Set to `false` for internal-only skills. |
| `model` | string | Override the model for this skill: `sonnet`, `opus`, or `haiku`. |

### Field Details

#### `description`

A brief description of what the skill does. This appears in the slash command menu and helps Claude understand when to suggest the skill.

```yaml
description: Create a feature branch from a ticket ID
```

#### `argument-hint`

Shows users what arguments the skill accepts:

- `[brackets]` indicate optional arguments
- `<angle-brackets>` indicate required arguments
- Can include multiple parts: `<ticket-id> [--url <url>]`

```yaml
argument-hint: "[ticket-id]"
```

#### `disable-model-invocation`

When set to `true`, Claude will not automatically invoke this skill - the user must explicitly type the slash command. This is recommended for workflow actions that have side effects (creating branches, committing, etc.).

```yaml
disable-model-invocation: true
```

#### `allowed-tools`

Specifies which tools Claude can use without asking for permission when executing this skill. Useful for skills that need to read files or search code.

```yaml
allowed-tools: Read, Grep, Glob
```

Available tools:
- `Read` - Read files
- `Grep` - Search file contents
- `Glob` - Find files by pattern
- `Bash` - Execute shell commands
- `Write` - Create/overwrite files
- `Edit` - Edit existing files
- `WebFetch` - Fetch web content
- `AskUserQuestion` - Ask user for input

**Security Note**: Only grant the tools necessary for the skill to function. Read-only skills should not have `Write`, `Edit`, or `Bash` access.

#### `user-invocable`

Controls whether the skill appears in the slash command menu. Defaults to `true`.

```yaml
user-invocable: true   # Appears in menu (default)
user-invocable: false  # Hidden from menu, for internal use
```

#### `model`

Override the default model for this skill. Useful for complex tasks that benefit from more capable models, or simple tasks that can use faster models.

```yaml
model: sonnet  # Default, balanced performance
model: opus    # Most capable, for complex reasoning
model: haiku   # Fastest, for simple tasks
```

## Available Commands

### PR Workflow

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/start` | Create feature branch from ticket | `[ticket-id]` |
| `/tdd` | Implement ticket using TDD (RED-GREEN-REFACTOR) | `<ticket-id>` |
| `/commit` | Stage and commit with formatting | - |
| `/finish` | Create PR with description | - |

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

## Using Commands

### As Slash Commands

Type the command name with a forward slash:

```
/start PROJ-123
/commit
/finish
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

### In Conversation

You can reference commands naturally:

> "I just finished implementing the feature. Can you run /commit and then /finish?"

Claude will invoke the commands in sequence.

## Workflows

Commands are designed to work together in workflows:

### Standard PR Flow

```
/start → make changes → /commit → /finish
```

1. `/start PROJ-123` - Create branch from ticket
2. Implement your changes
3. `/commit` - Stage and commit
4. `/finish` - Push and create PR

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

## Creating Custom Skills

To add a custom skill:

1. Create a directory with a `SKILL.md` file:

```bash
mkdir -p .claude/skills/my-skill
```

2. Create the skill file:

```markdown
---
description: Your skill description
argument-hint: "[optional-arg]"
disable-model-invocation: true
---

Your skill instructions here...
```

3. Use it with `/my-skill`

The directory name becomes the skill name.

## Directory Structure

### Plugin Format (This Repo)

```
skills/                 # Skill directories
├── setup/
│   └── SKILL.md
├── start/
│   └── SKILL.md
├── tdd/
│   └── SKILL.md
├── commit/
│   └── SKILL.md
├── finish/
│   └── SKILL.md
├── release/
│   └── SKILL.md
├── release-notes/
│   └── SKILL.md
├── sync/
│   └── SKILL.md
├── plan-qa/
│   └── SKILL.md
└── start-qa/
    └── SKILL.md

agents/                 # Subagents
├── pr-reviewer.md
├── release-validator.md
└── qa-executor.md
```

### Project Installation (Manual Copy)

```
.claude/
├── skills/             # Skill directories
│   ├── start/
│   │   └── SKILL.md
│   ├── commit/
│   │   └── SKILL.md
│   └── ...
└── agents/             # Subagents
    ├── pr-reviewer.md
    └── ...
```

### Legacy Format (Still Supported)

```
.claude/
├── commands/           # Single-file commands
│   ├── start.md
│   └── ...
└── agents/
    └── ...
```

## Subagents

Subagents are specialized AI assistants defined in the `agents/` directory. They have their own instructions and tool access.

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

See [AGENTS.md](./AGENTS.md) for complete documentation.

## Configuration

Commands respect the project configuration in `.claude/config.yaml`:

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
- Or use legacy format: `.claude/commands/{name}.md`

### Arguments Not Passed

Arguments are passed after the command name:
- Correct: `/start PROJ-123`
- Incorrect: `/start ticket=PROJ-123`

### Command Conflicts

If a command conflicts with a built-in command, the built-in takes precedence. Rename your command to avoid conflicts.
