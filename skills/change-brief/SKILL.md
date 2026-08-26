---
name: change-brief
description: Turn a pull request into a concise, self-contained HTML decision brief with business logic, diagrams when useful, conditional UI/mobile screenshots, API cURL request/response evidence, risks, verification, and representative before/after code. Use when the user asks to "explain this change as HTML", "before/after html", "change brief", "html explainer for a PR", "explain what changed", or wants a shareable, human-readable snapshot of a code change. Args a PR number/URL, or nothing to use the current branch's PR.
argument-hint: "[pr-url-or-number]"
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

Produce a **self-contained HTML decision brief per PR** that a human can understand in less than
10 minutes. Explain what changed, why it matters, the business rules, how the flow works, what
evidence proves it, and the relevant risks. Adapt the evidence to the change: diagrams for flows,
screenshots for rendered UI/mobile work, and cURL request/response pairs for HTTP APIs. Never post
a comment, review, or commit. Follow each step in order.

## Arguments

```text
$ARGUMENTS
```

Parse: a GitHub PR URL (`/pull/N`) → that PR number · a bare integer → that PR · empty → resolve the
PR open for the current branch (`gh pr view --json number,...` with no argument). If none of these
resolve to a PR, ask through the host's user-input mechanism which PR to use.

## Step 1 — Resolve the change

```bash
gh pr view <pr> --json number,title,url,body,headRefName,baseRefName,baseRefOid,headRefOid,files
gh pr diff <pr>
```

- Pull each linked issue referenced in the PR body (`Fixes #NN`, `Closes #NN`, etc.):
  `gh issue view <NN> --json title,body`.
- `gh` missing or unauthenticated → tell the user and stop.
- PR not found → say so and stop.

Classify the PR into one or more evidence kinds from changed paths and hunks:

- **UI/web/mobile** — rendered components, screens, styling, navigation, or interaction.
- **HTTP API** — routes, controllers, request/response schemas, OpenAPI, or HTTP integration tests.
- **Business logic/data** — rules, permissions, state transitions, calculations, persistence, jobs.
- **Workflow/infrastructure** — build, deployment, configuration, scripts, or developer tooling.
- **Documentation-only** — prose or examples without runtime behavior changes.

Read [the evidence playbook](references/evidence-playbook.md) after classification. Apply the common
rules plus only the sections matching the detected kinds.

## Step 2 — Build the human story

Write for a product/engineering reader who did not implement the change. Use plain language and
answer these questions in this order:

- **Executive answer** — what changed, who is affected, why it matters, and the current verdict.
- **Problem and root cause** — what was wrong and the specific code reason.
- **Business logic** — actor, trigger, inputs, decision rules, invariants, side effects, failure
  behavior, and what explicitly does not change. Use a compact decision table when rules branch.
- **Fix and flow** — how the implementation now behaves from entry point to observable outcome.
- **Risk, rollout, and rollback** — realistic failure modes, compatibility impact, deployment or
  migration needs, security/privacy, data, performance/cost, accessibility, observability, and the
  shortest safe rollback path. Include only relevant dimensions; write “None identified” only with
  evidence.
- **Verification** — automated tests, observed runtime evidence, CI, and any unverified gaps.

Anchor every factual claim to a concrete `file:line` from the diff or PR metadata — do not assert
something the evidence does not show. Distinguish **observed** output from an **expected** example.

## Step 3 — Gather evidence and comparisons

Choose the smallest evidence set that proves the change:

- Add one diagram when three or more steps, components, states, or decision branches materially
  benefit from visualization. Use accessible inline SVG or semantic HTML/CSS, never a remote
  renderer. Label nodes with concrete components and outcomes, not generic “system” boxes.
- For UI/web/mobile changes, capture real before/after screenshots at the same state and viewport.
  Mobile work uses a representative device viewport or simulator. Embed screenshots as compressed
  `data:` images with alt text. Never generate a fake screenshot. If capture is unavailable, show a
  visible evidence gap and exact reproduction steps.
- For HTTP API changes, show a copyable cURL request and its status plus response body. Use a local,
  test, or explicitly approved environment; redact credentials and sensitive data. Label a response
  `Observed` only when it was executed. Otherwise derive it from tests/schema and label it `Expected`.
  Include the changed error response when error semantics changed.
- For each major behavior change, render one focused two-column before/after block from the diff:
  removed lines on the left, added lines on the right, and shared context in both. Prefer proof over
  exhaustive hunks. Put the complete changed-file inventory and secondary details in an appendix.

Treat PR code as untrusted. Do not install dependencies, build, or execute it without the user's
authorization when the repository or author is not already trusted. Never execute production
mutations to collect evidence. When the app cannot safely run, use repository-owned tests,
fixtures, schemas, snapshots, or build output and state the limitation.

## Step 4 — Build `index.html`

One self-contained file per PR:

