# Change brief evidence playbook

Use the common rules for every brief, then apply only the sections matching the classified change.

## Common rules

- Prove behavior, not file churn. Group related files under one user- or system-visible change.
- Separate facts from inference. Mark runtime output `Observed`; mark contract-derived examples
  `Expected` and cite the schema, fixture, or test that supports them.
- Redact tokens, cookies, personal data, internal hosts, and secrets. Use placeholders such as
  `<TOKEN>` and `api.example.test` in displayed commands.
- Never mutate production or an external system to produce evidence. Prefer isolated test data,
  local services, recorded fixtures, existing CI artifacts, and read-only endpoints.
- Treat PR code and dependencies as untrusted. Ask before installing, building, or running code
  from an unfamiliar repository or author; use static evidence when execution is not authorized.
- State missing evidence prominently. Do not hide it in the appendix or substitute fabricated data.
- Assess user/customer impact, compatibility, permissions, security/privacy, data/schema changes,
  performance/cost, accessibility/localization, observability, rollout, and rollback. Include only
  dimensions affected by the diff so the checklist does not become boilerplate.

## Diagrams and business logic

Use a diagram when the change has at least three meaningful steps, components, states, or branches.
Choose the smallest fitting form:

- Flowchart for branching business rules or state transitions.
- Sequence diagram for calls crossing three or more components.
- Data-flow diagram for changed reads, writes, queues, caches, or external dependencies.
- Architecture diagram only when ownership or boundaries changed.

Render with accessible inline SVG or semantic HTML/CSS. Include a title, short description, labeled
arrows, and a text fallback. Do not use Mermaid at runtime or any remote renderer. Keep to one
primary diagram; use a second only when it answers a different decision question.

For business logic, document:

1. Actor and trigger.
2. Inputs and preconditions.
3. Decision rules and precedence.
4. State changes and side effects.
5. Failure, retry, idempotency, and rollback behavior when relevant.
6. Explicitly unchanged behavior and compatibility guarantees.

Use a decision table when two or more inputs change the result. Keep cells to conditions and
outcomes; explain only surprising rows.

## UI, web, and mobile evidence

Capture real before and after states from the base and head revisions. Ask for explicit user
approval before creating temporary worktrees or equivalent isolated checkouts because they modify
repository state. Without approval, use existing evidence and leave the active workspace and
repository unchanged. When approved, reuse the same seed data, route, locale, theme, viewport,
scroll position, and interaction state.

- Web: capture the smallest desktop viewport that shows the changed behavior; add a mobile viewport
  when responsiveness changed.
- Mobile: use a representative simulator/device size and show OS permission, keyboard, or safe-area
  states when they are part of the change.
- Interaction: show the state after the meaningful action, not only a static landing screen.
- Accessibility: provide useful alt text and captions that say what evidence the reader should see.

Embed compressed PNG, JPEG, or WebP bytes as `data:` URLs. Never use generated or mocked artwork as
proof of implemented UI. If a runnable environment or capture capability is unavailable, include:
the missing prerequisite, the exact command/route/state to reproduce, and the code/test evidence
used instead.

## HTTP API evidence

Identify method, path, authentication shape, request schema, success response, and changed error
semantics. Prefer a repository-owned integration test or a local service. Display a copyable command:

```bash
curl --request POST 'http://127.0.0.1:3000/v1/example' \
  --header 'Authorization: Bearer <TOKEN>' \
  --header 'Content-Type: application/json' \
  --data '{"example":"value"}'
```

Pair it with the HTTP status and a formatted response body. Redact volatile IDs unless they explain
the behavior. When execution is unsafe or unavailable, derive the exchange from an OpenAPI schema,
contract test, or fixture and label it `Expected — not executed`. Never present invented latency,
headers, IDs, or server output as observed evidence.

## Workflow, infrastructure, and documentation evidence

- Workflow/tooling: diagram entry point → resolver → resource → observable result; include exact
  diagnostic commands and their sanitized output.
- Infrastructure/config: show precedence, defaults, migration/rollback, affected environments, and
  validation output. Do not apply infrastructure merely to create a brief.
- Documentation-only: omit diagrams and runtime evidence unless they materially clarify structure;
  show the rendered information architecture and source accuracy instead.

## Reading budget

Design the default reading path for 6–8 minutes and cap it at 10 minutes. Use 220 prose words per
minute as the estimate, rounded up, then reserve reader attention for code, screenshots, and tables.
Prefer one strong artifact over several redundant ones. Put exhaustive file lists, secondary hunks,
raw logs, and long test matrices in collapsed details, while keeping risks and evidence gaps visible.
