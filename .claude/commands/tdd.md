---
description: Implement a ticket using Test-Driven Development (RED-GREEN-REFACTOR)
argument-hint: "<ticket-id>"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Edit, Write
---

You are helping implement a ticket using Test-Driven Development (TDD). Your task is to guide the user through the RED-GREEN-REFACTOR cycle: write failing tests first, implement code to pass tests, then refactor while keeping tests green.

## Step 1: Load Configuration

Check for configuration and context:

```bash
# Check for config and context files
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
[ -f ".claude/.pr-context.json" ] && echo "CONTEXT=true" || echo "CONTEXT=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
qa:
  tdd:
    confirmBeforeGreen: true
    confirmBeforeRefactor: true
    maxRedAttempts: 3
    runFullSuiteEachPhase: false
    autoStartServer: false
testing:
  unit: auto
  lint: auto
  typeCheck: auto
issueTracker:
  type: auto
```

**Default Values (when no config):**

```yaml
qa:
  tdd:
    confirmBeforeGreen: true
    confirmBeforeRefactor: true
    maxRedAttempts: 3
    runFullSuiteEachPhase: false
    autoStartServer: false
```

## Step 2: Parse Arguments

Extract from `$ARGUMENTS`:

```text
$ARGUMENTS
```

**Patterns to Extract:**

| Pattern     | Example                              | Meaning              |
| ----------- | ------------------------------------ | -------------------- |
| Ticket ID   | `PROJ-123`, `ENG-456`                | Issue tracker ticket |
| GitHub Issue | `#789`                              | GitHub issue number  |
| Linear URL  | `https://linear.app/.../ENG-456/...` | Extract ticket ID    |
| Jira URL    | `https://....atlassian.net/browse/PROJ-123` | Extract ticket ID |

**Parsing Logic:**

- Extract ticket ID from URL if provided
- Linear: Pattern `/issue/([A-Z]+-\d+)/`
- Jira: Pattern `/browse/([A-Z]+-\d+)`
- GitHub: Pattern `issues/(\d+)` or `#(\d+)`

**Validation:**

- Ticket ID is required for TDD workflow
- If not provided, prompt the user for it

## Step 3: Fetch Ticket Details

### Auto-Detect Issue Tracker Type

Based on ticket format and available MCP servers:

- `^[A-Z]+-\d+$` with Linear MCP available -> Linear
- `^[A-Z]+-\d+$` with Jira config/MCP available -> Jira
- `^#?\d+$` or GitHub URL -> GitHub Issues (via `gh` CLI)

### Linear Integration

If Linear ticket format is detected, use the Linear MCP server:

```text
mcp__linear__get_issue(id: ticketId)
```

Extract:
- Title
- Description
- Acceptance criteria
- Labels (to determine bug vs feature)

### Jira Integration

If Jira is configured, use the Jira MCP server:

```text
mcp__jira__get_issue(issueKey: ticketId)
```

Extract:
- Summary (title)
- Description
- Acceptance criteria
- Issue type (Bug/Story/Task)

### GitHub Issues

If GitHub format detected:

```bash
gh issue view {issue_number} --json title,body,labels
```

### Determine Ticket Type

From ticket labels/type, determine:

| Label/Type | Classification | TDD Behavior |
| ---------- | -------------- | ------------ |
| `bug`, `Bug`, `defect` | Bug | Include reproduction step |
| `feature`, `Story`, `enhancement` | Feature | Skip reproduction |
| `refactor`, `tech-debt` | Refactor | Focus on existing tests first |

## Step 4: Explore Codebase

Gather context about the codebase:

### Find Related Files

Search for files related to the ticket:

```bash
# Search for keywords from ticket title/description
# Look for existing implementations
# Find related test files
```

**Look for:**
- Files matching keywords from ticket
- Existing test files in same area
- Related service/controller files
- Configuration files

### Analyze Test Patterns

Identify existing test patterns:

```bash
# Find test files
find . -name "*.test.ts" -o -name "*.spec.ts" -o -name "*_test.py" -o -name "*_test.go" | head -20

# Check test framework imports
grep -r "describe\|it\|test\|expect" --include="*.test.*" -l | head -5
```

