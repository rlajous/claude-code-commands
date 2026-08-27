---
name: review-watch
description: Review pull requests that requested your review, in a loop until clean. Runs cheap deterministic checks (linters + a known-issues ruleset) first, then the full review fan-out, posts REQUEST_CHANGES when it finds problems, and APPROVE plus a human-readable change brief when the PR is clean. Use when the user asks to "review the PRs waiting on me", "auto-review", "watch for review requests", "drain the review queue", or passes a PR URL to review-and-decide.
argument-hint: "[pr-url-or-number] [--drain] [--comment-only] [--doctor] [--daemon-command]"
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are the worker side of the review-watch tool. The skill-local `scripts/review-watch.sh` daemon listens for PRs where your review was requested and pings you; this skill does the actual review and decides whether to request changes or approve. Goal: **loop a PR until it is clean**, cheaply. Follow each step in order.

## Step 1: Parse Arguments and Pick Targets

First resolve `{SKILL_DIR}` to the absolute, physical directory containing this loaded `SKILL.md`.
If the host cannot expose the loaded path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, only to
locate `skills/review-watch/SKILL.md`. Verify requested resources exist. Never substitute an empty
variable or silently fall back to `/scripts`.

- `--doctor` → run `bash "{SKILL_DIR}/scripts/review-watch-tools.sh" --doctor`, report its output,
  and exit. This checks paths, dependencies, configuration, and `gh` authentication without
  querying PRs, publishing reviews, or changing GitHub state.
- `--daemon-command` → run
  `bash "{SKILL_DIR}/scripts/review-watch-tools.sh" --daemon-command`, print the absolute command
  unchanged so the user can paste it into another terminal, and exit.

- A PR URL or number → review just that PR.
- `--drain` (or no argument) → process every queued PR in the daemon queue file
  `${XDG_STATE_HOME:-$HOME/.local/state}/git-workflow/review-watch-queue.jsonl` (dedupe by `repo#number@headRefOid`; newest entry per PR wins). Remove entries as you finish them.
  New entries include the nullable PR-author login as `author`; accept older entries where that field
  is absent and fetch the author with the PR metadata below.
- `--comment-only` → never post REQUEST_CHANGES/APPROVE, only a COMMENT review (safe mode).

For each target resolve `{owner}/{repo}` and PR number (parse from the URL, or use the current repo for a bare number).

## Step 2: Skip Already-Reviewed Head SHAs

Read the reviewed-SHA ledger `.git-workflow/.review-watch-reviewed` (legacy fallback `.claude/.review-watch-reviewed`). Each line is `repo#number@headRefOid`. Fetch the PR head SHA:

```bash
gh pr view {PR} --repo {owner}/{repo} --json number,title,url,author,isDraft,baseRefOid,headRefOid,files,additions,deletions
```

If `repo#number@headRefOid` is already in the ledger, skip this PR (nothing new since the last review). If the PR `isDraft`, skip and note it.

**Self-review guard:** GitHub forbids REQUEST_CHANGES/APPROVE on your own PR. If the PR author is you (`gh api user --jq .login`), operate in `--comment-only` mode for this PR.

## Step 3: Get the Diff

```bash
gh pr diff {PR} --repo {owner}/{repo}
```

Note the changed file list and languages. If the diff exceeds `review.maxDiffLines` (default 3000), work from the file list and read files individually.

## Step 4: Tier 1 — Deterministic Checks (cheap, no model reasoning)

Run the fast, mechanical checks first so obvious problems cost nothing.

Resolve configuration once from `.git-workflow/config.yaml`, then the legacy
`.claude/config.yaml` fallback. If neither exists, use these defaults:
`reviewWatch.enabled=false`, `reviewWatch.linters=auto`,
`reviewWatch.knownIssues=references/known-issues.md`, and `review.postEvent=auto`.
Stop without reviewing unless `reviewWatch.enabled` is exactly `true`; an explicit
`--comment-only` changes posting behavior but does not bypass this opt-in gate.

**a) Project linters (only if the repo is checked out locally with deps).** Use the resolved
`reviewWatch.linters`. When it is `auto`, auto-detect and run against the changed files; when it is
an explicit command, run that exact project-owned command:

- JS/TS: `npx eslint <changed>` , `npx tsc --noEmit`
- CSS/SCSS: `npx stylelint <changed css>`
- Python: `ruff check <changed>` / `flake8`
- Others: the project's configured lint command (`.git-workflow/config.yaml` → `testing.lint`).

If the repo is not available locally (a PR on someone else's repo you have not cloned), skip the linters and note it — Tier 2 still covers logic from the diff.

**b) Known-issues ruleset.** Resolve `reviewWatch.knownIssues` as follows: an absolute path is used
as-is; for a relative path, prefer a matching project-root file, otherwise resolve it under
`{SKILL_DIR}`. If the setting is absent, use the bundled
`{SKILL_DIR}/references/known-issues.md`. Read its grep-style patterns and scan only changed diff lines. These
are the "errors we already know": stray `console.log`, `debugger`, CSS `!important` abuse, inline
styles, shipped `TODO/FIXME`, hard-coded colors, TS `any`, etc. If the configured file is missing,
stop with the resolved path instead of silently dropping the deterministic checks.

Collect all Tier-1 findings with file, line, and the rule that fired. Anything at severity `error`/BLOCKING/HIGH is a **blocker**.

**If Tier 1 found blockers → go straight to Step 6 and post REQUEST_CHANGES with those findings. Skip Tier 2** (do not spend the expensive review when there are already known errors to fix). This is the cost gate.

