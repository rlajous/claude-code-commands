# Review Lenses

The dimensions the general `pr-reviewer` pass (and your own synthesis) applies. The specialized agents own their narrow lens; use this list to fill gaps they don't cover (security, data integrity, performance, architecture).

### Architecture & Design

- Does the change follow existing patterns in the codebase?
- Is there proper separation of concerns?
- Are dependencies flowing in the right direction?
- Is coupling appropriate or excessive?
- Are new abstractions justified?

### Business Logic & Correctness

- Trace the execution end-to-end from entry point to response
- Check edge cases: empty inputs, null values, boundary conditions
- Look for race conditions in concurrent operations
- Verify state transitions are valid
- Check that error paths don't leave data in an inconsistent state

### Data Integrity

- Are database operations wrapped in transactions where needed?
- Is idempotency handled for operations that could retry?
- What happens on partial failure?
- Are foreign key relationships maintained?

### Error Handling & Resilience

- Are errors caught at appropriate levels?
- Do catch blocks handle errors meaningfully (not silently swallowed)?
- Are retries implemented where appropriate?
- Are error messages helpful for debugging?
- Are external service failures handled gracefully?

### Security & Validation

- Is user input validated before use?
- Are there injection risks (SQL, command, template)?
- Are secrets kept out of code and logs?
- Are authentication/authorization checks in place?
- Is sensitive data properly handled (no logging PII, proper encryption)?

### Performance

- Are there N+1 query patterns?
- Could operations be batched?
- Are there memory concerns with large datasets?
- Are blocking operations in async contexts?
- Are expensive operations cached where appropriate?

### Testing

- Are there tests for the new functionality?
- Do tests cover edge cases and error scenarios?
- Are tests testing behavior, not implementation details?
- Is test coverage adequate for the risk level of the change?

### Code Quality

- Does naming follow project conventions?
- Is there dead code or unnecessary complexity?
- Are comments used appropriately (explaining why, not what)?
- Is the code readable and maintainable?
