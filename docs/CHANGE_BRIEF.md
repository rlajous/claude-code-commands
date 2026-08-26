# Change Brief

Change Brief turns a pull request into one self-contained HTML decision document that a product or
engineering reader can understand in less than 10 minutes. It explains behavior and risk rather
than repeating the complete diff.

## Example

[Download the self-contained PR #23 example](examples/change-brief-pr-23.html) and open it directly
in a browser. The public example is an English snapshot of PR #23 at commit `e49c47b`; it does not
change as later documentation commits are added to the PR.

[![Top of the PR #23 change brief, including its summary, business rules, workflow diagram, and real notification evidence.](assets/change-brief-pr-23.png)](examples/change-brief-pr-23.html)

The example includes a business-rule table, an accessible inline SVG flow, real macOS notification
evidence, focused before/after code, delivery risks, rollback, and verification results.

## Generate a brief

Pass a PR number or URL, or omit it to use the current branch's open PR:

```text
/change-brief 42                                      # Claude Code
/change-brief https://github.com/owner/repo/pull/42   # Claude Code

$change-brief 42                                      # Codex
$change-brief https://github.com/owner/repo/pull/42   # Codex
```

The default output is:

```text
.git-workflow/change-brief/pr-42/index.html
```

Open that file directly in a browser. It has no companion asset directory and can be copied or
deleted as one unit.

## What the reader gets

The primary reading path targets 6–8 minutes and is capped at 10 minutes:

1. Executive answer: what changed, who is affected, why it matters, and the current verdict.
2. Problem and root cause: the broken behavior and the concrete implementation reason.
3. Business logic: actor, trigger, inputs, decisions, state changes, failures, and invariants.
4. Fix and flow: how the new path reaches the observable result.
5. Evidence: only the screenshots, HTTP exchanges, tests, diagrams, and code comparisons needed to
   prove the change.
6. Risk and delivery: compatibility, rollout, rollback, security/data impact, and open questions.
7. Collapsed appendix: changed-file inventory and secondary implementation details.

Factual claims are anchored to PR metadata or `file:line` references. Runtime output is marked
`Observed`; examples derived from tests, schemas, or fixtures are marked `Expected`.

## Evidence by change type

| Change type | Evidence |
| --- | --- |
| UI, web, or mobile | Real before/after screenshots at matching state and viewport. Mobile uses a representative simulator or device size. |
| HTTP API | Copyable cURL request plus status and response body from a safe environment; otherwise a schema/test-derived exchange labeled `Expected`. |
| Business logic or data | Decision table plus state, side-effect, failure, retry, idempotency, and rollback behavior when relevant. |
| Workflow or infrastructure | Entry point → resolver → resource → observable-result diagram, configuration precedence, and diagnostic output. |
| Documentation only | Rendered information architecture and source-accuracy evidence; no decorative runtime proof. |

A diagram is used only when at least three meaningful steps, components, states, or branches become
clearer visually. Briefs use accessible inline SVG or semantic HTML/CSS, never a remote renderer.
Primary evidence is limited to six items and supporting detail moves behind disclosure controls.

## Screenshot and API safety

- Screenshots must come from the real base/head application state; generated or mocked UI is never
  presented as implementation evidence.
- Creating temporary worktrees or isolated checkouts requires explicit approval because it changes
  repository state. Without approval, the brief uses existing evidence and records the gap.
- HTTP evidence uses local, test, or explicitly approved environments. Tokens, cookies, personal
  data, internal hosts, and secrets are redacted.
- Production mutations are never performed just to create evidence.

## Self-contained security contract

Each brief contains its CSS, JavaScript, diagrams, and screenshot bytes inline. It makes zero
automatic external requests:

- no CDN scripts or styles;
- no remote fonts, images, analytics, or diagram renderers;
- no fetch, XHR, WebSocket, EventSource, beacon, or scripted navigation;
- a restrictive CSP in `<head>` with connections denied;
- HTML escaping for every PR-controlled title, body, file path, issue, and diff string.

PR and issue links remain ordinary user-initiated links. Before completion, the skill-local parser
validates resource attributes, CSS URLs, executable JavaScript, duplicate attributes, and effective
CSP placement.

For package development, validate an artifact directly:

```bash
python3 skills/change-brief/scripts/validate-self-contained-html.py \
  ".git-workflow/change-brief/pr-42/index.html"
```

## Configuration

```yaml
changeBrief:
  outputDir: .git-workflow/change-brief
```

`changeBrief.outputDir` changes the base directory used both to write and report the artifact.
Configuration resolves from `.git-workflow/config.yaml`, then the legacy `.claude/config.yaml`
read-only fallback.

## Review Watch integration

When [Review Watch](REVIEW_WATCH.md) finishes a clean PR, it runs the host-correct Change Brief
invocation and sends the ready-for-merge notification. A self-authored PR or `--comment-only` may
post a GitHub `COMMENT`, but a clean result still produces the local brief.

If capture tooling, a runnable UI, or a safe API environment is unavailable, the brief keeps the
gap visible and includes exact reproduction steps. It never fabricates observed evidence.

See [Commands](../COMMANDS.md) and [Configuration](../CONFIGURATION.md) for the complete package
reference.
