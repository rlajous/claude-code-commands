---
description: Generate QA test plan YAML from ticket
argument-hint: "<ticket-id> [--url <url>]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, WebFetch, Write, Bash
user-invocable: true
---

You are helping generate a QA test plan from a ticket description, issue tracker ticket, or requirements. This command creates a structured YAML test plan that can be executed with `/start-qa`.

## Step 1: Load Configuration

Check for configuration:

```bash
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
qa:
  apiBaseUrl: ${API_BASE_URL}
  testPlansDir: tests/qa
  resultsDir: tests/qa/results
  timeout: 10
  sqsQueueUrl: ${SQS_QUEUE_URL}
issueTracker:
  type: auto
```

**Default Values:**

```yaml
qa:
  apiBaseUrl: http://localhost:3000
  testPlansDir: tests/qa
  timeout: 10
```

## Step 2: Parse Arguments

Extract from `$ARGUMENTS`:

```
$ARGUMENTS
```

**Patterns to Extract:**

| Pattern                    | Example                              | Meaning                 |
| -------------------------- | ------------------------------------ | ----------------------- |
| Ticket ID                  | `PROJ-123`, `ENG-456`                | Issue tracker ticket    |
| `--url <base_url>`         | `--url https://api.example.com`      | Override API base URL   |
| `--sqs <queue_url>`        | `--sqs https://sqs.../queue`         | SQS queue for events    |
| `--sqs-env <VAR_NAME>`     | `--sqs-env SQS_EVENTS_QUEUE`         | SQS queue from env var  |
| Remaining text             | `Test the /v2/risk endpoint`         | Task description        |

**Parsing Logic:**

```javascript
// Extract ticket ID
const ticketMatch = args.match(/([A-Z]+-\d+)/);
const ticketId = ticketMatch ? ticketMatch[1] : null;

// Extract URL override
const urlMatch = args.match(/--url\s+(\S+)/);
const baseUrl = urlMatch ? urlMatch[1] : config.qa.apiBaseUrl;

// Extract SQS queue
const sqsMatch = args.match(/--sqs\s+(\S+)/);
const sqsEnvMatch = args.match(/--sqs-env\s+(\S+)/);
const sqsQueue = sqsMatch ? sqsMatch[1] : sqsEnvMatch ? `\${${sqsEnvMatch[1]}}` : null;

// Remaining is description
const description = args.replace(ticketMatch, '').replace(urlMatch, '').trim();
```

## Step 3: Fetch Ticket Details (If ID Provided)

### Linear Integration (via MCP)

If ticket matches Linear format, use the Linear MCP server:

```
mcp__linear__get_issue(id: ticketId)
```

Extract:

- Title
- Description
- Acceptance criteria (from comments or description)
- Labels/tags

The MCP server handles authentication automatically via OAuth.

### Jira Integration (via MCP)

If Jira configured, use the Jira MCP server:

```
mcp__jira__get_issue(issueKey: ticketId)
```

Extract:

- Summary (title)
- Description
- Acceptance criteria
- Labels

The MCP server handles authentication automatically.

### GitHub Issues

