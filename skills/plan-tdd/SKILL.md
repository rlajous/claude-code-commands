---
name: plan-tdd
description: Turn a plain-language feature or module description into a reviewed TDD plan. Ask clarifying questions when context is missing, then design behavior cycles and assertions with edge, error, and security scenarios made explicit, and emit a self-contained HTML brief plus a machine-readable YAML plan that /tdd can implement. Use when the user says "plan a TDD", "design tests first", "spec-driven TDD", "what tests should this have", or wants a test plan reviewed before writing code.
argument-hint: "[description or ticket-id]"
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Write, Edit
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are helping design a Test-Driven Development plan **before** any code is written. Take a plain-language description of what the user wants to build (optionally a ticket), fill missing context by asking the user, then produce a plan of **behavior cycles** (each a RED-GREEN-REFACTOR unit) and their **assertions**. Make edge cases, error paths, and high-risk scenarios (privilege escalation, data leakage, impersonation) explicit rather than leaving them off the radar. Deliver two artifacts: a self-contained HTML brief the user reviews, and a machine-readable YAML plan that `/tdd` can implement. This skill plans and reviews — it does **not** write implementation code, and it only scaffolds test skeletons after explicit approval (Step 11). Follow each step in order.

## Step 1: Load Configuration

Check for configuration and context:

```bash
if [ -f ".git-workflow/config.yaml" ]; then
  CONFIG_PATH=".git-workflow/config.yaml"
elif [ -f ".claude/config.yaml" ]; then
  CONFIG_PATH=".claude/config.yaml" # legacy read-only fallback
else
  CONFIG_PATH=""
fi
if [ -f ".git-workflow/pr-context.json" ]; then
  CONTEXT_PATH=".git-workflow/pr-context.json"
elif [ -f ".claude/.pr-context.json" ]; then
  CONTEXT_PATH=".claude/.pr-context.json" # legacy read-only fallback
else
  CONTEXT_PATH=""
fi
```

**Load from the resolved `CONFIG_PATH` (if one exists):**

```yaml
planTdd:
  outputDir: .git-workflow/plan-tdd
  maxQuestions: 6
testing:
  unit: auto
  lint: auto
  typeCheck: auto
issueTracker:
  type: auto
```

**Default Values (when no config):**

```yaml
planTdd:
  outputDir: .git-workflow/plan-tdd
  maxQuestions: 6
```

## Step 2: Parse Arguments

Extract from `$ARGUMENTS`:

```text
$ARGUMENTS
```

**Patterns to Extract:**

| Pattern      | Example                                     | Meaning              |
| ------------ | ------------------------------------------- | -------------------- |
| Ticket ID    | `PROJ-123`, `ENG-456`                       | Issue tracker ticket |
| GitHub Issue | `#789`                                      | GitHub issue number  |
| Linear URL   | `https://linear.app/.../ENG-456/...`        | Extract ticket ID    |
| Jira URL     | `https://....atlassian.net/browse/PROJ-123` | Extract ticket ID    |
| Remaining text | `Add role-based access to admin settings` | Feature description  |

**Parsing Logic:**

- Extract ticket ID from URL if provided. Linear: `/issue/([A-Z]+-\d+)/`; Jira: `/browse/([A-Z]+-\d+)`; GitHub: `issues/(\d+)` or `#(\d+)`.
- Everything not matched as a ticket/flag is the feature description.

**Validation:**

- Require at least a description **or** a ticket. If neither is present, ask the user what they want to build through the host's user-input mechanism before continuing.

## Step 3: Fetch Ticket Details (If ID Provided)

Auto-detect the tracker by ticket format and available MCP servers, then fetch details. Skip this step entirely when the input is only a free-text description.

- `^[A-Z]+-\d+$` with Linear MCP available -> Linear: `mcp__linear__get_issue(id: ticketId)`
- `^[A-Z]+-\d+$` with Jira configured/available -> Jira: `mcp__jira__get_issue(issueKey: ticketId)`
- `^#?\d+$` or GitHub URL -> GitHub Issues: `gh issue view {issue_number} --json title,body,labels`

Extract title, description, acceptance criteria, and labels. Use labels to classify the plan `type`:

