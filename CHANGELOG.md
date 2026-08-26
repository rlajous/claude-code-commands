# Changelog

## 2.5.0

- Added the `review-watch` auto-reviewer: a console daemon (`scripts/review-watch.sh`) that listens for pull requests requesting your review and pings you with a local sound and desktop notification (`scripts/notify.sh`), plus a `review-watch` skill that reviews each PR in a loop.
- The `review-watch` skill runs cheap deterministic checks first (project linters + a growing `references/known-issues.md` ruleset) and only escalates to the full review fan-out when those pass, posting `REQUEST_CHANGES` on problems and `APPROVE` when clean.
- Added the `change-brief` skill: generates a self-contained human-readable HTML explainer of a change (Problem / Root cause / Fix / Verification, before/after), written to `.git-workflow/change-brief/`. Produced automatically when a watched PR passes.
- The `review` skill can now post `REQUEST_CHANGES`/`APPROVE`/`COMMENT` reviews (previously `COMMENT` only), with a self-review guard.
- Opt-in via `reviewWatch.enabled` in `.git-workflow/config.yaml`.

## 2.4.0

- Added native Codex plugin packaging for the same 17 workflow skills shipped to Claude Code.
- Added eight generated, project-scoped Codex agents while retaining the canonical Markdown agent definitions.
- Moved shared configuration and generated state to `.git-workflow/`, with read-only fallback support for legacy `.claude/` files from the `2.3.0` baseline.
- Added safe setup and update synchronization with host selection, dry runs, customization protection, explicit pruning, managed-file ownership, and local-directory or explicit Git-URL sources.
- Added host-specific commit-review delivery: asynchronous re-wake for Claude Code and synchronous `additionalContext` output for Codex compatibility.
- Hardened review ranges, hook retry behavior, status warnings, manifest validation, agent generation, and release validation.

Requirements for repository workflows are Git, Bash, and the GitHub CLI for GitHub operations. Setup, update, and HTML status generation require Node.js; hook input and Codex output handling require Python 3; synchronization previews require `diff`.
