---
name: close-customer-loop
description: Close the loop with a customer or partner after their reported bug/request ships. Use whenever a customer/partner-reported fix reaches production, a ticket that came from a customer report is about to be marked Done/closed, or you're deciding whether follow-up is still owed. Enforces verify-in-prod-then-reply-in-the-original-thread, and adds the two acceptance-criteria lines when creating customer/partner tickets.
disable-model-invocation: false
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

# Close the customer loop

When work originates from a **customer or partner report** (a Slack/Telegram thread, a shared doc, a support ticket, an email), the job is **not done when the fix ships — it's done when the reporter has been told, in the original thread, that it's live.** A silent prod fix reads as no progress and is exactly how follow-ups get dropped and partners go cold.

## The rule

A customer/partner-reported item is only truly closed when **both** are true:

1. **Verified live in prod** — a real check against production, not "the release tag went out" or "it merged." Actually exercise the changed behavior (curl the endpoint, run the flow, query live data). Staging passing is not prod.
2. **Reply sent in the original thread** — confirm it's live and say what to re-test. If some of the report is still not addressed, say so honestly rather than implying everything is done.

If you (the agent) can't post to the thread yourself, **hand the user a ready-to-send draft** and explicitly flag the reply as *still owed* — do not present the ticket as closed until it's actually sent.

## When marking a customer/partner ticket Done

- Do the prod verification first (step 1). If it fails, don't close it — reopen/diagnose.
- Draft or send the thread reply (step 2).
- Only then move the ticket to the terminal/Done state.
- Never batch-close customer tickets on merge — each needs its own prod check + reply.

## When creating a customer/partner-reported ticket

Add these two lines to the ticket's Acceptance Criteria so the loop can't be forgotten:

- `Fix verified live in prod`
- `Reply in the original customer thread once live in prod (link the thread)`

If the tracker (e.g. Linear) has a bug/issue template, the same two lines belong there — but templates are usually UI-only and not editable via API/MCP, so add the lines to the issue body yourself when creating.

## Honesty guardrails

- Never tell a customer something is fixed/live that you haven't verified against prod. If you're inferring from a release tag, verify before you claim it (some prod routes are auth/tier-gated and a default key won't reach them — use a valid key to actually hit the endpoint).
- Separate what shipped from what's still backlog. Tell the customer both, plus a real next step or timeline for the open items rather than a vague "soon."

## Project-specific notes

If the current repo has its own ticket-workflow skill (e.g. a `linear-workflow` skill), follow that for column names, projects/cycles, and any repo-specific prod-verification details (like which key reaches gated routes). This skill is the general principle; the repo skill wins on repo specifics.