If GitHub issue format (#123), use the `gh` CLI:

```bash
gh issue view ${ISSUE_NUMBER} --json title,body,labels
```

## Step 4: Analyze Requirements

From the ticket or description, identify:

### Endpoints to Test

Look for patterns in description:

- `GET /api/v1/users`
- `POST /endpoint`
- Path patterns: `/v1/`, `/v2/`, `/api/`
- HTTP methods: GET, POST, PUT, PATCH, DELETE

### Expected Behaviors

Extract from acceptance criteria:

- Success conditions
- Error scenarios
- Edge cases
- Authentication requirements

### SQS Events (If Mentioned)

Look for:

- Event names (e.g., "USER_CREATED", "ORDER_PLACED")
- Queue mentions
- Async processing requirements

## Step 5: Generate Test Plan

Create the test plan YAML:

```yaml
# Auto-generated QA Test Plan
# Generated: {ISO_TIMESTAMP}
# Source: {TICKET_ID or "Manual description"}

name: "{DESCRIPTIVE_NAME}"
type: feature # feature | bug_fix | regression | smoke
description: |
  {DESCRIPTION_FROM_TICKET_OR_INPUT}

# Base configuration
base_url: "${API_BASE_URL}" # or explicit URL
timeout: 10 # seconds

# Endpoints under test
endpoints:
  - path: /api/v1/{endpoint}
    method: GET
    description: "{What this endpoint does}"
    auth_required: true

# Test cases
test_cases:
  # Happy path tests
  - id: TC-001
    name: "{Descriptive test name}"
    type: happy_path
    endpoint: /api/v1/{endpoint}
    method: GET
    headers:
      Authorization: "Bearer ${API_TOKEN}"
      Content-Type: application/json
    params:
      key: value
    expected:
      status: 200
      body:
        # Key assertions
        success: true
    priority: high
    tags: [smoke, happy-path]

  # Validation tests
  - id: TC-002
    name: "Invalid input returns 400"
    type: validation
    endpoint: /api/v1/{endpoint}
    method: POST
    body:
      invalid_field: "bad_value"
    expected:
      status: 400
      body:
        error: true
    priority: medium
    tags: [validation]

  # Authentication tests
  - id: TC-003
    name: "Missing auth returns 401"
    type: auth
    endpoint: /api/v1/{endpoint}
    method: GET
    # No Authorization header
    expected:
      status: 401
    priority: high
    tags: [auth, security]

  # Edge cases
  - id: TC-004
    name: "Empty list returns empty array"
    type: edge_case
    endpoint: /api/v1/{endpoint}
    method: GET
    params:
      filter: "nonexistent"
    expected:
      status: 200
      body:
        items: []
    priority: low
    tags: [edge-case]

# SQS assertions (if applicable)
sqs_assertions:
  - name: "Event published after action"
    queue_url: "${SQS_QUEUE_URL}"
    trigger_test: TC-001 # Which test triggers this event
    match_mode: json_field # json_field | contains | exact
    expected_fields:
      event_type: "EVENT_NAME"
      # Additional field assertions
    timeout_seconds: 30
    required: true

# Acceptance criteria (from ticket)
acceptance_criteria:
  - "{AC 1 from ticket}"
  - "{AC 2 from ticket}"
  - "{AC 3 from ticket}"

# Test environment
environment:
  variables:
    - API_BASE_URL
    - API_TOKEN
  setup_commands: []
  cleanup_commands: []
```

## Step 6: Save Test File

Determine file name:

```javascript
// From ticket ID (lowercase)
const slug = ticketId ? ticketId.toLowerCase() : null;

// Or from description (kebab-case)
const descSlug = description
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .slice(0, 50);

const fileName = `${slug || descSlug}-test.yaml`;
```

Save to configured directory:

```bash
TEST_DIR=$(config.qa.testPlansDir || "tests/qa")
mkdir -p ${TEST_DIR}

# Write file
cat > "${TEST_DIR}/${FILE_NAME}" << 'EOF'
{GENERATED_YAML}
EOF
```

## Step 7: Confirm

```
Test plan generated: {TEST_DIR}/{FILE_NAME}

Summary:
- Endpoints: {N} endpoints identified
- Test cases: {M} test cases generated
  - Happy path: {X}
  - Validation: {Y}
  - Auth: {Z}
  - Edge cases: {W}
- SQS assertions: {K}

To run tests:
/start-qa {FILE_NAME}

To edit:
Open {TEST_DIR}/{FILE_NAME} and customize as needed.
```

## Configuration Reference

| Setting             | Default               | Description               |
| ------------------- | --------------------- | ------------------------- |
| `qa.apiBaseUrl`     | `http://localhost:3000` | Default API base URL    |
| `qa.testPlansDir`   | `tests/qa`            | Directory for test plans  |
| `qa.timeout`        | `10`                  | Default timeout (seconds) |
| `qa.sqsQueueUrl`    | -                     | Default SQS queue URL     |

## Examples

### From Ticket ID

```
/plan-qa PROJ-123
```

Fetches ticket from issue tracker and generates test plan.

### From Ticket with SQS

```
/plan-qa PROJ-456 --sqs-env SQS_EVENTS_QUEUE
```

Generates test plan with SQS event assertions.

### From Description

```
/plan-qa Test the new /v2/risk endpoint returns risk scores 0-100
```

Generates test plan from description without ticket.

### With Custom URL

```
/plan-qa PROJ-789 --url https://staging-api.example.com
```

Generates test plan targeting staging environment.

## Test Case Templates

### REST API Endpoint

```yaml
- id: TC-001
  name: "GET users returns paginated list"
  endpoint: /api/v1/users
  method: GET
  params:
    page: 1
    limit: 10
  expected:
    status: 200
    body:
      items: [] # Array of users
      pagination:
        page: 1
        limit: 10
```

### Create Resource

```yaml
- id: TC-002
  name: "POST creates new user"
  endpoint: /api/v1/users
  method: POST
  body:
    email: "test@example.com"
    name: "Test User"
  expected:
    status: 201
    body:
      id: "*" # Any non-null value
      email: "test@example.com"
```

### Error Handling

```yaml
- id: TC-003
  name: "Duplicate email returns 409"
  endpoint: /api/v1/users
  method: POST
  body:
    email: "existing@example.com"
  expected:
    status: 409
    body:
      error: "Email already exists"
```

## Output Location

Test files are saved to: `{qa.testPlansDir}/{slug}-test.yaml`

Where `{slug}` is:

- Ticket ID lowercase (e.g., `proj-123-test.yaml`)
- Or kebab-case from description (e.g., `risk-endpoint-test.yaml`)
