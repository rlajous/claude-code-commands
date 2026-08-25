# Subagents Reference

Subagents are specialized AI assistants that can be invoked to handle specific tasks. They have their own instructions, tool access, and can run in isolated contexts.

**Official Documentation**: https://code.claude.com/docs/en/sub-agents

## Overview

Subagents are defined as markdown files in `.claude/agents/` with YAML frontmatter. They can be:

- Invoked automatically by Claude when relevant
- Called explicitly by the user
- Used proactively for specific tasks

## Available Subagents

This repository includes eight specialized subagents:

| Agent | Purpose | Tools |
|-------|---------|-------|
| `pr-reviewer` | Code review for quality and security | Read, Grep, Glob |
| `release-validator` | Pre-release validation checks | Read, Grep, Glob, Bash |
| `qa-executor` | QA test execution and reporting | Read, Bash, WebFetch |
| `silent-failure-hunter` | Hunts swallowed errors, over-broad catch blocks, and silent fallbacks in changed code | Read, Grep, Glob |
| `type-design-analyzer` | Rates type design: encapsulation, invariant expression, usefulness, enforcement (1-10 each) | Read, Grep, Glob |
| `pr-test-analyzer` | Finds behavioral test-coverage gaps, rating each missing test's criticality and the regression it catches | Read, Grep, Glob |
| `comment-analyzer` | Detects comment rot and docstrings that no longer match the code | Read, Grep, Glob |
| `version-delta-analyst` | Catalogs breaking changes, deprecations, and migration steps between two versions of a dependency/stack/API | Read, Grep, Glob, Bash, WebFetch |

## Agent Configuration

### Frontmatter Fields

```yaml
---
name: agent-name
description: What this agent does and when to use it
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique identifier for the agent |
| `description` | string | What the agent does (used for auto-invocation) |
| `tools` | string | Comma-separated list of allowed tools |
| `model` | string | Model to use: `sonnet`, `opus`, or `haiku` |

### Tool Options

| Tool | Description |
|------|-------------|
| `Read` | Read files |
| `Grep` | Search file contents |
| `Glob` | Find files by pattern |
| `Bash` | Execute shell commands |
| `Write` | Create/overwrite files |
| `Edit` | Edit existing files |
| `WebFetch` | Fetch web content |
| `AskUserQuestion` | Ask user for input |

## Included Agents

### PR Reviewer

**File**: `.claude/agents/pr-reviewer.md`

**Purpose**: Expert code reviewer that analyzes changes for:

- Code quality and readability
- Security vulnerabilities
- Performance issues
- Test coverage
- Documentation

**Usage**:
```
Review the code changes in this PR
```

**Output**: Structured review with issues categorized by severity.

> **Tip**: For a full step-by-step review workflow with GitHub integration, use the `/review` command instead. It provides a structured process that fetches PR metadata, reads full source files, produces a detailed review document, and optionally posts the review to GitHub.

### Release Validator

**File**: `.claude/agents/release-validator.md`

**Purpose**: Pre-release validation that checks:

- Version is set correctly
- Tests pass
- Build succeeds
- Linting passes
- Type checking passes
- No vulnerable dependencies
- Changelog is updated
- Git state is clean

**Usage**:
```
Validate this release is ready
```

**Output**: Validation report with pass/fail status and recommendations.

### QA Executor

**File**: `.claude/agents/qa-executor.md`

**Purpose**: Executes QA test plans with:

- HTTP request execution
- Response validation
- SQS event verification
- Detailed reporting

**Usage**:
```
Execute the QA tests in tests/qa/proj-123-test.yaml
```

**Output**: Test execution report with pass/fail status and failure details.

### Silent Failure Hunter

**File**: `.claude/agents/silent-failure-hunter.md`

**Purpose**: Hunts for silent failures and inadequate error handling in changed code:

- Empty or overly broad catch blocks
- Errors logged but not surfaced to users
- Unjustified fallback behavior that masks real problems
- Missing or unhelpful error messages

**Usage**:
```
Review this PR for silent failures and error handling issues
```

**Output**: Findings by severity (CRITICAL/HIGH/MEDIUM) with file:line locations and recommended fixes.

### Type Design Analyzer

**File**: `.claude/agents/type-design-analyzer.md`

**Purpose**: Analyzes type design quality for new or modified types:

- Encapsulation
- Invariant expression
- Invariant usefulness
- Invariant enforcement

**Usage**:
```
Analyze the type design of the new types in this PR
```

**Output**: Per-type report with 1-10 ratings on each axis, strengths, concerns, and recommended improvements.

### PR Test Analyzer

**File**: `.claude/agents/pr-test-analyzer.md`

**Purpose**: Reviews a pull request for behavioral test-coverage gaps:

- Untested error handling and edge cases
- Missing negative/validation test cases
- Tests that are brittle or overfit to implementation

**Usage**:
```
Check whether the tests in this PR are thorough
```

**Output**: Coverage summary with critical/important gaps, each rated 1-10 for criticality and mapped to the regression it would catch.

### Comment Analyzer

**File**: `.claude/agents/comment-analyzer.md`

**Purpose**: Detects comment rot and inaccurate documentation:

- Comments/docstrings that no longer match the code
- Misleading or ambiguous wording
- Comments that add no value and should be removed

**Usage**:
```
Check the comments added in this PR for accuracy
```

**Output**: Critical issues, improvement opportunities, and recommended removals, each with file:line references. Advisory only — does not modify code.

### Version Delta Analyst

**File**: `.claude/agents/version-delta-analyst.md`

**Purpose**: Catalogs what changed between two versions of a dependency, framework, or API for release documentation:

- Breaking changes with severity ratings
- Deprecations and removal timelines
- Behavioral changes that don't break builds but could surprise consumers
- A concrete migration checklist

**Usage**:
```
Compare our ORM v4 to v6 and list what will break
```

**Output**: Version delta report with breaking changes, deprecations, behavioral changes, assumptions/gaps, and a migration checklist.

## Creating Custom Agents

### 1. Create the Agent File

Create a markdown file in `.claude/agents/`:

```markdown
---
name: my-custom-agent
description: What this agent does
tools: Read, Grep, Glob
model: sonnet
---

