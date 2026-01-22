# CLAUDE.md

This file provides guidance to Claude Code when working with this monorepo.

## Project Overview

A Turborepo monorepo containing multiple apps and shared packages with unified tooling.

**Tech Stack:**

- Build System: Turborepo
- Package Manager: pnpm (workspaces)
- Languages: TypeScript
- Apps: Next.js, NestJS, React Native
- Packages: Shared UI, Config, Types

## Workspace Structure

```
├── apps/
│   ├── web/              # Next.js frontend
│   ├── api/              # NestJS backend
│   ├── mobile/           # React Native app
│   └── docs/             # Documentation site
├── packages/
│   ├── ui/               # Shared UI components
│   ├── config/           # Shared configs (ESLint, TS, etc.)
│   ├── types/            # Shared TypeScript types
│   └── utils/            # Shared utilities
├── turbo.json            # Turborepo config
├── pnpm-workspace.yaml   # Workspace config
└── package.json          # Root package
```

## Development Commands

```bash
# Install all dependencies
pnpm install

# Run all apps in development
pnpm dev

# Run specific app
pnpm dev --filter web
pnpm dev --filter api
pnpm dev --filter mobile

# Build all
pnpm build

# Build specific package/app
pnpm build --filter @repo/ui
pnpm build --filter web

# Run tests
pnpm test                     # All packages
pnpm test --filter api        # Specific package

# Linting
pnpm lint
pnpm lint --filter web

# Type checking
pnpm typecheck
```

## Git Workflow

Uses scoped Conventional Commits:

```
feat(web): add user dashboard
fix(api): resolve auth token expiry
chore(deps): update dependencies
```

Scopes match workspace names: `web`, `api`, `mobile`, `ui`, `types`, etc.

## Package Dependencies

### Adding Dependencies

```bash
# Add to specific workspace
pnpm add lodash --filter web

# Add dev dependency
pnpm add -D vitest --filter api

# Add shared package
pnpm add @repo/ui --filter web --workspace

# Add to root (shared dev tools)
pnpm add -Dw turbo
```

### Internal Package References

```json
// apps/web/package.json
{
  "dependencies": {
    "@repo/ui": "workspace:*",
    "@repo/types": "workspace:*"
  }
}
```

## Turborepo Pipeline

```json
// turbo.json
{
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**"]
    },
    "test": {
      "dependsOn": ["build"]
    },
    "lint": {},
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

## Code Standards

### Shared Code

- Put shared types in `packages/types`
- Put shared UI in `packages/ui`
- Put shared configs in `packages/config`

### Package-Specific

Each package has its own:

- `tsconfig.json` (extends shared config)
- `.eslintrc.js` (extends shared config)
- `package.json` with scripts

### Versioning

All packages use the same version (root `package.json`).

## Environment Variables

Each app has its own `.env`:

```
apps/web/.env
apps/api/.env
apps/mobile/.env.local
```

Shared env validation in `packages/config/env.ts`.

## CI/CD

GitHub Actions with Turborepo remote caching:

```yaml
- name: Build
  run: pnpm build
  env:
    TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
    TURBO_TEAM: ${{ vars.TURBO_TEAM }}
```

## Common Tasks

### Adding a New Package

```bash
# Create package directory
mkdir -p packages/new-package

# Initialize
cd packages/new-package
pnpm init

# Add to workspace (automatic with pnpm)
```

### Adding a New App

```bash
# Create with template
pnpm create next-app apps/new-web --typescript
```

### Updating All Dependencies

```bash
pnpm update --recursive --interactive
```
