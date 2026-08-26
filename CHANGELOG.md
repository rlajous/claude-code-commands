# Changelog

## 2.5.2

- Resolve deterministic resources from each loaded skill directory so installed and checkout-local
  Codex skills work without `PLUGIN_ROOT` or `CLAUDE_PLUGIN_ROOT`.
- Keep root helper commands as compatibility wrappers while colocating watcher, review, HTML,
  status, SARIF, and synchronization implementations with their owning skills.
- Add checkout-local Codex discovery plus `review-watch --doctor` and `--daemon-command`.
- Harden notification arguments, embedded status JSON, HTML/CSP validation, watcher ledger order,
  and synchronization prune bookkeeping.
- Make change briefs decision-oriented and readable in under 10 minutes, with business rules,
  diagrams, conditional UI/mobile screenshots, API cURL exchanges, risks, and evidence gaps.
- Include repository, PR number, author, and title in review-watch notifications; fetch live queue
  metadata with GraphQL and keep validation runs from sending desktop test notifications.

## 2.5.1

- Enforce `reviewWatch.enabled`, daemon interval, notification sound, linter, known-issue, and safe review-event configuration.
- Add tested review-event selection for blocking, clean, comment-only, and self-authored pull requests.
- Harden change-brief HTML with a restrictive CSP and parser-based zero-network validation.

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
