# Configuration Reference

Complete reference for `.git-workflow/config.yaml` configuration options.

## Configuration File

Create `.git-workflow/config.yaml` in your project root. All settings are optional - commands use sensible defaults.

Matching `.claude/` files are read-only fallbacks only when the canonical file is absent. Status reports include a `warnings` array when canonical configuration or PR context cannot be read or parsed, or when saved context belongs to another branch; malformed canonical state never silently falls back to legacy data.

## Full Configuration Example

```yaml
# Package manager (auto-detected if not specified)
packageManager: auto  # npm | pnpm | yarn | bun | uv | pip | cargo | go

# Git workflow configuration
workflow:
  type: staging        # staging | tag-based | direct
  developmentBranch: staging
  productionBranch: main

# Branch naming patterns
branches:
  feature: "{type}/{ticket}-{description}"
  release: "release/{version}"
  sync: "sync/main-to-{devBranch}"

# Commit message format
commits:
  format: "[{type}] {message} ({ticket})"
  types: [Feature, Fix, Hotfix, Refactor, Docs, Test, Chore]
  requireTicket: false
  ticketPattern: "^[A-Z]+-\\d+$"

# Pull request settings
pullRequests:
  targetBranch: staging
  reviewers: []
  labels: []

# Issue tracker integration (uses MCP servers for auth)
issueTracker:
  type: auto          # auto | linear | jira | github | none
  jira:
    baseUrl: https://company.atlassian.net  # Only baseUrl needed

# Version management
versioning:
  file: auto          # auto | package.json | pyproject.toml | VERSION | Cargo.toml

# AI Attribution (disabled by default)
attribution:
  enabled: false
  format: ""

# Testing commands
testing:
  unit: auto
  e2e: auto
  lint: auto
  typeCheck: auto
  build: auto

# Review publishing and event selection
review:
  saveLocally: true
  reviewsDir: docs
  postToGitHub: ask       # ask | always | never
  maxDiffLines: 3000
  postEvent: auto         # auto | comment

# Review-request daemon and worker
reviewWatch:
  enabled: false
  intervalSeconds: 60
  linters: auto
  knownIssues: references/known-issues.md

# Local agent and authored-PR review notifications
notifications:
  agentComplete: false
  prActivity: false
  sound: Glass

# Self-contained HTML decision briefs
changeBrief:
  outputDir: .git-workflow/change-brief

# QA test settings
qa:
  apiBaseUrl: ${API_BASE_URL}
  testPlansDir: tests/qa
  resultsDir: tests/qa/results
  timeout: 10

# Release settings
release:
  watchFiles:
    openapi: docs/openapi.json
    migrations: prisma/migrations/**/migration.sql
    schema: prisma/schema.prisma
  generateChangelog: true
  changelogCategories:
    - name: "Bug Fixes"
      prefixes: ["[Fix]", "fix:"]
      emoji: "bug"
    - name: "Features"
      prefixes: ["[Feature]", "feat:"]
      emoji: "sparkles"
```

## Configuration Sections

### Package Manager

```yaml
packageManager: auto  # npm | pnpm | yarn | bun | uv | pip | cargo | go
```

Auto-detection checks for lock files:

| Lock File | Package Manager |
|-----------|-----------------|
| `package-lock.json` | npm |
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `bun.lockb` | bun |
| `uv.lock` | uv |
| `Cargo.lock` | cargo |
| `go.sum` | go |

### Workflow

```yaml
workflow:
  # Workflow type
  # staging: feature -> staging -> main (recommended)
  # tag-based: feature -> main with tags
  # direct: feature -> main (no staging)
  type: staging

  # Development/integration branch
  developmentBranch: staging  # or develop, dev

  # Production branch
  productionBranch: main  # or master
```

### Branches

```yaml
branches:
  # Feature branch pattern
  # Variables: {type}, {ticket}, {description}
  feature: "{type}/{ticket}-{description}"

  # Release branch pattern
  # Variables: {version}
  release: "release/{version}"

  # Sync branch pattern
  # Variables: {devBranch}, {version}
  sync: "sync/main-to-{devBranch}"
```

**Examples:**

| Pattern | Result |
|---------|--------|
| `{type}/{ticket}-{description}` | `fix/proj-123-fix-auth` |
| `feature/{ticket}` | `feature/proj-123` |
| `{type}/{description}` | `fix/fix-auth` |

### Commits

```yaml
commits:
  # Commit message format
  # Variables: {type}, {message}, {ticket}, {scope}
  format: "[{type}] {message} ({ticket})"

  # Allowed commit types (will be capitalized)
  types:
    - Feature
    - Fix
    - Hotfix
    - Refactor
    - Docs
    - Test
    - Chore

  # Require ticket ID in commits
  requireTicket: false

  # Ticket validation pattern
  ticketPattern: "^[A-Z]+-\\d+$"
```

