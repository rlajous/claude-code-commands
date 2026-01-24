# CLAUDE.md

This file provides guidance to Claude Code when working with this NestJS backend project.

## Project Overview

A NestJS backend API with PostgreSQL database, Prisma ORM, and comprehensive testing setup.

**Tech Stack:**

- Runtime: Node.js 20 LTS
- Framework: NestJS 10
- Database: PostgreSQL 15 with Prisma ORM
- Package Manager: npm
- Testing: Jest, Supertest

## Development Commands

```bash
# Install dependencies
npm install

# Run development server
npm run start:dev

# Run tests
npm test                    # Unit tests
npm run test:e2e           # E2E tests
npm run test:cov           # Coverage report

# Database
npx prisma migrate dev     # Run migrations
npx prisma generate        # Generate client
npx prisma studio          # Open database GUI

# Linting & formatting
npm run lint               # ESLint
npm run format             # Prettier

# Build
npm run build
```

## Project Structure

```
src/
├── modules/               # Feature modules
│   ├── auth/              # Authentication
│   ├── users/             # User management
│   └── {feature}/         # Other features
├── common/                # Shared code
│   ├── decorators/        # Custom decorators
│   ├── filters/           # Exception filters
│   ├── guards/            # Auth guards
│   ├── interceptors/      # Request/response interceptors
│   └── pipes/             # Validation pipes
├── config/                # Configuration
├── prisma/                # Database schema & migrations
└── main.ts                # Application entry

tests/
├── unit/                  # Unit tests (*.spec.ts)
├── integration/           # Integration tests
└── e2e/                   # End-to-end tests
```

## Git Workflow

Uses Claude Code slash commands with staging-based workflow:

- `/start` → Create feature branch from Linear ticket
- `/commit` → Commit with `[Type] Message (TICKET-ID)` format
- `/finish` → Create PR to staging with full description
- `/release` → Create release from staging to main
- `/release-notes` → Generate GitHub release notes
- `/sync` → Back-merge main to staging

## Code Standards

### Module Structure

Each module should have:

```
{module}/
├── {module}.module.ts      # Module definition
├── {module}.controller.ts  # HTTP endpoints
├── {module}.service.ts     # Business logic
├── dto/                    # Data transfer objects
├── entities/               # Prisma models/types
└── {module}.spec.ts        # Unit tests
```

### Testing

- Write tests alongside implementation
- Use factories for test data
- Mock external dependencies
- Minimum 80% coverage for new code

### API Design

- Use DTOs with class-validator decorators
- Document endpoints with Swagger decorators
- Return consistent response shapes
- Handle errors with exception filters

## Environment Variables

```bash
# Required
DATABASE_URL=postgresql://user:pass@localhost:5432/db
JWT_SECRET=your-secret-key
API_KEY=external-api-key

# Optional
PORT=3000
LOG_LEVEL=debug
REDIS_URL=redis://localhost:6379
```

## Database Migrations

```bash
# Create migration after schema change
npx prisma migrate dev --name {migration_name}

# Apply migrations in production
npx prisma migrate deploy

# Reset database (development only)
npx prisma migrate reset
```

## API Documentation

- Swagger UI: http://localhost:3000/api/docs
- OpenAPI spec: docs/openapi.json
- Generated on build with `npm run build:docs`
