# /start-qa

Execute QA tests from a test plan file.

## Arguments

Parse from `$ARGUMENTS`:

- **Test file path**: Direct path to YAML file
- **Or ticket ID**: Find `tests/qa/<ticket-id>-test.yaml`
- **Or "latest"**: Use most recently modified test file in `tests/qa/`

```
$ARGUMENTS
```

## Workflow

1. **Locate test file**:

   - If path provided: Use directly
   - If ticket ID (e.g., TEAM-123): Look for `tests/qa/TEAM-123-test.yaml`
   - If "latest" or empty: Find newest `.yaml` in `tests/qa/`

2. **Read and parse test file**:

   - Load YAML configuration
   - Extract base_url, test_cases, sqs_assertions

3. **Execute each test case** using MCP tools:

   For each test case:

   ```
   check_api_access(
     base_url=<from config>,
     method=<test_case.method>,
     path=<test_case.endpoint with params substituted>,
     timeout=<test_case.timeout or 10.0>
   )
   ```

4. **Verify SQS assertions** (if defined):

   ```
   verify_sqs_message(
     queue_url=<assertion.queue_url>,
     match_mode=<assertion.match_mode>,
     expected_content=<assertion.expected_content>,
     expected_fields=<assertion.expected_fields>,
     timeout_seconds=<assertion.timeout_seconds>
   )
   ```

5. **Report results**:

   ```
   ═══════════════════════════════════════════════════
   QA Test Results: <test name>
   ═══════════════════════════════════════════════════

   Test Cases: X/Y passed
   SQS Checks: X/Y passed

   ┌─────────┬────────────────────────┬────────┬─────────┐
   │ ID      │ Name                   │ Status │ Time    │
   ├─────────┼────────────────────────┼────────┼─────────┤
   │ TC-001  │ Happy path             │ PASS   │ 150ms   │
   │ TC-002  │ Invalid input          │ PASS   │ 45ms    │
   │ TC-003  │ Missing auth           │ FAIL   │ 32ms    │
   └─────────┴────────────────────────┴────────┴─────────┘

   Failed Tests:
   - TC-003: Expected 401, got 200

   SQS Assertions:
   - EVENT_PUBLISHED: PASS (found in 2.3s)

   ═══════════════════════════════════════════════════
   Overall: FAIL (2/3 passed)
   ═══════════════════════════════════════════════════
   ```

6. **Save results** to `tests/qa/results/<test-name>-<timestamp>.json`

## Example Usage

```
/start-qa                           # Run latest test file
/start-qa TEAM-123                   # Run tests/qa/TEAM-123-test.yaml
/start-qa tests/qa/risk-test.yaml   # Run specific file
```

## Test File Format

Expected YAML structure:

```yaml
name: 'Test Name'
base_url: '${API_BASE_URL}'

test_cases:
  - id: TC-001
    name: 'Test name'
    endpoint: /path/{param}
    method: GET
    params:
      param: value
    expected_status: 200
    expected_response:
      field: expected_value
    priority: high

sqs_assertions:
  - queue_url: '${SQS_QUEUE}'
    match_mode: json_field
    expected_fields:
      event_type: 'EVENT_NAME'
```

## Pre-approved Tools

Uses MCP tools:

- `mcp__ai-qa-tools__check_api_access`
- `mcp__ai-qa-tools__verify_sqs_message`
