# Sample Generated Tests

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

# Sample Completion Summary

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

# Examples

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
