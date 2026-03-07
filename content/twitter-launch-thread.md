# Twitter/X Launch Thread

## Main Launch Thread (6 tweets)

### Tweet 1 (Hook)
```
I just open-sourced my entire Claude Code workflow.

10 slash commands that automate:
- Feature branches from tickets
- Conventional commits
- PRs with full descriptions
- Releases with changelogs
- QA test plans

Zero config needed. Works with any stack.

🧵
```

### Tweet 2 (The Problem)
```
The problem: AI coding assistants are great at writing code.

But the workflow around it?
- Creating branches
- Writing commit messages
- Making PRs
- Managing releases

Still manual. Still slow. Still inconsistent.
```

### Tweet 3 (The Solution)
```
The solution: Slash commands that handle everything.

/start TICKET-123 → Creates feature branch, fetches ticket context
/commit → Stages changes, writes conventional commit
/finish → Pushes and creates PR with full description
/release → Version bump, changelog, PR to main

That's it. Ticket to production.
```

### Tweet 4 (TDD Feature)
```
My favorite command: /tdd

It implements Test-Driven Development automatically:

RED → Writes failing tests first
GREEN → Implements until tests pass
REFACTOR → Cleans up the code

AI that enforces testing discipline. Finally.
```

### Tweet 5 (Stack Support)
```
Works with everything:

- Node.js (npm, pnpm, yarn, bun)
- Python (pip, poetry, uv)
- Rust, Go, and more

Auto-detects your package manager, version files, and testing commands.

One command set for polyglot teams.
```

### Tweet 6 (CTA)
```
Get started in 2 minutes:

git clone https://github.com/rlajous/claude-code-commands
cp -r claude-code-commands/.claude your-project/

Then run /setup to configure.

MIT licensed. No dependencies. Just better workflows.

github.com/rlajous/claude-code-commands
```

---

## Standalone Tweets (Alternative angles)

### Angle 1 - Speed
```
My PR workflow before Claude Code Commands: 30 minutes

My PR workflow now:

/start TICKET-123
[write code]
/commit
/finish

2 minutes. PR created with full description, linked ticket, and proper labels.
```

### Angle 2 - TDD
```
TDD is hard to stick to.

So I made AI do it.

/tdd automatically:
1. Writes failing tests (RED)
2. Implements until they pass (GREEN)
3. Refactors the code (REFACTOR)

No more "I'll add tests later" lies.

Open source: github.com/rlajous/claude-code-commands
```

### Angle 3 - Issue Tracker Integration
```
"But my tickets are in Linear/Jira/GitHub..."

Claude Code Commands integrates with all of them via MCP servers.

/start LINEAR-123 → Fetches ticket title, description, acceptance criteria
/finish → Links PR back to ticket automatically

No more copy-pasting context.
```

### Angle 4 - Releases
```
Release day used to be stressful.

Now it's one command:

/release

- Creates release branch
- Bumps version (semver)
- Generates changelog from commits
- Creates PR to main
- Validates tests pass

Then /release-notes generates the GitHub release.
```