| Label/Type                        | Plan type  |
| --------------------------------- | ---------- |
| `bug`, `defect`                   | `bug_fix`  |
| `feature`, `Story`, `enhancement` | `feature`  |
| `refactor`, `tech-debt`           | `refactor` |

## Step 4: Explore Codebase and Detect Test Framework

Gather enough context to write a plan that fits the project.

- Find files related to the description/ticket keywords, existing implementations in the same area, and neighboring test files.
- Identify the test file naming convention, framework, test structure, and mock patterns from existing tests.
- Detect the test framework and its run command.

> Full per-language detection commands, tables, and the detection-results JSON shape: see `references/test-frameworks.md`.

Record `test_framework`, `test_command`, and `test_file_pattern` for the plan.

## Step 5: Clarify Gaps

This is the core of the skill: when context is missing, ask for it instead of guessing.

From the description, ticket, and code, list the ambiguities and undefined behavior that would change the tests, focusing on:

- **Scope and inputs** — what exactly is in and out of scope, valid input ranges, required vs optional fields.
- **Edge and error behavior** — empty/absent data, limits, concurrency, invalid input, downstream failures, idempotency.
- **Risk boundaries** — who is authorized for what (privilege scope), what data each actor may see (exposure), identity and impersonation rules, and tenant/isolation boundaries.

Ask the user the highest-value questions through the host's user-input mechanism. Keep it bounded — no more than `planTdd.maxQuestions` (default 6). Record each answer as a resolved assumption; note anything left unanswered as an open question. Do not proceed to design until the risk boundaries are either answered or explicitly recorded as open.

## Step 6: Design the TDD Plan

Enumerate **behavior cycles**. Each cycle is one RED-GREEN-REFACTOR unit describing an observable behavior, with concrete assertions that its RED test would make.

For every cycle capture:

- `id` (`BC-001`, `BC-002`, ...)
- `name` — the behavior in plain language
- `category` — one of `happy_path`, `validation`, `auth`, `edge_case`, `error`, `security`
- `risk` — `low`, `medium`, or `high`
- `given` / `when` / `then` — preconditions, action, expected outcome
- `assertions[]` — the specific checks the failing test makes

Cover happy paths **and** the categories that specs usually miss: validation, auth, edge cases, error handling. Then build an explicit **risk-scenario set** — at minimum privilege escalation, data leakage, and impersonation, plus any project-relevant threats surfaced in Step 5 — and map each to the cycle(s) that cover it (`covered`, `partial`, or `not_covered`). Surfacing an uncovered high-risk scenario is a feature of this plan, not an omission: list it as `not_covered` so the review makes the gap visible.

## Step 7: Emit the Structured Plan (YAML)

Build the machine-readable plan that `/tdd` can later consume.

> Full schema and a worked feature/bug example: see `references/plan-template.md`.

Top-level shape:

```yaml
# Auto-generated TDD Plan
# Source: {TICKET_ID or "Manual description"}

name: "{DESCRIPTIVE_NAME}"
type: feature # feature | bug_fix | refactor
description: |
  {DESCRIPTION_FROM_TICKET_OR_INPUT}

context:
  assumptions:
    - "{Resolved answer from Step 5}"
  open_questions:
    - "{Anything still unanswered}"

test_framework: "{jest|vitest|pytest|cargo|go|...}"
test_command: "{npm test|pytest|go test ./...|...}"
test_file_pattern: "*.test.ts|*_test.py|..."

behavior_cycles:
  - id: BC-001
    name: "{Behavior}"
    category: happy_path # happy_path | validation | auth | edge_case | error | security
    risk: low # low | medium | high
    given: "{Preconditions}"
    when: "{Action}"
    then: "{Expected outcome}"
    assertions:
      - "{Specific check the failing test makes}"

risk_scenarios:
  - id: RS-001
    threat: "Privilege escalation"
    coverage: covered # covered | partial | not_covered
    covered_by: [BC-003]

acceptance_criteria:
  - "{AC from ticket or derived}"

out_of_scope:
  - "{Explicitly excluded behavior}"
```

## Step 8: Render the Review HTML

Build one self-contained `index.html` the user can open to confirm the plan captures their intent. Reuse the presentation rules below verbatim.

**Sections:**