## Step 5: Tier 2 — Full Review Fan-out (only when Tier 1 is clean)

Run the standard review: delegate, through the active host's subagent mechanism, to the specialized reviewers used by the `review` skill (`pr-reviewer` always; `silent-failure-hunter`, `type-design-analyzer`, `pr-test-analyzer`, `comment-analyzer` by changed-file type), in parallel. Hand each the PR number/repo, `baseRefOid` as `BASE_SHA`, `headRefOid` as `HEAD_SHA`, the changed-file list, and the diff.

Aggregate and de-duplicate their findings. Keep only findings with **confidence ≥ 80** and drop the false-positive classes (pre-existing, linter-catchable, intentionally-silenced, formatter-style, speculative) — the same bar as the `review` skill. Assign each survivor a severity (BLOCKING / HIGH / MEDIUM / LOW).

## Step 6: Decide and Post

Combine Tier-1 blockers and Tier-2 findings. Resolve `review.postEvent` from the same config
(`auto` by default). Set `{HAS_BLOCKING}` to `true` when any BLOCKING/HIGH finding survived and set
`{SELF_AUTHORED_FLAG}` to `--self-authored` only for the self-review case. Determine the event with
the package's tested resolver:

```bash
REVIEW_EVENT="$(bash "{SKILL_DIR}/../review/scripts/review-event.sh" \
  --has-blocking {HAS_BLOCKING} {SELF_AUTHORED_FLAG})"
```

If `--comment-only` was passed, force `REVIEW_EVENT=COMMENT` after resolution. Never infer a more
permissive event when the resolver reports invalid configuration.

- **`REVIEW_EVENT=REQUEST_CHANGES`.** Build the review body: a one-line verdict, then each finding as `severity — file permalink — what is wrong — suggested fix`, using SHA permalinks (`https://github.com/{owner}/{repo}/blob/{headRefOid}/{path}#L{line}`, literal). Post:

  ```bash
  gh api "repos/{owner}/{repo}/pulls/{PR}/reviews" --method POST \
    -f body="$(cat <<'REVIEW_EOF'
  {REVIEW_BODY}
  REVIEW_EOF
  )" -f event="$REVIEW_EVENT"
  ```

- **No BLOCKING/HIGH (clean) → `APPROVE` or `COMMENT` as resolved.** Post the same way with
  `-f event="$REVIEW_EVENT"`, a short "looks good" body plus any remaining LOW/MEDIUM notes. A clean
  result triggers the human-readable change brief (Step 7) and ping even when safe mode or
  self-authorship forces the GitHub event to `COMMENT`.

Respect `review.postToGitHub` (`ask` | `always` | `never`, default `ask`): when `ask`, show the drafted review and confirm through the host's user-input mechanism before posting. Truncate bodies over ~65,000 characters.

## Step 7: On Clean — Generate the Change Brief and Ping

When the PR is clean (`HAS_BLOCKING=false`, whether the posted event is `APPROVE` or `COMMENT`):

- Generate the human-facing HTML decision brief by following `/change-brief {PR}` in Claude Code or
  `$change-brief {PR}` in Codex. Output goes to `.git-workflow/change-brief/pr-{PR}/index.html`.
- Ping the human that it is ready:

  ```bash
  bash "{SKILL_DIR}/scripts/notify.sh" \
    "{owner}/{repo} · PR #{PR}" \
    "{AUTHOR_LABEL} — Ready for merge: {title}"
  ```

  Resolve `{AUTHOR_LABEL}` as `@{author.login}`, or `unknown author` when GitHub returns no author.
  This matches the daemon's initial review-request notification, which uses the same title and
  `{AUTHOR_LABEL} — {title}` as its message.

## Step 8: Record and Loop

Append `repo#number@headRefOid` to `.git-workflow/.review-watch-reviewed` so this exact head SHA is not reviewed again. Remove the PR from the daemon queue file if you were draining it.

The **loop is head-SHA driven**: when the author pushes a fix, the daemon detects the new head SHA and re-queues the PR; running this skill again reviews only the new SHA. Repeat REQUEST_CHANGES → author fixes → re-review until a round posts APPROVE. Never re-review an unchanged SHA (the ledger prevents it).

## Step 9: Report

Print a compact summary per PR: verdict (REQUEST_CHANGES / APPROVED / COMMENTED), Tier-1 vs Tier-2 finding counts, whether a change brief was written, and the PR URL.

## Configuration Reference

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `reviewWatch.intervalSeconds` | `60` | Daemon poll interval |
| `notifications.sound` | `Glass` | Shared notification sound name (`reviewWatch.sound` remains a fallback) |
| `reviewWatch.linters` | `auto` | `auto`-detect, or an explicit lint command |
| `reviewWatch.knownIssues` | `references/known-issues.md` | Deterministic ruleset path |
| `review.postToGitHub` | `ask` | `ask` \| `always` \| `never` |
| `review.postEvent` | `auto` | `auto` (derive REQUEST_CHANGES/APPROVE) \| `comment` |

The daemon implementation and generic notifier are owned by the sibling `notifications` skill;
the skill-local scripts here are compatibility wrappers. Enabling `notifications.prActivity`
adds authored-PR review events to the same GraphQL poll without duplicating the daemon.

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `gh` unauthenticated | Stop with a hint to run `gh auth login` |
| Repo not available locally | Skip Tier-1 linters, run Tier-2 from the diff, note it |
| PR authored by you | Fall back to COMMENT (cannot self-approve/request-changes) |
| Head SHA already reviewed | Skip; nothing new |
| Node unavailable (change brief) | Post the approval, skip the HTML, note it |