**Format Examples:**

| Format | Result |
|--------|--------|
| `[{type}] {message} ({ticket})` | `[Fix] Update auth (PROJ-123)` |
| `{type}: {message}` | `fix: update auth` |
| `{type}({scope}): {message}` | `fix(auth): update flow` |
| `{ticket}: {message}` | `PROJ-123: Update auth` |

### Pull Requests

```yaml
pullRequests:
  # Default target branch for PRs
  targetBranch: staging

  # Default reviewers (GitHub usernames or team slugs)
  reviewers:
    - alice
    - bob
    - team/backend

  # Default labels
  labels:
    - needs-review
    - feature
```

### Issue Tracker

Issue tracker integration uses **MCP servers** for authentication. Configure them in the active host: Claude settings for Claude Code, or Codex MCP configuration for Codex. Authentication does not belong in this shared YAML file.

```yaml
issueTracker:
  # Tracker type
  # auto: Detect from ticket format
  # linear: Linear.app (via MCP server)
  # jira: Atlassian Jira (via MCP server)
  # github: GitHub Issues (via gh CLI)
  # none: Disable integration
  type: auto

  # Jira settings (only baseUrl needed - auth handled by MCP)
  jira:
    baseUrl: https://company.atlassian.net
```

#### Claude MCP example

Claude users can add remote MCP servers to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.linear.app/mcp"]
    },
    "jira": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.atlassian.com/v1/mcp/authv2"]
    }
  }
}
```

See [INSTALLATION.md](./INSTALLATION.md) for detailed setup instructions.

Codex users should register the same endpoints through Codex MCP configuration or its MCP management command. The workflow consumes whichever tools the active host exposes.

### Versioning

```yaml
versioning:
  # Version file location
  # auto: Detect from project type
  # Or specify: package.json, pyproject.toml, VERSION, Cargo.toml
  file: auto
```

**Auto-detection Order:**

1. `package.json` (Node.js)
2. `pyproject.toml` (Python)
3. `Cargo.toml` (Rust)
4. `VERSION` (Generic)

### Attribution

```yaml
attribution:
  # Add an AI assistance note to commit bodies (default: false)
  enabled: false

  # Optional prose note; empty by default and subject to repository commit rules.
  format: ""
```

### Testing

```yaml
testing:
  # Test commands (auto-detected or custom)
  unit: "npm test"
  e2e: "npm run test:e2e"
  lint: "npm run lint"
  typeCheck: "npm run typecheck"
  build: "npm run build"
```

### Review

```yaml
review:
  # Save the review document in the local checkout
  saveLocally: true

  # Directory used for saved review documents
  reviewsDir: docs

  # ask: preview and confirm; always: post; never: keep local
  postToGitHub: ask

  # Switch from a monolithic diff to file-by-file reading above this size
  maxDiffLines: 3000

  # auto: derive REQUEST_CHANGES/APPROVE; comment: always post COMMENT
  postEvent: auto
```

Self-authored pull requests cannot use `REQUEST_CHANGES` or `APPROVE` and fall back to `COMMENT`.
`review.postToGitHub` remains the final permission gate regardless of the resolved event.

### Review Watch

```yaml
reviewWatch:
  # Explicit opt-in for both the daemon and worker
  enabled: false

  # Poll interval in seconds; a daemon CLI option can override it
  intervalSeconds: 60

  # Auto-detect changed-file linters, or provide one explicit command
  linters: auto

  # Relative paths prefer the project, then the bundled skill reference
  knownIssues: references/known-issues.md
```

The daemon discovers up to 50 open PRs requesting the authenticated user's review, optionally
filtered by repository. It de-duplicates by `repo#number@headRefOid` and stores queue state outside
the project under `${XDG_STATE_HOME:-$HOME/.local/state}/git-workflow/`. Completed-review SHAs are
stored in `.git-workflow/.review-watch-reviewed`.

See the [Review Watch guide](docs/REVIEW_WATCH.md) for notifications, queue schema, commands, and
posting behavior.

### Notifications

```yaml
notifications:
  # Notify when the main Claude Code or Codex turn finishes
  agentComplete: false

  # Notify for new submitted reviews on open PRs you authored
  prActivity: false

  # macOS system sound name used by all Git Workflow notifications
  sound: Glass
```

Both channels are explicit opt-ins. Agent completion uses the host's packaged `Stop` hook. PR
activity uses the daemon shared with Review Watch, queries up to 50 authored open PRs and their
latest 20 reviews, and establishes a silent first-run baseline. See the
[Notifications guide](docs/NOTIFICATIONS.md) for exact formats, local state, privacy, and manual
hook installation.

### Change Brief