You are a specialized agent for [purpose].

## Your Role

[Detailed instructions for the agent]

## Process

1. [Step 1]
2. [Step 2]
3. [Step 3]

## Output Format

[Expected output format]
```

### 2. Define Clear Instructions

Be specific about:

- What the agent should do
- What tools it should use
- What output format to use
- What edge cases to handle

### 3. Limit Tool Access

Only grant tools the agent needs:

```yaml
# Read-only agent
tools: Read, Grep, Glob

# Agent that can modify files
tools: Read, Grep, Glob, Write, Edit

# Agent with shell access
tools: Read, Grep, Glob, Bash
```

### 4. Choose the Right Model

| Model | Best For |
|-------|----------|
| `haiku` | Simple, fast tasks |
| `sonnet` | Balanced performance |
| `opus` | Complex reasoning |

## Agent Directory Structure

```
.claude/
├── agents/
│   ├── pr-reviewer.md
│   ├── release-validator.md
│   ├── qa-executor.md
│   ├── silent-failure-hunter.md
│   ├── type-design-analyzer.md
│   ├── pr-test-analyzer.md
│   ├── comment-analyzer.md
│   ├── version-delta-analyst.md
│   └── your-custom-agent.md
└── skills/
    └── ...
```

## Using Agents

### Automatic Invocation

Agents with descriptive `description` fields can be auto-invoked when relevant:

```yaml
description: Expert code reviewer. Use proactively after code changes to review for quality.
```

### Explicit Invocation

Reference agents in conversation:

```
Use the pr-reviewer agent to review these changes
```

### From Commands

Commands can reference agents in their instructions:

```markdown
Use the release-validator agent to verify release readiness.
```

## Best Practices

### 1. Single Responsibility

Each agent should have one clear purpose:

```yaml
# Good
description: Validates release readiness

# Too broad
description: Handles all release and deployment tasks
```

### 2. Clear Output Format

Define the expected output format in the agent:

```markdown
## Output Format

```markdown
## Review Summary
- Issues found: {count}
- Recommendation: {APPROVE|REQUEST CHANGES}
```
```

### 3. Defensive Instructions

Include error handling guidance:

```markdown
## Error Handling

- If files cannot be read, report the error and continue
- If tests fail, show the failure details
- If environment is missing, list required variables
```

### 4. Use Proactive Descriptions

For agents that should be used automatically:

```yaml
description: Use proactively after code changes to review for quality, security, and best practices.
```

### 5. Document Dependencies

List what the agent needs to function:

```markdown
## Requirements

- Git repository with commits
- Node.js installed for npm commands
- Environment variables: API_TOKEN
```

## Troubleshooting

### Agent Not Found

1. Verify file is in `.claude/agents/`
2. Check file has `.md` extension
3. Verify YAML frontmatter is valid

### Agent Missing Tools

1. Check `tools` field in frontmatter
2. Verify tool names are spelled correctly
3. Tools are comma-separated

### Agent Not Auto-Invoked

1. Check `description` is descriptive
2. Verify the task matches the description
3. Try explicit invocation

## Examples

### Security Auditor Agent

```markdown
---
name: security-auditor
description: Security specialist. Use to audit code for vulnerabilities.
tools: Read, Grep, Glob
model: sonnet
---

You are a security specialist focused on identifying vulnerabilities.

## Focus Areas

1. **Input Validation**: Check all user inputs are validated
2. **Authentication**: Verify auth is properly implemented
3. **Authorization**: Check access controls
4. **Secrets**: Look for hardcoded credentials
5. **Dependencies**: Check for known vulnerabilities

## Output

Provide a security report with:
- Critical issues (must fix)
- Warnings (should fix)
- Recommendations (consider)
```

### Documentation Generator Agent

```markdown
---
name: doc-generator
description: Documentation specialist. Use to generate or update documentation.
tools: Read, Grep, Glob, Write
model: sonnet
---

You are a technical writer specializing in developer documentation.

## Tasks

1. Generate API documentation from code
2. Update README files
3. Create usage examples
4. Document configuration options

## Style Guide

- Use clear, concise language
- Include code examples
- Follow existing documentation style
```
