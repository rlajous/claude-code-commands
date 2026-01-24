# Hooks Reference

Hooks allow you to run custom commands at specific points during Claude Code's execution. This enables automation, validation, and integration with your development workflow.

**Official Documentation**: https://code.claude.com/docs/en/hooks

## Overview

Hooks are configured in your `settings.json` file and can run:

- **Before** a tool is used (PreToolUse) - Can block execution
- **After** a tool is used (PostToolUse) - For cleanup or validation
- **At session start/end** (SessionStart/SessionEnd) - For setup and logging
- **On notifications** (Notification) - For alerts

## Configuration

Hooks are configured in `~/.claude/settings.json` (global) or `.claude/settings.json` (project).

```json
{
  "hooks": {
    "PostToolUse": [...],
    "PreToolUse": [...],
    "SessionStart": [...],
    "SessionEnd": [...],
    "Notification": [...]
  }
}
```

See `templates/settings.json.template` for a complete example.

## Hook Types

### PostToolUse

Runs after a tool completes. Useful for:

- Auto-formatting code after edits
- Running linters
- Triggering builds
- Logging changes

```json
{
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
```

### PreToolUse

Runs before a tool executes. Can **block** execution by returning non-zero exit code.

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "if echo \"$CLAUDE_BASH_COMMAND\" | grep -q 'rm -rf /'; then echo 'BLOCKED' && exit 1; fi"
        }
      ]
    }
  ]
}
```

### SessionStart

Runs when a Claude Code session begins.

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "echo 'Session started' >> .claude/session.log"
        }
      ]
    }
  ]
}
```

### SessionEnd

Runs when a Claude Code session ends.

```json
{
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "echo 'Session ended' >> .claude/session.log"
        }
      ]
    }
  ]
}
```

### Notification

Runs when Claude sends notifications.

```json
{
  "Notification": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "osascript -e 'display notification \"$CLAUDE_NOTIFICATION\"'"
        }
      ]
    }
  ]
}
```

## Hook Structure

Each hook entry has:

| Field | Type | Description |
|-------|------|-------------|
| `matcher` | string | Regex pattern to match tool names |
| `hooks` | array | Array of hook definitions |

Each hook definition has:

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Currently only `"command"` is supported |
| `command` | string | Shell command to execute |

## Environment Variables

Hooks have access to special environment variables:

| Variable | Description | Available In |
|----------|-------------|--------------|
| `$CLAUDE_FILE_PATH` | Path of file being modified | Write, Edit |
| `$CLAUDE_BASH_COMMAND` | Bash command being run | Bash (PreToolUse) |
| `$CLAUDE_NOTIFICATION` | Notification message | Notification |

## Common Use Cases

### Auto-Format on Save

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "prettier --write \"$CLAUDE_FILE_PATH\" 2>/dev/null || true"
        }
      ]
    }
  ]
}
```

### Prevent Dangerous Commands

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "if echo \"$CLAUDE_BASH_COMMAND\" | grep -qE 'git push.*--force'; then echo 'BLOCK: Force push not allowed' && exit 1; fi"
        }
      ]
    }
  ]
}
```

### Type Check After TypeScript Changes

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "[[ $CLAUDE_FILE_PATH == *.ts ]] && npx tsc --noEmit 2>/dev/null || true"
        }
      ]
    }
  ]
}
```

### Run Tests After Code Changes

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "[[ $CLAUDE_FILE_PATH == *.test.* ]] && npm test -- --findRelatedTests \"$CLAUDE_FILE_PATH\" || true"
        }
      ]
    }
  ]
}
```

### Notify on Task Completion (macOS)

```json
{
  "Notification": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "osascript -e 'display notification \"Task completed\" with title \"Claude Code\"'"
        }
      ]
    }
  ]
}
```

### Log All Sessions

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "echo \"$(date): Session started in $(pwd)\" >> ~/.claude/sessions.log"
        }
      ]
    }
  ],
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "echo \"$(date): Session ended\" >> ~/.claude/sessions.log"
        }
      ]
    }
  ]
}
```

### Prevent Commits to Main

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "if echo \"$CLAUDE_BASH_COMMAND\" | grep -qE 'git commit' && git branch --show-current | grep -qE '^(main|master)$'; then echo 'BLOCK: Use feature branches' && exit 1; fi"
        }
      ]
    }
  ]
}
```

## Best Practices

### 1. Use Error Suppression

Add `|| true` or `2>/dev/null` to prevent hooks from blocking on non-critical failures:

```json
{
  "command": "npm run lint:fix -- $CLAUDE_FILE_PATH 2>/dev/null || true"
}
```

### 2. Be Specific with Matchers

Use specific tool matchers instead of `.*` when possible:

```json
{
  "matcher": "Write|Edit",  // Better than ".*"
  "hooks": [...]
}
```

### 3. Keep Hooks Fast

Hooks run synchronously. Slow hooks will impact Claude's responsiveness:

- Avoid network calls in PreToolUse hooks
- Use background processes for slow operations
- Cache results when possible

### 4. Test Hooks Thoroughly

Test hooks in a safe environment before deploying:

```bash
# Test a hook command manually
CLAUDE_FILE_PATH="test.ts" npm run lint:fix -- $CLAUDE_FILE_PATH
```

### 5. Use Clear Block Messages

When blocking in PreToolUse, provide clear feedback:

```json
{
  "command": "echo 'BLOCK: Reason for blocking' && exit 1"
}
```

## Troubleshooting

### Hook Not Running

1. Check `matcher` regex matches the tool name
2. Verify command syntax is correct
3. Check file permissions

### Hook Blocking Unexpectedly

1. Check exit codes in your command
2. Add `|| true` to allow non-zero exits
3. Review the matcher pattern

### Session Hooks Not Firing

1. Ensure `settings.json` is in the correct location
2. Check JSON syntax is valid
3. Restart Claude Code

## Template

See `templates/settings.json.template` for a complete configuration template with common hooks pre-configured.
