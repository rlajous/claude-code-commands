# Git Workflow hooks

Git Workflow ships one opt-in hook that notices successful `git commit` and `git push` commands and provides the resulting diff to the active host for review.

## Host registration

The shared implementation is `hooks/review-commit.sh`.

| Host | Registration | Output |
| --- | --- | --- |
| Claude Code | `hooks/claude-hooks.json`, selected by the Claude manifest | Plain review context with Claude's asynchronous re-wake behavior |
| Codex | `hooks/hooks.json`, discovered by the Codex plugin | Synchronous JSON containing `hookSpecificOutput.additionalContext` |

Both registrations use `PostToolUse` and match Bash execution. Claude uses asynchronous re-wake behavior; Codex runs synchronously for compatibility with supported Codex clients. The script parses the hook payload and exits without output unless the executed command contains `git commit` or `git push`.

## Enable it

The hook is disabled by default. Add this project-local file:

```yaml
# .git-workflow/git-workflow.local.md
review-on-commit: true
```

The neutral path is checked first. For compatibility, the script falls back to `.claude/git-workflow.local.md` when the canonical file is absent. Restart or reload the host after changing plugin hook registration.

To disable the behavior, set the value to `false` or remove the opt-in file.

## What it does

After an eligible command, the script:

1. Reads the hook JSON from standard input and extracts the Bash command.
2. Verifies that project opt-in is enabled.
3. Resolves the current commit SHA.
4. Checks `.git-workflow/.git-workflow-reviewed-shas` to avoid reviewing the same SHA twice.
5. Builds a bounded diff for the new commit or push state.
6. Produces the host-specific output format successfully.
7. Records the SHA only after useful review context was delivered, keeping failures retryable.

The reviewed-SHA ledger is local generated state and should be git-ignored. A legacy `.claude/.git-workflow-reviewed-shas` ledger is read for duplicate suppression, but new entries are written only to `.git-workflow/`.

## Review behavior

The additional context asks the main workflow to inspect the bounded diff and use `pr-reviewer` for non-trivial changes. The review path may fan out through `$review` or `/review`; it must wait for all requested specialist reports and must not modify source files merely to perform a review.

Large diffs are truncated deliberately so a background hook cannot flood the next agent turn. The message identifies truncation and encourages an explicit full review when needed.

## Safety properties

- Disabled unless the repository opts in
- Ignores unrelated Bash commands
- Does not execute the detected commit or push command itself
- Does not modify tracked source files
- Suppresses duplicate SHAs, including those present in the legacy ledger
- Reports malformed hook input and missing runtime dependencies as actionable errors; non-Git directories remain no-op paths
- Keeps hook stdout machine-readable under Codex

## Manual testing

From a temporary Git repository containing at least one commit:

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | hooks/review-commit.sh --host codex

printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' \
  | hooks/review-commit.sh --host codex
```

The first call emits nothing. The second also emits nothing until `.git-workflow/git-workflow.local.md` enables the feature. With opt-in enabled, Codex output must be valid JSON and include `hookSpecificOutput.additionalContext`.

Run the repository's automated hook checks with:

```bash
bash scripts/test-review-hook.sh
```

## Troubleshooting

### Hook never runs

- Confirm the plugin is enabled and start a fresh host session.
- Confirm the host loaded the correct registration file.
- Verify `.git-workflow/git-workflow.local.md` contains `review-on-commit: true`.
- Verify the Bash payload actually contains `git commit` or `git push`.
- Verify Python 3 is available; the hook uses it for input parsing and Codex JSON output.

### Codex reports invalid hook output

Run the script manually and pipe the result through `python3 -m json.tool`. Diagnostic output must go to stderr; successful Codex context is emitted as one JSON object on stdout.

### A commit is skipped

Inspect `.git-workflow/.git-workflow-reviewed-shas` and the legacy fallback ledger. Removing the current SHA permits a new review, but normally the ledger should be left intact to prevent repetition.

### Package root is unresolved

Skill instructions resolve bundled resources from the loaded `SKILL.md` path. Hook registration is
host-specific and still receives its package context from the host. If a hook command cannot resolve
its package, reload the installed plugin and inspect the matching registration JSON.