**Extract:**
- Test file naming convention (`*.test.ts`, `*.spec.ts`, `*_test.py`, etc.)
- Test framework (Jest, Vitest, pytest, go test, etc.)
- Test structure (describe/it, test(), etc.)
- Mock patterns used

### Detect Test Framework

**Node.js:**

```bash
# Check package.json for test framework
cat package.json | grep -E "(jest|vitest|mocha|ava)" || echo "UNKNOWN"

# Check for config files
ls jest.config.* vitest.config.* 2>/dev/null
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| `jest` in package.json | Jest | `npm test` or `pnpm test` |
| `vitest` in package.json | Vitest | `npm test` or `pnpm vitest` |
| `vitest.config.*` exists | Vitest | `pnpm vitest` |
| `mocha` in package.json | Mocha | `npm test` |

**Python:**

```bash
# Check for pytest
cat pyproject.toml 2>/dev/null | grep pytest || ls .pytest_cache 2>/dev/null
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| pytest in pyproject.toml | pytest | `pytest` |
| .pytest_cache exists | pytest | `pytest` |
| unittest pattern | unittest | `python -m unittest` |

**Rust:**

```bash
# Check for Cargo.toml
[ -f "Cargo.toml" ] && echo "RUST"
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| Cargo.toml exists | cargo test | `cargo test` |

**Go:**

```bash
# Check for go.mod
[ -f "go.mod" ] && echo "GO"
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| go.mod exists | go test | `go test ./...` |

**Store Detection Results:**

```json
{
  "testFramework": "jest|vitest|pytest|cargo|go",
  "testCommand": "npm test|pnpm vitest|pytest|cargo test|go test ./...",
  "testFilePattern": "*.test.ts|*.spec.ts|*_test.py|*_test.go",
  "relatedFiles": ["src/services/auth.ts", "tests/auth.test.ts"]
}
```

## Step 5: Reproduce Issue (Bugs Only)

**Skip this step for features and refactors.**

For bugs, attempt to reproduce the issue:

### Optional: Start Development Server

If `qa.tdd.autoStartServer: true`:

```bash
# Detect and start dev server (background)
npm run dev &
# or
pnpm dev &
# Wait for server to be ready
sleep 5
```

### Manual Reproduction

Ask the user to confirm the bug reproduction:

**Question**: "Can you reproduce the bug? Describe the steps and current behavior."

**Options:**
1. Yes, I can reproduce it
2. No, let me try first
3. Skip reproduction (proceed to tests)

### Document Expected vs Actual

If user reproduces:

```json
{
  "reproduction": {
    "steps": ["Step 1", "Step 2"],
    "currentBehavior": "What happens now",
    "expectedBehavior": "What should happen"
  }
}
```

## Step 6: TDD RED Phase - Write Failing Tests

### Create Test File

If test file doesn't exist, create it following project conventions:

```bash
# Determine test file location
# Based on source file: src/services/auth.ts -> tests/services/auth.test.ts
# Or co-located: src/services/auth.ts -> src/services/auth.test.ts
```

### Generate Test Cases

Based on ticket acceptance criteria, generate failing tests:

**For Bugs:**
```typescript
describe('AuthService', () => {
  describe('login', () => {
    it('should complete within 3 seconds', async () => {
      // TC-001: Performance requirement
      const startTime = Date.now();
      await authService.login(credentials);
      const elapsed = Date.now() - startTime;
      expect(elapsed).toBeLessThan(3000);
    });

    it('should show friendly message on timeout', async () => {
      // TC-002: User experience requirement
      // Simulate timeout scenario
      const result = await authService.loginWithTimeout(credentials, 100);
      expect(result.error).toBe('Login is taking longer than expected. Please try again.');
    });
  });
});
```

**For Features:**
```typescript
describe('NewFeature', () => {
  it('should satisfy acceptance criteria 1', () => {
    // AC-001: Description from ticket
    expect(feature.behavior()).toBe(expected);
  });

  it('should satisfy acceptance criteria 2', () => {
    // AC-002: Description from ticket
    expect(feature.otherBehavior()).toBe(expected);
  });
});
```

### Run Tests - Verify RED

```bash
# Run the specific test file
{TEST_COMMAND} {TEST_FILE}

# Example:
# npm test -- tests/auth.test.ts
# pnpm vitest run tests/auth.test.ts
# pytest tests/test_auth.py
```

