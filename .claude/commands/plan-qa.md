# /plan-qa

Generate a QA test plan file from task description, Linear ticket, or requirements.

## Arguments

Parse the following from `$ARGUMENTS`:

- **Ticket ID**: Pattern `[A-Z]+-\d+` (e.g., PROJ-123)
- **SQS queue**: Pattern `--sqs <queue_url>` or `--sqs-env <ENV_VAR_NAME>`
- **Base URL**: Pattern `--url <base_url>` (defaults to API_BASE_URL env)
- **Description**: Remaining text after extracting above

## Workflow

1. **Extract inputs from arguments**

   ```
   $ARGUMENTS
   ```

2. **If ticket ID found**, fetch ticket details:

   - Use issue tracker MCP tool or API to fetch ticket
   - Extract: title, description, acceptance criteria from comments
   - Identify endpoints mentioned in description

3. **Analyze requirements** to identify:

   - Endpoints to test (method + path)
   - Expected status codes
   - Request parameters/body
   - Expected response fields
   - SQS events to verify (if applicable)

4. **Generate test file** at `tests/qa/<ticket-id or slug>-test.yaml`:

```yaml
# Auto-generated QA Test Plan
# Generated: <timestamp>
# Source: <linear ticket or description>

name: '<descriptive name>'
type: feature # feature | bug_fix | regression
description: |
  <extracted from ticket/description>

# Base configuration
base_url: '${API_BASE_URL}' # or provided URL
model: llama-4-maverick

# Endpoints under test
endpoints:
  - path: <endpoint path>
    method: <GET|POST|PUT|DELETE>
    description: '<what this endpoint does>'

# Test cases
test_cases:
  # Happy path
  - id: TC-001
    name: '<descriptive name>'
    endpoint: <path>
    method: <method>
    params: {}
    expected_status: 200
    expected_response:
      # key assertions
    priority: high
    tags: [smoke, happy-path]

  # Error cases
  - id: TC-002
    name: 'Invalid input returns 400'
    # ...

# SQS assertions (if applicable)
sqs_assertions:
  - queue_url: '${SQS_QUEUE_URL}' # or provided queue
    match_mode: json_field
    expected_fields:
      event_type: '<expected event>'
    timeout_seconds: 30

# Acceptance criteria (from ticket)
acceptance_criteria:
  - '<AC 1>'
  - '<AC 2>'
```

5. **Output**:
   - Print path to generated test file
   - Summarize: number of test cases, endpoints covered, SQS checks

## Example Usage

```
/plan-qa PROJ-123
/plan-qa PROJ-456 --sqs-env SQS_EVENTS_QUEUE
/plan-qa Test the new /v2/risk endpoint returns risk scores 0-100
/plan-qa PROJ-789 --url https://staging-api.example.com
```

## Output Location

Save test files to: `tests/qa/<slug>-test.yaml`

Where `<slug>` is:

- Ticket ID lowercase (e.g., `proj-123-test.yaml`)
- Or kebab-case from description (e.g., `risk-endpoint-test.yaml`)
