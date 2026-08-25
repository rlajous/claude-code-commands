# I Automated My Entire Git Workflow with AI - Here's How

## The Problem Nobody Talks About

AI coding assistants have gotten remarkably good at writing code. Claude Code and Codex can implement features, fix bugs, and write tests.

But here's what I noticed: the code is only half the job.

Every feature still requires:
- Creating a branch with the right naming convention
- Fetching context from the ticket
- Writing meaningful commit messages
- Creating PRs with proper descriptions
- Managing releases with changelogs
- Keeping branches in sync

These tasks eat hours every week. They're repetitive, error-prone, and frankly... boring.

So I built a solution.

## Introducing Git Workflow

Over the past few months, I've developed a package of 17 skills that automates the entire development workflow in both Claude Code and Codex. Today I'm open-sourcing it.

Claude invokes a skill as `/name`; Codex uses `$name`. The examples below use Claude syntax, but the same workflows are available in Codex by replacing the leading slash with a dollar sign.

**The Core Workflow:**
```
/start TICKET-123    → Create feature branch, fetch ticket context
[write your code]
/commit              → Stage changes, conventional commit message
/finish              → Push and create PR with full description
```

That's it. From ticket to pull request in minutes, not hours.

## The 17 Skills

Beyond the core workflow, Git Workflow includes setup and updates, TDD, PR review, release notes, synchronization, QA planning and execution, RFCs, review requests, standups, status, and safe cleanup of gone branches. Eight specialized agents support review, release validation, QA execution, and version analysis.

### `/start` - Begin with Context

Instead of manually creating branches and looking up ticket details, `/start TICKET-123` does it all:

- Creates a branch following your naming conventions
- Fetches the ticket title, description, and acceptance criteria
- Saves context for later use in commits and PRs

Works with Linear, Jira, and GitHub Issues.

### `/tdd` - AI-Enforced Test-Driven Development

This is my favorite command. `/tdd` implements the RED-GREEN-REFACTOR cycle automatically:

1. **RED**: Writes failing tests based on acceptance criteria
2. **GREEN**: Implements code until all tests pass
3. **REFACTOR**: Cleans up without breaking tests

No more "I'll add tests later." The AI enforces discipline.

### `/commit` - Conventional Commits, Every Time

Tired of inconsistent commit messages? `/commit` analyzes your changes and generates proper conventional commits:

```
feat(auth): add OAuth2 provider support

- Implement Google and GitHub OAuth flows
- Add token refresh logic
- Update user model with provider fields
```

Follows whatever format your team prefers.

### `/finish` - PRs That Actually Describe the Changes

`/finish` creates pull requests with:
- Summary of all changes
- Screenshots (if applicable)
- Test plan based on what you modified
- Links to the original ticket

No more "Updated stuff" PR descriptions.

### `/release` - One-Command Releases

When it's time to ship:

```
/release
```

This single command:
- Creates a release branch
- Bumps the version (following semver)
- Generates a changelog from commits
- Creates a PR to main
- Validates all tests pass

Then `/release-notes` generates the GitHub release with categorized changes.

## Framework Agnostic

The commands work with any tech stack:

- **Node.js**: npm, pnpm, yarn, bun
- **Python**: pip, poetry, uv
- **Rust**: cargo
- **Go**: go mod

They auto-detect your package manager, version files, and testing commands. One command set for polyglot teams.

## Zero Config, Deep Customization

Here's what I'm most proud of: **you don't need any configuration to start**.

Just install the commands and go. They use sensible defaults that work for most projects.

But when you need customization, everything is configurable via `.git-workflow/config.yaml`:

- Branch naming patterns
- Commit message formats
- PR templates
- Release workflows
- Issue tracker integration

Start simple, customize as needed.

## The Workflow in Practice

Here's my typical day now:

**Morning**: Product assigns me TICKET-123
```
/start TICKET-123
```
Branch created, ticket context loaded.

**Development**: I write code with Claude Code or Codex

**Ready to commit**:
```
/commit
```
Conventional commit created automatically.

**Ready for review**:
```
/finish
```
PR created with full description, linked to ticket.

**Release day**:
```
/release
/release-notes
/sync
```
Version bumped, changelog generated, release published, branches synced.

Total time spent on Git workflow: maybe 5 minutes across the entire feature lifecycle.

## Getting Started

Install for Claude Code from the marketplace:
```text
/plugin marketplace add rlajous/claude-code-commands
/plugin install git-workflow@git-workflow-marketplace
/git-workflow:setup
```

For a manual Claude project copy, copy `skills/`, `agents/`, and `references/` into `.claude/`, then run `/setup`.

For Codex, install or load the repository as a plugin and run:
```text
$setup
```

The Codex plugin exposes all 17 skills and installs eight project agents into `.codex/agents/`. Both hosts share `.git-workflow/config.yaml` and generated state, while legacy `.claude/` state remains a read-only fallback.

To explore the source locally:
```bash
git clone https://github.com/rlajous/claude-code-commands
```

Linear and Jira connect through the active host's MCP configuration. GitHub operations use the GitHub CLI. Setup also configures branch naming conventions and other workflow options.

No dependencies. No accounts to create. Just better workflows.

## What's Next

This is v2.4.0, with native Claude and Codex packaging, but there's more coming:
- More issue tracker integrations
- Customizable PR templates
- Team workflow presets
- CI/CD integration commands

The code is MIT licensed. Contributions welcome.

**Repository**: [github.com/rlajous/claude-code-commands](https://github.com/rlajous/claude-code-commands)

---

*If you found this useful, share it with a developer friend who's still writing commit messages manually.*