**Expected:** Tests should FAIL (RED phase)

### Handle Unexpected Results

| Result | Action |
| ------ | ------ |
| Tests fail (expected) | Proceed to GREEN phase |
| Tests pass | Warning: "Tests pass but shouldn't. Is the issue already fixed?" |
| Syntax errors | Fix test syntax, retry |
| Import errors | Fix imports, retry |

**If tests pass unexpectedly:**

**Question**: "The tests pass, but we expected them to fail. What should we do?"

**Options:**
1. Issue is already fixed - verify and close
2. Tests are incorrect - adjust test assertions
3. Different test needed - rewrite tests
4. Proceed anyway

**Max Attempts:**

Track attempts (default: `maxRedAttempts: 3`). If max reached:

**Question**: "Failed to achieve RED phase after {N} attempts. How should we proceed?"

**Options:**
1. Continue trying with guidance
2. Skip to implementation
3. Abort TDD workflow

## Step 7: TDD GREEN Phase - Implement Code

### Confirmation (If Configured)

If `qa.tdd.confirmBeforeGreen: true`:

**Question**: "RED phase complete. Tests are failing as expected. Proceed to GREEN phase?"

**Options:**
1. Yes, implement the fix/feature
2. Review tests first
3. Add more tests before implementing

### Implement Minimum Code

Write the minimum code necessary to make tests pass:

**Guidelines:**
- Focus only on passing the tests
- Don't add extra functionality
- Don't optimize yet
- Don't refactor yet

### Run Tests - Verify GREEN

```bash
# Run tests again
{TEST_COMMAND} {TEST_FILE}
```

**Expected:** Tests should PASS (GREEN phase)

### Handle Failures

If tests still fail:

1. Analyze error messages
2. Fix implementation
3. Re-run tests
4. Repeat until green

Track attempts. If struggling:

**Question**: "Tests are still failing. Need help troubleshooting?"

**Options:**
1. Show me the errors - I'll help debug
2. I'll fix it manually
3. Skip to refactor phase anyway

### Optional: Run Full Suite

If `qa.tdd.runFullSuiteEachPhase: true`:

```bash
# Run full test suite
{TEST_COMMAND}
```

Ensure no regressions were introduced.

## Step 8: TDD REFACTOR Phase - Clean Up

### Confirmation (If Configured)

If `qa.tdd.confirmBeforeRefactor: true`:

**Question**: "GREEN phase complete. All tests pass. Proceed to REFACTOR phase?"

**Options:**
1. Yes, clean up the code
2. Skip refactoring - code is good enough
3. Add more tests first

### Refactoring Guidelines

Review and improve the implementation:

**Check for:**
- Code duplication
- Long methods/functions
- Poor naming
- Missing error handling
- Performance issues
- Type safety

**Do NOT:**
- Add new functionality
- Change behavior
- Break existing tests

### Run Tests After Each Change

After each refactoring change:

```bash
{TEST_COMMAND} {TEST_FILE}
```

Ensure tests remain GREEN throughout refactoring.

## Step 9: Final Verification

### Run Full Test Suite

```bash
# Run all tests
{FULL_TEST_COMMAND}

# Examples:
# npm test
# pnpm test
# pytest
# cargo test
# go test ./...
```

### Run Linting

```bash
# Auto-detected or from config
{LINT_COMMAND}

# Examples:
# npm run lint
# pnpm lint
# ruff check .
# cargo clippy
```

### Run Type Check (If Applicable)

```bash
# TypeScript
npx tsc --noEmit

# Python (mypy)
mypy .
```

### Summary of Checks

| Check | Status | Notes |
| ----- | ------ | ----- |
| New tests | PASS | {N} tests added |
| Full suite | PASS | {M} total tests |
| Linting | PASS | No issues |
| Type check | PASS | No errors |

## Step 10: Update Context

Update `.claude/.pr-context.json` with TDD information:

```json
{
  "ticket_id": "PROJ-1234",
  "ticket_url": "https://...",
  "ticket_title": "Title from ticket",
  "branch": "fix/proj-1234-description",
  "type": "fix",
  "description": "Description",
  "started_at": "2025-01-17T12:00:00Z",
  "tdd": {
    "test_files": ["tests/auth/login.test.ts"],
    "implementation_files": ["src/services/auth.ts"],
    "tests_added": 2,
    "tests_modified": 0,
    "phases_completed": ["red", "green", "refactor"],
    "completed_at": "2025-01-17T14:30:00Z"
  }
}
```