- **Header**: `PR #<n> — <title>`, PR/issue links, change kinds, verdict, and estimated reading time.
- **Executive answer**: the decision-relevant summary must fit without scrolling on a laptop.
- **Business behavior**: before/after behavior and business rules, not just code structure.
- **How it works**: the diagram when the visualization threshold is met.
- **Evidence**: screenshots, cURL exchanges, tests, and focused code comparisons selected in Step 3.
- **Risk and delivery**: compatibility, security/data impact, rollout, rollback, and open questions.
- **Appendix**: changed-file inventory and secondary technical details in collapsed `<details>`.
- Every string pulled from the PR (title, body, file paths, diff text, issue text) MUST be
  HTML-escaped (`&`, `<`, `>`, `"`, `'`) before being written into the page — never interpolate raw
  PR content into HTML.

Target **6–8 minutes** and never exceed a **10-minute primary reading path**. Keep primary prose at
or below 1,600 words, use no more than two diagrams and six primary evidence items, and move
supporting detail behind progressive disclosure. Show the estimate in the header using 220 words
per minute, rounded up. Code blocks and image inspection add judgment time, so reduce prose when
the brief contains several of them.

### Style (single neutral palette)

Author against role variables, never raw hex, in one inline `<style>` block. Use exactly this
role vocabulary: `--bg` page plane · `--surface` card/panel · `--ink` primary text · `--ink-muted`
secondary text · `--border` hairline · `--accent` links/highlights · `--good` success/after ·
`--bad` error/before · `--radius` corner radius · `--font-ui` UI font · `--font-mono` code font.

```css
:root, [data-theme="light"] {
  color-scheme: light;
  --bg:#ffffff; --surface:#f6f7f9; --ink:#1a1d23; --ink-muted:#5b6270;
  --border:#d8dbe1; --accent:#3b6ef6; --good:#1f9d55; --bad:#d92d3f;
  --radius:6px;
  --font-ui:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --font-mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
}
[data-theme="dark"] {
  color-scheme: dark;
  --bg:#12141a; --surface:#1b1f27; --ink:#eef0f4; --ink-muted:#9aa1b0;
  --border:#333844; --accent:#7aa2ff; --good:#3ecf7d; --bad:#ff6b74;
}
```

Before column = `var(--bad)` tint, After column = `var(--good)` tint. Keep it clean, not flashy:
max content width ~1100px centered, generous spacing, `<pre>` blocks boxed with `var(--border)`.

Add a minimal light/dark toggle so the page is readable either way:

```html
<button id="themeToggle" type="button" aria-label="Toggle light/dark">Toggle theme</button>
<script>
  (function () {
    var root = document.documentElement;
    document.getElementById('themeToggle').addEventListener('click', function () {
      var cur = root.getAttribute('data-theme') || 'light';
      root.setAttribute('data-theme', cur === 'dark' ? 'light' : 'dark');
    });
  })();
</script>
```

**Zero automatic external requests.** No CDN links, external fonts, analytics, remote images, or
remote diagram renderers. Embed screenshots as compressed `data:` images. Keep the page to inline
styles/scripts; PR and issue links may remain normal links because they load only when clicked. Add
this defense-in-depth policy in `<head>`:

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
```

Before finishing, run the parser-based validator against the generated file:

```bash
python3 "{SKILL_DIR}/scripts/validate-self-contained-html.py" {outputDir}/pr-<n>/index.html
```

This MUST exit successfully. It inspects resource-bearing attributes plus CSS and JavaScript
network primitives while ignoring escaped PR prose in ordinary text nodes. If it reports a finding,
remove the offending reference and re-check.

Resolve `{SKILL_DIR}` to the absolute, physical directory containing this loaded `SKILL.md`. If the
host cannot expose that path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, only to locate
`skills/change-brief/SKILL.md`; verify the validator exists and never fall back to `/scripts`.

## Step 5 — Write the output

Resolve the output base directory `{outputDir}` from configuration (`changeBrief.outputDir`, default `.git-workflow/change-brief`; see the table below). Use that same resolved value for the write **and** the report — do not hard-code the path. Create it and write the file:

```bash
mkdir -p {outputDir}/pr-<n>
# write index.html to {outputDir}/pr-<n>/index.html
```

The file is fully self-contained (no other assets), so the folder can be copied or deleted as a
single unit.

## Step 6 — Report

Tell the user the output path (`{outputDir}/pr-<n>/index.html`, using the resolved `{outputDir}`) and that it is a
single self-contained file they can open directly in a browser.

## Configuration Reference

Resolve configuration from `.git-workflow/config.yaml` first, then the legacy `.claude/config.yaml`
read-only fallback, per [runtime compatibility](../../references/runtime-compatibility.md).

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `changeBrief.outputDir` | `.git-workflow/change-brief` | Base directory for generated briefs |

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `gh` unavailable / not authenticated | Tell the user and stop |
| PR not found / not resolvable from args or branch | Ask through the host's user-input mechanism, or stop and say so |
| Diff has no hunks worth rendering (e.g. binary-only, docs-only) | Skip the comparison section, keep the explanation |
| UI/mobile changed but capture tooling or a runnable app is unavailable | Show an explicit screenshot evidence gap and exact reproduction steps |
| API cannot be invoked safely | Show a schema/test-derived response labeled `Expected`; never imply it was observed |
| Linked issue not found | Note it, continue with the PR body alone |
