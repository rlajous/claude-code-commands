# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Claude Code slash commands (`.md` files in `commands/`) that automate PR and release workflows. These commands are meant to be copied to a project's `.claude/commands/` directory.

## Command Files

All commands are in the `commands/` directory. Each `.md` file defines a slash command:

- **`/start`** - Create feature branch from ticket ID
- **`/commit`** - Stage and commit with formatted message `[Type] Summary (TICKET-ID)`
- **`/finish`** - Push branch and create PR to staging
- **`/release`** - Create release branch, bump version, PR to main
- **`/release-notes`** - Enhance GitHub release with detailed notes
- **`/sync`** - Back-merge main to staging post-release
- **`/plan-qa`** - Generate QA test plan YAML from ticket
- **`/start-qa`** - Execute QA tests from plan file

## Workflow

Standard PR flow: `/start` → make changes → `/commit` → `/finish`

Release flow: `/release` → merge → `/release-notes` → `/sync`

## Configuration Points

Commands use placeholders that users should customize:
- `PROJ-XXXX` - Ticket ID format (e.g., JIRA-123, LINEAR-456)
- `your-org/engineers` - GitHub reviewer team
- `your-issue-tracker.com` - Issue tracker URL
- `API_BASE_URL` - Environment variable for API testing
- `docs/openapi.json` - OpenAPI spec path in `/release`

## PR Context

Commands store state in `.claude/.pr-context.json` with ticket ID, branch name, and timestamps. This file persists across `/start`, `/commit`, and `/finish`.
