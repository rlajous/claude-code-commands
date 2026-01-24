# Configuration Reference

Complete reference for `.claude/config.yaml` configuration options.

## Configuration File

Create `.claude/config.yaml` in your project root. All settings are optional - commands use sensible defaults.

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

# Issue tracker integration
issueTracker:
  type: auto          # auto | linear | jira | github | none
  linear:
    apiKey: ${LINEAR_API_KEY}
  jira:
    baseUrl: https://company.atlassian.net
    apiToken: ${JIRA_API_TOKEN}
    email: ${JIRA_EMAIL}

# Version management
versioning:
  file: auto          # auto | package.json | pyproject.toml | VERSION | Cargo.toml

# AI Attribution (disabled by default)
attribution:
  enabled: false
  format: "Co-Authored-By: Claude <noreply@anthropic.com>"

# Testing commands
testing:
  unit: auto
  e2e: auto
  lint: auto
  typeCheck: auto
  build: auto

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

```yaml
issueTracker:
  # Tracker type
  # auto: Detect from ticket format
  # linear: Linear.app
  # jira: Atlassian Jira
  # github: GitHub Issues
  # none: Disable integration
  type: auto

  # Linear settings
  linear:
    apiKey: ${LINEAR_API_KEY}

  # Jira settings
  jira:
    baseUrl: https://company.atlassian.net
    apiToken: ${JIRA_API_TOKEN}
    email: ${JIRA_EMAIL}
```

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
  # Add AI co-author to commits (default: false)
  enabled: false

  # Attribution format
  format: "Co-Authored-By: Claude <noreply@anthropic.com>"
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
issueTracker:
  linear:
    apiKey: ${LINEAR_API_KEY}

qa:
  apiBaseUrl: ${API_BASE_URL}
```

## Configuration Priority

1. `.claude/config.yaml` (explicit config)
2. Auto-detection (package.json, pyproject.toml, etc.)
3. Sensible defaults

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
| `qa.timeout` | `10` |

## Hooks Configuration

Hooks are configured separately in `settings.json` (not `config.yaml`).

Location: `~/.claude/settings.json` (global) or `.claude/settings.json` (project)

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
