---
name: notifications
description: Configure and diagnose opt-in desktop notifications for completed Claude Code or Codex turns and new reviews on pull requests you authored. Use when the user asks to enable agent-finished alerts, watch approvals or requested changes on their PRs, inspect notification configuration, or get the background daemon command.
allowed-tools: Read, Grep, Glob, Bash
---

# Git Workflow Notifications

Resolve `{SKILL_DIR}` to the absolute, physical directory containing this loaded `SKILL.md`. If the
host cannot expose the path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, only to locate
`skills/notifications/SKILL.md`. Verify every requested resource exists. Never substitute an empty
variable or silently fall back to `/scripts`.

## Commands

- `--doctor` → run `bash "{SKILL_DIR}/scripts/notification-tools.sh" --doctor`, report the output,
  and exit. The check must not query pull requests, create state, or emit a desktop notification.
- `--daemon-command` → run
  `bash "{SKILL_DIR}/scripts/notification-tools.sh" --daemon-command`, print the absolute command
  unchanged, and exit.
- No argument → show the resolved configuration with
  `python3 "{SKILL_DIR}/scripts/notification_config.py"`, explain which channels are enabled, and
  print the daemon command when PR activity or review requests are enabled.

The daemon is required for GitHub activity. Agent-complete notifications use the plugin's `Stop`
hook and do not require the daemon.

## Configuration

Read `.git-workflow/config.yaml`, then the legacy `.claude/config.yaml` fallback:

```yaml
notifications:
  agentComplete: false
  prActivity: false
  sound: Glass
```

Both channels are opt-in. `notifications.sound` applies to all Git Workflow notifications. When it
is absent, accept `reviewWatch.sound` as a compatibility fallback, then use `Glass`.

## Expected events

Agent completion announces only the main turn. Do not add `SubagentStop` or failure alerts. GitHub
activity announces submitted `APPROVED`, `CHANGES_REQUESTED`, and `COMMENTED` reviews on open PRs
authored by the authenticated user. General PR comments, CI, merges, dismissals, and commits are
outside this workflow.

Notification failures are best effort and must never fail a turn or review workflow. Do not read or
persist full transcripts; the completion adapter uses only the first useful line of
`last_assistant_message` and stores only a deduplication digest.

## Runtime compatibility

Claude invokes this skill as `/notifications`; Codex invokes it as `$notifications`. Keep shared
behavior host-neutral. Claude loads `hooks/claude-hooks.json`, Codex plugins load `hooks/hooks.json`,
and a source checkout exposes the project hook through `.codex/hooks.json`.