- **Header** — `TDD Plan — <name>`, the source ticket/description, detected framework, and counts (behavior cycles, assertions, risk scenarios). Show an estimated reading time.
- **Summary / verdict** — what will be built and the overall test posture in a screen's worth of text.
- **Behavior cycles** — grouped by category, each showing `given/when/then`, `risk`, and its assertions.
- **Risk matrix** — each risk scenario as a row: threat, coverage, and covering cycles. Tint `covered` with `var(--good)` and any `not_covered`/`partial` **high**-risk row with `var(--bad)` so gaps stand out.
- **Open questions and assumptions** — the resolved and unresolved items from Step 5.
- **Acceptance criteria**.
- **Appendix** — out-of-scope items and secondary detail in collapsed `<details>`.

Every string pulled from the ticket, description, or code MUST be HTML-escaped (`&`, `<`, `>`, `"`, `'`) before being written into the page — never interpolate raw content into HTML. Target **6–8 minutes** of reading; keep prose lean and move detail behind `<details>`.

### Style (single neutral palette)

Author against role variables, never raw hex, in one inline `<style>` block: `--bg` page plane · `--surface` card/panel · `--ink` primary text · `--ink-muted` secondary text · `--border` hairline · `--accent` links/highlights · `--good` covered/success · `--bad` gap/error · `--radius` corner radius · `--font-ui` UI font · `--font-mono` code font.

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

Keep it clean, not flashy: max content width ~1100px centered, generous spacing, `<pre>` blocks boxed with `var(--border)`. Add a minimal light/dark toggle so the page is readable either way:

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

**Zero automatic external requests.** No CDN links, external fonts, analytics, or remote images. Keep the page to inline styles/scripts. Add this defense-in-depth policy in `<head>`:

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
```

`img-src data:` lets any embedded `data:` image (e.g. an inline diagram) render; without it those images fall back to `default-src 'none'` and are blocked. It keeps the page fully offline — no network origin is allowed.

Before finishing, run the parser-based validator against the generated file:

```bash
python3 "{SKILL_DIR}/scripts/validate-self-contained-html.py" "{outputDir}/<slug>/index.html"
```

Pass the resolved output path as a literal argument (as shown), not by interpolating raw config text into the command — see the input-safety note in Step 9. This MUST exit successfully. If it reports a finding, remove the offending reference and re-check. Resolve `{SKILL_DIR}` to the absolute, physical directory containing this loaded `SKILL.md`. If the host cannot expose that path, use `PLUGIN_ROOT`, then `CLAUDE_PLUGIN_ROOT`, only to locate `skills/plan-tdd/SKILL.md`; verify the validator exists and never fall back to `/scripts`.

## Step 9: Write Outputs

Resolve the output base directory `{outputDir}` from configuration (`planTdd.outputDir`, default `.git-workflow/plan-tdd`).

**`{outputDir}` is repository-controlled input — treat it as literal data, not shell source.** Read it through the host's file/config reader and pass it as an **argument** to a filesystem API or a command; never paste its raw text into a command line, because double-quoting still lets `$(…)` and backticks execute. Prefer creating the directory and writing files with the host's filesystem tools (Write) rather than a shell. If you must use a shell, first reject any resolved value containing shell metacharacters (`` $ ` \ ; & | < > ( ) ``newline) and stop with an error, then reference it only through a quoted variable with `--`.

**Determine a collision-safe slug:**
- Ticket ID lowercased (e.g. `proj-123`) — already unique.
- Otherwise kebab-case the description (first ~50 chars) **and append a short stable digest of the full description** (e.g. the first 8 hex chars of its SHA-256), so two descriptions that share a truncated prefix don't collide: `add-role-based-access-to-the-admin-settings-endpo-1a2b3c4d`.
- Before writing, if `{outputDir}/<slug>` already exists, do not silently overwrite it — ask the user whether to overwrite or write to a new suffixed directory.

Create the folder and write both artifacts to `{outputDir}/<slug>/plan.yaml` and `{outputDir}/<slug>/index.html`. Use the same resolved `{outputDir}` for the write and for the report — do not hard-code the path.

## Step 10: Review Checkpoint

Tell the user the HTML path (`{outputDir}/<slug>/index.html`) and that it is a single self-contained file they can open in a browser. Ask them to confirm the plan captures what they want to build. If they request changes, revise the cycles, assumptions, or risk coverage and re-emit both artifacts (Steps 6–9), then check again. Do not proceed to skeletons until the user approves.

