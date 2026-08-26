---
name: change-brief
description: Turn a pull request into a self-contained HTML page that explains the change in plain English and shows a before/after comparison of the diff. Use when the user asks to "explain this change as HTML", "before/after html", "change brief", "html explainer for a PR", "explain what changed", or wants a shareable, reviewable snapshot of a code change. Args a PR number/URL, or nothing to use the current branch's PR.
argument-hint: "[pr-url-or-number]"
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

Produce a **self-contained HTML page per PR** that (1) explains the change in plain language and
(2) shows a **before/after** comparison of what the diff actually did. It reads from the PR only —
it never posts a comment, review, or commit. Follow each step in order.

## Arguments

```text
$ARGUMENTS
```

Parse: a GitHub PR URL (`/pull/N`) → that PR number · a bare integer → that PR · empty → resolve the
PR open for the current branch (`gh pr view --json number,...` with no argument). If none of these
resolve to a PR, ask through the host's user-input mechanism which PR to use.

## Step 1 — Resolve the change

```bash
gh pr view <pr> --json number,title,url,body,headRefName,baseRefName,files
gh pr diff <pr>
```

- Pull each linked issue referenced in the PR body (`Fixes #NN`, `Closes #NN`, etc.):
  `gh issue view <NN> --json title,body`.
- `gh` missing or unauthenticated → tell the user and stop.
- PR not found → say so and stop.

## Step 2 — Write the explanation

For the change, in plain language (no unexplained jargon), write four parts:

- **Problem** — what was wrong or missing, from the PR/issue description.
- **Root cause** — the specific code reason, naming the file and line/function that caused it
  (`path/to/file.ext:42`).
- **Fix** — what changed and why, one or two sentences, anchored to the same `file:line` references.
- **Verification** — how the fix was confirmed (tests added/run, manual check, CI), if stated in the
  PR body or visible in the diff (e.g. a new test file).

Anchor every factual claim to a concrete `file:line` from the diff or PR metadata — do not assert
something the diff does not show.

## Step 3 — Build the before/after comparison

For each changed file with a non-trivial hunk, render a **two-column before/after** block from the
`gh pr diff` hunks:

- Left column ("Before"): the hunk's removed (`-`) lines.
- Right column ("After"): the hunk's added (`+`) lines.
- Context lines (no `+`/`-`) appear in both columns unstyled.
- Removed lines get the "before" treatment (red-tinted background/text using `var(--bad)`); added
  lines get the "after" treatment (green-tinted using `var(--good)`).

UI screenshots are **optional** — only add a screenshot before/after row if a browser-automation
tool is available in the current session and the PR touches rendered UI. Otherwise the comparison is
code-only, which is the default and fully sufficient.

## Step 4 — Build `index.html`

One self-contained file per PR:

- **Header**: `PR #<n> — <title>`, a link to the PR and each linked issue, a one-line summary.
- **Explanation**: the Problem / Root cause / Fix / Verification sections from Step 2.
- **Comparison**: the before/after blocks from Step 3, one per changed file, each with a small
  `<pre>` using the monospace font for the code.
- Every string pulled from the PR (title, body, file paths, diff text, issue text) MUST be
  HTML-escaped (`&`, `<`, `>`, `"`, `'`) before being written into the page — never interpolate raw
  PR content into HTML.

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

**Zero external requests.** No CDN links, no external fonts, no analytics, no remote images — the
whole page is one `<style>` and one small inline `<script>`. Add this defense-in-depth policy in
`<head>` (the page's PR and issue links still work when the user chooses to open them):

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
```

Before finishing, run the parser-based validator against the generated file:

```bash
python3 "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts/validate-self-contained-html.py" {outputDir}/pr-<n>/index.html
```

This MUST exit successfully. It inspects resource-bearing attributes plus CSS and JavaScript
network primitives while ignoring escaped PR prose in ordinary text nodes. If it reports a finding,
remove the offending reference and re-check.

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
| Browser-automation tool unavailable | Skip UI screenshots, comparison stays code-only |
| Linked issue not found | Note it, continue with the PR body alone |