```yaml
changeBrief:
  # Base directory for per-PR self-contained HTML files
  outputDir: .git-workflow/change-brief
```

PR `42` is written to `<outputDir>/pr-42/index.html`. The same resolved value is reported to the
user. Each file embeds its styles, scripts, diagrams, and screenshots and is validated to prevent
automatic external requests. See the [Change Brief guide](docs/CHANGE_BRIEF.md).

### QA

```yaml
qa:
  # Base URL for API tests
  apiBaseUrl: ${API_BASE_URL}

  # Directory for test plans
  testPlansDir: tests/qa

  # Directory for results
  resultsDir: tests/qa/results

  # Default timeout (seconds)
  timeout: 10

  # SQS queue for event verification
  sqsQueueUrl: ${SQS_QUEUE_URL}
```

### Release

```yaml
release:
  # Files to watch for special handling
  watchFiles:
    openapi: docs/openapi.json
    migrations: prisma/migrations/**/migration.sql
    schema: prisma/schema.prisma

  # Generate changelog from commits
  generateChangelog: true

  # Changelog categorization
  changelogCategories:
    - name: "Bug Fixes"
      prefixes: ["[Fix]", "[FIX]", "fix:"]
      emoji: "bug"
    - name: "Features"
      prefixes: ["[Feature]", "feat:"]
      emoji: "sparkles"
    - name: "Performance"
      prefixes: ["[Perf]", "perf:"]
      emoji: "zap"
```

## Environment Variables

Use `${VAR_NAME}` syntax for environment variables:

```yaml
qa:
  apiBaseUrl: ${API_BASE_URL}
  sqsQueueUrl: ${SQS_QUEUE_URL}
```

**Note:** Issue tracker authentication is handled by MCP servers and does not require environment variables. See [INSTALLATION.md](./INSTALLATION.md) for MCP setup.

## Configuration Priority

1. `.git-workflow/config.yaml` (canonical explicit config)
2. `.claude/config.yaml` (legacy read-only fallback)
3. Auto-detection (`package.json`, `pyproject.toml`, and similar files)
4. Sensible defaults

## Default Values

| Setting | Default |
|---------|---------|
| `packageManager` | Auto-detected |
| `workflow.type` | `staging` |
| `workflow.developmentBranch` | `staging` |
| `workflow.productionBranch` | `main` |
| `branches.feature` | `{type}/{ticket}-{description}` |
| `branches.release` | `release/{version}` |
| `commits.format` | `[{type}] {message} ({ticket})` |
| `commits.requireTicket` | `false` |
| `pullRequests.targetBranch` | `staging` |
| `issueTracker.type` | `auto` |
| `versioning.file` | `auto` |
| `attribution.enabled` | `false` |
| `review.postToGitHub` | `ask` |
| `review.maxDiffLines` | `3000` |
| `review.postEvent` | `auto` |
| `reviewWatch.enabled` | `false` |
| `reviewWatch.intervalSeconds` | `60` |
| `notifications.agentComplete` | `false` |
| `notifications.prActivity` | `false` |
| `notifications.sound` | `Glass` |
| `reviewWatch.linters` | `auto` |
| `reviewWatch.knownIssues` | `references/known-issues.md` |
| `changeBrief.outputDir` | `.git-workflow/change-brief` |
| `qa.timeout` | `10` |

## Hooks Configuration

The packaged commit-review and agent-completion hooks are registered by host-specific descriptors:
Claude loads `hooks/claude-hooks.json`, while Codex plugins discover `hooks/hooks.json`. The source
checkout includes project-local `.codex/hooks.json`. Commit review opts in through
`.git-workflow/git-workflow.local.md`; agent completion opts in through
`notifications.agentComplete`. Git Workflow does not modify global host settings.

Host-specific custom hooks can also be configured in host settings. For example, Claude supports `~/.claude/settings.json` (global) or `.claude/settings.json` (project):

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
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$CLAUDE_BASH_COMMAND\" | grep -q 'rm -rf'; then exit 1; fi"
          }
        ]
      }
    ]
  }
}
```

### Hook Types

| Hook | When | Can Block |
|------|------|-----------|
| `PostToolUse` | After a tool runs | No |
| `PreToolUse` | Before a tool runs | Yes (exit 1) |
| `SessionStart` | When session begins | No |
| `SessionEnd` | When session ends | No |
| `Notification` | On notifications | No |

See [HOOKS.md](./HOOKS.md) for complete documentation.

See `templates/settings.json.template` for a complete template.

## Stack-Specific Examples

See the `examples/` directory for complete configurations:

- [NestJS](./examples/nestjs/config.yaml)
- [Next.js](./examples/nextjs/config.yaml)
- [Python](./examples/python/config.yaml)
- [React Native](./examples/react-native/config.yaml)
- [Monorepo](./examples/monorepo/config.yaml)
