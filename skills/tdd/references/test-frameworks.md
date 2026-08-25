# Test Framework Detection

**Node.js:**

```bash
# Check package.json for test framework
cat package.json | grep -E "(jest|vitest|mocha|ava)" || echo "UNKNOWN"

# Check for config files
ls jest.config.* vitest.config.* 2>/dev/null
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| `jest` in package.json | Jest | `npm test` or `pnpm test` |
| `vitest` in package.json | Vitest | `npm test` or `pnpm vitest` |
| `vitest.config.*` exists | Vitest | `pnpm vitest` |
| `mocha` in package.json | Mocha | `npm test` |

**Python:**

```bash
# Check for pytest
cat pyproject.toml 2>/dev/null | grep pytest || ls .pytest_cache 2>/dev/null
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| pytest in pyproject.toml | pytest | `pytest` |
| .pytest_cache exists | pytest | `pytest` |
| unittest pattern | unittest | `python -m unittest` |

**Rust:**

```bash
# Check for Cargo.toml
[ -f "Cargo.toml" ] && echo "RUST"
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| Cargo.toml exists | cargo test | `cargo test` |

**Go:**

```bash
# Check for go.mod
[ -f "go.mod" ] && echo "GO"
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| go.mod exists | go test | `go test ./...` |

**Store Detection Results:**

```json
{
  "testFramework": "jest|vitest|pytest|cargo|go",
  "testCommand": "npm test|pnpm vitest|pytest|cargo test|go test ./...",
  "testFilePattern": "*.test.ts|*.spec.ts|*_test.py|*_test.go",
  "relatedFiles": ["src/services/auth.ts", "tests/auth.test.ts"]
}
```

# Test Run Commands by Language

```bash
# JS/TS + Python:
{TEST_COMMAND} {TEST_FILE}

# Go:
go test ./...              # or: go test ./path -run TestName

# Rust:
cargo test <pattern>       # or: cargo test --package <pkg>

# Examples:
# npm test -- tests/auth.test.ts
# pnpm vitest run tests/auth.test.ts
# pytest tests/test_auth.py
# go test ./services -run TestAuth
# cargo test auth_service
```
