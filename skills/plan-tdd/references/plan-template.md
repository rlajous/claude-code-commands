# TDD Plan Schema and Examples

The `plan.yaml` artifact is the machine-readable source of truth. `/tdd` can read it to drive the RED-GREEN-REFACTOR cycle. Keep it in sync with the HTML brief.

## Schema

| Key | Type | Notes |
| --- | ---- | ----- |
| `name` | string | Descriptive plan name |
| `type` | enum | `feature` \| `bug_fix` \| `refactor` |
| `description` | string | What is being built, from ticket or input |
| `context.assumptions[]` | string | Resolved answers from the clarify step |
| `context.open_questions[]` | string | Anything still unanswered |
| `test_framework` | string | Detected framework, or `unknown` |
| `test_command` | string | How the suite runs |
| `test_file_pattern` | string | Test file naming convention |
| `behavior_cycles[]` | list | One RED-GREEN-REFACTOR unit each (see below) |
| `risk_scenarios[]` | list | Threats and their coverage (see below) |
| `acceptance_criteria[]` | string | From ticket or derived |
| `out_of_scope[]` | string | Explicitly excluded behavior |

**`behavior_cycles[]` item:**

| Field | Type | Notes |
| ----- | ---- | ----- |
| `id` | string | `BC-001`, `BC-002`, ... |
| `name` | string | Behavior in plain language |
| `category` | enum | `happy_path` \| `validation` \| `auth` \| `edge_case` \| `error` \| `security` |
| `risk` | enum | `low` \| `medium` \| `high` |
| `given` / `when` / `then` | string | Preconditions / action / expected outcome |
| `assertions[]` | string | Specific checks the failing test makes |

**`risk_scenarios[]` item:**

| Field | Type | Notes |
| ----- | ---- | ----- |
| `id` | string | `RS-001`, ... |
| `threat` | string | e.g. Privilege escalation, Data leakage, Impersonation |
| `coverage` | enum | `covered` \| `partial` \| `not_covered` |
| `covered_by[]` | list | Behavior-cycle ids that cover it (empty if `not_covered`) |

## HTML section checklist

The brief renders the same data: header (name, source, framework, counts, reading time) · summary/verdict · behavior cycles grouped by category · risk matrix (tint `covered` with `--good`; tint high-risk `not_covered`/`partial` with `--bad`) · open questions and assumptions · acceptance criteria · out-of-scope appendix in `<details>`.

## Example — Feature

```yaml
name: "Role-based access on admin settings endpoint"
type: feature
description: |
  Only users with the admin role may read or update system settings via
  PATCH /admin/settings. All others are rejected without leaking data.

context:
  assumptions:
    - "Roles are user, editor, admin; only admin may write settings."
    - "Editors may read but not write; users get no access."
    - "Requests carry a signed session; role comes from the session, not the body."
  open_questions:
    - "Should a demoted admin's in-flight session lose write access immediately?"

test_framework: "jest"
test_command: "pnpm test"
test_file_pattern: "*.test.ts"

behavior_cycles:
  - id: BC-001
    name: "Admin updates settings successfully"
    category: happy_path
    risk: low
    given: "An authenticated admin"
    when: "PATCH /admin/settings with a valid body"
    then: "200 and the settings are persisted"
    assertions:
      - "Response status is 200"
      - "Persisted value matches the request body"
  - id: BC-002
    name: "Non-admin write is rejected"
    category: auth
    risk: high
    given: "An authenticated editor"
    when: "PATCH /admin/settings"
    then: "403 and no write occurs"
    assertions:
      - "Response status is 403"
      - "Settings store is unchanged"
  - id: BC-003
    name: "Role is taken from the session, not the payload"
    category: security
    risk: high
    given: "An authenticated user whose body claims role=admin"
    when: "PATCH /admin/settings"
    then: "403; the payload role is ignored"
    assertions:
      - "Response status is 403"
      - "No write occurs despite role=admin in the body"
  - id: BC-004
    name: "Rejection response leaks no settings data"
    category: security
    risk: high
    given: "A non-admin request"
    when: "The request is rejected"
    then: "The error body contains no current settings values"
    assertions:
      - "Error body has no settings fields"
  - id: BC-005
    name: "Invalid settings body is rejected"
    category: validation
    risk: low
    given: "An authenticated admin"
    when: "PATCH /admin/settings with an unknown field"
    then: "400 and no write occurs"
    assertions:
      - "Response status is 400"
      - "Settings store is unchanged"

risk_scenarios:
  - id: RS-001
    threat: "Privilege escalation"
    coverage: covered
    covered_by: [BC-002, BC-003]
  - id: RS-002
    threat: "Data leakage"
    coverage: covered
    covered_by: [BC-004]
  - id: RS-003
    threat: "Impersonation"
    coverage: partial
    covered_by: [BC-003]

acceptance_criteria:
  - "Only admins can modify settings."
  - "Unauthorized attempts are rejected without exposing data."

out_of_scope:
  - "Role management UI."
  - "Audit logging of settings changes."
```

## Example — Bug fix

```yaml
name: "Fix: expired token treated as valid"
type: bug_fix
description: |
  Tokens past their expiry are currently accepted. They must be rejected.

context:
  assumptions:
    - "Expiry is the exp claim in seconds since epoch."
  open_questions: []

test_framework: "pytest"
test_command: "pytest"
test_file_pattern: "*_test.py"

behavior_cycles:
  - id: BC-001
    name: "Expired token is rejected"
    category: error
    risk: high
    given: "A token whose exp is in the past"
    when: "It is used to authenticate"
    then: "401 and access is denied"
    assertions:
      - "Auth returns 401"
      - "No session is created"
  - id: BC-002
    name: "Valid token still works"
    category: happy_path
    risk: low
    given: "A token whose exp is in the future"
    when: "It is used to authenticate"
    then: "Access is granted"
    assertions:
      - "Auth returns 200"

risk_scenarios:
  - id: RS-001
    threat: "Impersonation via replayed expired token"
    coverage: covered
    covered_by: [BC-001]

acceptance_criteria:
  - "Expired tokens are always rejected."

out_of_scope:
  - "Token refresh flow."
```
