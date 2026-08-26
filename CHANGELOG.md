# Changelog

## 2.4.0

- Added native Codex plugin packaging for the same 17 workflow skills shipped to Claude Code.
- Added eight generated, project-scoped Codex agents while retaining the canonical Markdown agent definitions.
- Moved shared configuration and generated state to `.git-workflow/`, with read-only fallback support for legacy `.claude/` files from the `2.3.0` baseline.
- Added safe setup and update synchronization with host selection, dry runs, customization protection, explicit pruning, managed-file ownership, and local-directory or explicit Git-URL sources.
- Added host-specific commit-review delivery: asynchronous re-wake for Claude Code and synchronous `additionalContext` output for Codex compatibility.
- Hardened review ranges, hook retry behavior, status warnings, manifest validation, agent generation, and release validation.

Requirements for repository workflows are Git, Bash, and the GitHub CLI for GitHub operations. Setup, update, and HTML status generation require Node.js; hook input and Codex output handling require Python 3; synchronization previews require `diff`.
