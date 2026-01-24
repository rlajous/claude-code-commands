# CLAUDE.md

This file provides guidance to Claude Code when working with this Python FastAPI project.

## Project Overview

A FastAPI backend with SQLAlchemy, Alembic migrations, and comprehensive async support.

**Tech Stack:**

- Runtime: Python 3.12
- Framework: FastAPI
- Database: PostgreSQL with SQLAlchemy 2.0
- Migrations: Alembic
- Package Manager: uv
- Testing: pytest, pytest-asyncio

## Development Commands

```bash
# Install dependencies
uv sync

# Run development server
uv run uvicorn app.main:app --reload

# Run tests
uv run pytest                      # All tests
uv run pytest tests/unit           # Unit tests only
uv run pytest -v --cov=app         # With coverage

# Database
uv run alembic upgrade head        # Run migrations
uv run alembic revision -m "msg"   # Create migration

# Code quality
uv run ruff check .                # Linting
uv run ruff format .               # Formatting
uv run mypy .                      # Type checking

# Build
uv build
```

## Project Structure

```
app/
├── api/                   # API routes
│   ├── v1/                # API version 1
│   │   ├── endpoints/     # Route handlers
│   │   └── router.py      # Route aggregation
│   └── deps.py            # Dependencies (auth, db)
├── core/                  # Core configuration
│   ├── config.py          # Settings
│   ├── security.py        # Auth utilities
│   └── database.py        # DB connection
├── models/                # SQLAlchemy models
├── schemas/               # Pydantic schemas
├── services/              # Business logic
├── repositories/          # Data access layer
└── main.py                # Application entry

tests/
├── conftest.py            # Fixtures
├── unit/                  # Unit tests
├── integration/           # Integration tests
└── e2e/                   # End-to-end tests

alembic/
├── versions/              # Migration files
└── env.py                 # Migration config
```

## Git Workflow

Uses Claude Code commands with Jira integration:

- `/start` → Create branch from Jira ticket
- `/commit` → Commit with `[Type] Message (JIRA-ID)`
- `/finish` → Create PR to staging
- `/release` → Create release to main

## Code Standards

### API Endpoints

```python
from fastapi import APIRouter, Depends
from app.api.deps import get_current_user
from app.schemas.user import UserResponse

router = APIRouter()

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: int,
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    """Get user by ID."""
    ...
```

### Dependency Injection

- Use FastAPI Depends for dependencies
- Create reusable dependencies in `deps.py`
- Use repository pattern for data access

### Async

- Use `async/await` for all I/O operations
- Use `asyncpg` for database connections
- Use `httpx` for HTTP client

## Environment Variables

```bash
# Required
DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/db
SECRET_KEY=your-secret-key
ENVIRONMENT=development

# Optional
DEBUG=true
LOG_LEVEL=DEBUG
REDIS_URL=redis://localhost:6379
```

## Database Migrations

```bash
# Create migration after model changes
uv run alembic revision --autogenerate -m "Add users table"

# Apply migrations
uv run alembic upgrade head

# Rollback last migration
uv run alembic downgrade -1
```

## Testing Guidelines

- Use pytest fixtures for setup
- Use `pytest-asyncio` for async tests
- Mock external services
- Use factory_boy for test data

```python
@pytest.mark.asyncio
async def test_create_user(client: AsyncClient, db: AsyncSession):
    response = await client.post("/api/v1/users", json={...})
    assert response.status_code == 201
```

## API Documentation

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc
- OpenAPI JSON: http://localhost:8000/openapi.json
