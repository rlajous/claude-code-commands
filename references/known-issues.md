# Known issues

These are the "errors we already know" — deterministic mistakes that don't need a model to catch
them. The `review-watch` skill's Tier-1 pass greps the changed lines of a diff against the patterns
below before spending anything on the full review fan-out; a hit here is enough to request changes
without further reasoning.

This is a **starter ruleset**, not exhaustive, and intentionally framework-agnostic. Teams should
append their own rows as they find recurring mistakes worth catching mechanically. A project-level
`.git-workflow/known-issues.md` is honored in addition to this file — put project-specific rules
there instead of editing this one.

| Pattern (grep -E) | Applies to | Severity | Why |
| ------------------ | ---------- | -------- | --- |
| `console\.log\(` | JS/TS | warning | Leftover debug logging; noisy in production output |
| `debugger;` | JS/TS | error | Breakpoint statement left in committed code |
| `!important` | CSS/SCSS | warning | Overrides cascade rather than fixing specificity; hard to undo later |
| `style=` | HTML/JSX/TSX | warning | Inline styles bypass the shared stylesheet/design tokens |
| `TODO` | any | note | Marks known-incomplete work; should be tracked, not shipped silently |
| `FIXME` | any | note | Marks known-incomplete work; should be tracked, not shipped silently |
| `#[0-9a-fA-F]{3,6}\b` | CSS/JSX/TSX (components) | note | Hard-coded hex color instead of a design token/variable |
| `:\s*any\b` | TS/TSX | warning | Disables type checking for that value |
| `[^=!<>]==[^=]` | JS | warning | Loose equality (`==`) instead of `===`; coercion surprises |
| `\.only\(` | JS/TS (tests) | error | Test scoped to `.only` will skip the rest of the suite in CI |
| `print\(` | Python | warning | Leftover debug print instead of the project logger |

## How to add a rule

Append a row with a `grep -E`-compatible pattern, the file types it applies to, a severity
(`error` = blocker, `warning` = flagged but not blocking, `note` = informational), and a one-line
reason. Keep patterns anchored enough to avoid false positives on the diff's changed lines only —
Tier-1 is meant to be cheap and unambiguous, not a full linter replacement.
