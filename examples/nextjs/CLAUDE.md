# CLAUDE.md

This file provides guidance to Claude Code when working with this Next.js project.

## Project Overview

A Next.js 14 application with App Router, TypeScript, Tailwind CSS, and comprehensive component library.

**Tech Stack:**

- Framework: Next.js 14 (App Router)
- Language: TypeScript 5
- Styling: Tailwind CSS, shadcn/ui
- State: Zustand / React Query
- Package Manager: pnpm
- Testing: Vitest, Playwright

## Development Commands

```bash
# Install dependencies
pnpm install

# Run development server
pnpm dev

# Run tests
pnpm test              # Unit tests with Vitest
pnpm test:e2e          # E2E tests with Playwright

# Type checking
pnpm typecheck

# Linting & formatting
pnpm lint
pnpm format

# Build
pnpm build
pnpm start             # Start production server
```

## Project Structure

```
app/
├── (auth)/            # Auth route group
│   ├── login/
│   └── register/
├── (dashboard)/       # Dashboard route group
│   ├── layout.tsx
│   └── page.tsx
├── api/               # API routes
├── layout.tsx         # Root layout
└── page.tsx           # Home page

components/
├── ui/                # shadcn/ui components
├── features/          # Feature-specific components
└── layouts/           # Layout components

lib/
├── api/               # API client
├── hooks/             # Custom hooks
├── utils/             # Utility functions
└── validations/       # Zod schemas

styles/
└── globals.css        # Global styles
```

## Git Workflow

Uses Conventional Commits with develop branch workflow:

- `/start` → Create branch from GitHub issue
- `/commit` → Commit with `type: message (ISSUE-ID)` format
- `/finish` → Create PR to develop
- `/release` → Create release from develop to main

## Code Standards

### Component Structure

```tsx
// components/features/UserCard.tsx
interface UserCardProps {
  user: User;
  onEdit?: () => void;
}

export function UserCard({ user, onEdit }: UserCardProps) {
  // Implementation
}
```

### File Naming

- Components: PascalCase (`UserCard.tsx`)
- Utilities: camelCase (`formatDate.ts`)
- Hooks: camelCase with `use` prefix (`useAuth.ts`)
- Types: PascalCase (`User.ts`)

### Testing

- Unit tests alongside components: `Component.test.tsx`
- E2E tests in `e2e/` directory
- Use React Testing Library
- Test user interactions, not implementation

## Environment Variables

```bash
# Required
NEXT_PUBLIC_API_URL=https://api.example.com
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Auth
NEXTAUTH_SECRET=your-secret
NEXTAUTH_URL=http://localhost:3000

# Optional
NEXT_PUBLIC_ANALYTICS_ID=
```

## Styling Guidelines

- Use Tailwind utility classes
- Create component variants with cva
- Use CSS variables for theming
- Mobile-first responsive design

## Component Library

Using shadcn/ui. Add components:

```bash
pnpm dlx shadcn-ui@latest add button
pnpm dlx shadcn-ui@latest add card
```

Components are added to `components/ui/`.