## Step 11: Optional — Scaffold RED Skeletons

Only after the user explicitly approves the plan, offer to scaffold failing test skeletons. Ask the user through the host's user-input mechanism whether to create them; do nothing to the codebase if they decline.

If approved, create one **failing** test stub per behavior cycle in the project's test path, following the detected framework and naming convention. Each stub is RED by construction — a pending/skip marker or a trivially failing assertion — with **no implementation**. Do not touch source files. This is the only file-writing action beyond the two artifacts and it is gated on explicit approval, per the repository's strictly-reactive, no-unapproved-side-effects guidance.

**Treat cycle `name`/`then` text as untrusted (it originates from ticket or user input) when writing stubs:**

- **Test identifiers** (function, method, class, and `#[test]` fn names in Python, Go, Rust, unittest) must be derived **only** from the stable cycle `id` — e.g. `test_bc_001`, `TestBC001`, `bc_001` — never interpolated from behavior text. Slugify the id, not the prose.
- **Behavior text** goes only inside a **string literal** (the test title / skip reason) or a **comment**, and must be escaped for that context first: escape quotes, backslashes, and newlines; strip or neutralize any sequence that could close the string or the comment. Never place raw behavior text where it becomes code.
- If a framework has no string-titled test (Go, Rust), put the behavior text in an **escaped trailing comment** and keep the identifier id-based.

See `references/test-frameworks.md` for id-based, escaped stub templates per framework.

## Step 12: Report and Next Step

Summarize what was produced and point to implementation:

```
TDD plan generated: {outputDir}/<slug>/

Artifacts:
- index.html  (open in a browser to review)
- plan.yaml   (machine-readable, consumable by /tdd)

Plan summary:
- Behavior cycles: {N}  (happy_path {A} · validation {B} · auth {C} · edge_case {D} · error {E} · security {F})
- Assertions: {M}
- Risk scenarios: {covered X · partial Y · not covered Z}
- Open questions: {K}
{If skeletons created: - Test skeletons: {N} failing stubs under {test path}}

Next:
/tdd {ticket-id}   # implement the plan test-first
```

## Configuration Reference

Resolve configuration from `.git-workflow/config.yaml` first, then the legacy `.claude/config.yaml` read-only fallback, per [runtime compatibility](../../references/runtime-compatibility.md).

| Setting              | Default                | Description                                   |
| -------------------- | ---------------------- | --------------------------------------------- |
| `planTdd.outputDir`  | `.git-workflow/plan-tdd` | Base directory for generated plans          |
| `planTdd.maxQuestions` | `6`                  | Max clarifying questions in Step 5            |
| `issueTracker.type`  | `auto`                 | Issue tracker for ticket lookups              |

## Error Handling

| Scenario                                             | Action                                                             |
| ---------------------------------------------------- | ------------------------------------------------------------------ |
| No description and no ticket in arguments            | Ask the user what they want to build, then continue                |
| Ticket ID given but tracker unavailable/unauthorized | If the arguments also included a usable description, note the lookup failure and continue from it. If the ticket was the only input, do not design a speculative plan — ask the user for a description, or stop with a clear error. |
| Test framework cannot be detected                    | Record `test_framework: unknown`, still emit cycles and assertions |
| Risk boundaries left unanswered in Step 5            | Record them as `open_questions` and mark related scenarios `not_covered` |
| HTML validator reports a finding                     | Remove the offending reference and re-run until it exits 0         |
| User declines skeletons in Step 11                   | Leave the codebase untouched; only the two artifacts exist         |

## Examples

### From a description

```
/plan-tdd Add role-based access to the admin settings endpoint
```

Asks about privilege scope and data exposure, then generates cycles plus a risk matrix flagging privilege-escalation and data-leak coverage.

### From a ticket

```
/plan-tdd PROJ-123
```

Fetches the ticket, clarifies gaps, and writes `plan.yaml` + `index.html` under `.git-workflow/plan-tdd/proj-123/`.

### Plan then implement

```
/plan-tdd ENG-456     # review the HTML, approve
/tdd ENG-456          # implement the approved plan test-first
```