This enables `/commit` to generate better commit messages and `/finish` to include TDD summary in PR description.

## Step 11: Summary

Output a completion summary:

```text
TDD Workflow Complete!

Ticket: {TICKET_ID} - {TICKET_TITLE}
Type: {bug|feature|refactor}

Phases Completed:
  RED    - Wrote failing tests
  GREEN  - Implemented passing code
  REFACTOR - Cleaned up code

Files Changed:
  Tests:
    + tests/auth/login.test.ts (new, 2 test cases)
  Implementation:
    ~ src/services/auth.ts (modified)

Test Results:
  New tests: 2 added, 0 modified
  Full suite: 156 tests passing

Next Steps:
  1. Review the changes: git diff
  2. Commit: /commit
  3. Create PR: /finish
```

## Configuration Reference

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `qa.tdd.confirmBeforeGreen` | `true` | Pause for confirmation before GREEN phase |
| `qa.tdd.confirmBeforeRefactor` | `true` | Pause for confirmation before REFACTOR phase |
| `qa.tdd.maxRedAttempts` | `3` | Maximum attempts to achieve RED (failing tests) |
| `qa.tdd.runFullSuiteEachPhase` | `false` | Run full test suite after each phase |
| `qa.tdd.autoStartServer` | `false` | Auto-start dev server for bug reproduction |

## Error Handling

| Scenario | Action |
| -------- | ------ |
| Ticket ID not provided | Prompt for ticket ID |
| Ticket not found | Error with suggestion to check ID |
| Tests pass in RED phase | Warn, ask to adjust tests or confirm already fixed |
| Tests fail in GREEN phase | Show errors, retry implementation |
| Max attempts reached | Ask user for guidance |
| Test framework not detected | Ask user for test command |
| No acceptance criteria | Ask user to define test cases |

## Examples

### Bug Fix Flow

```text
User: /tdd ENG-456

Agent: [Fetches ticket from Linear]
  Ticket: ENG-456 - Login times out after 10 seconds
  Type: Bug

Agent: [Explores codebase]
  Found: src/services/auth.ts, tests/auth.test.ts
  Framework: Vitest

Agent: Can you reproduce the bug?
User: Yes, login takes 15+ seconds

Agent: RED Phase - Writing failing tests...
  Creating tests/auth/login.test.ts:
  - TC-001: Login should complete within 3 seconds
  - TC-002: Timeout should show friendly message

  Running tests...
  FAIL: 2 tests failed (as expected)

Agent: Proceed to GREEN phase? [Yes/No]
User: Yes

Agent: GREEN Phase - Implementing fix...
  Modified: src/services/auth.ts
  - Added connection pooling
  - Added timeout handling

  Running tests...
  PASS: 2 tests passing

Agent: Proceed to REFACTOR? [Yes/Skip]
User: Yes

Agent: REFACTOR Phase - Cleaning up...
  - Extracted timeout logic to utility function
  - Added JSDoc comments

  Running tests...
  PASS: All tests still passing

Agent: TDD Complete!
  Files: tests/auth/login.test.ts (new), src/services/auth.ts (modified)
  Next: /commit → /finish
```

### Feature Flow

```text
User: /tdd PROJ-789

Agent: [Fetches ticket]
  Ticket: PROJ-789 - Add dark mode support
  Type: Feature

  Acceptance Criteria:
  - User can toggle dark mode
  - Preference is persisted
  - All components respect theme

Agent: RED Phase - Writing failing tests...
  - TC-001: Toggle should switch theme
  - TC-002: Theme persists across sessions
  - TC-003: Components use theme colors

  FAIL: 3 tests failed (expected)

Agent: Proceed to GREEN?
User: Yes

Agent: [Implements feature]
  PASS: 3 tests passing

Agent: Proceed to REFACTOR?
User: Skip

Agent: TDD Complete!
```

### No Ticket Flow

```text
User: /tdd

Agent: What is the ticket ID?
User: ENG-123

Agent: [Continues with normal flow...]
```
