# Test Framework Detection

Detect the project's test framework and run command so the plan uses real conventions.

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
[ -f "Cargo.toml" ] && echo "RUST"
```

| Detection | Framework | Test Command |
| --------- | --------- | ------------ |
| Cargo.toml exists | cargo test | `cargo test` |

**Go:**

```bash
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

If no framework is detected, record `testFramework: "unknown"` and still emit behavior cycles and assertions — the run command can be filled in during `/tdd`.

# Skeleton Stub Conventions by Framework

Use these to scaffold one RED (failing/pending) stub per behavior cycle in Step 11. Each stub names the behavior, references its `BC-00N` id in a comment, and contains no implementation.

```text
# Jest / Vitest (*.test.ts, *.spec.ts)
describe('BC-001 <behavior>', () => {
  it.todo('<then>');            // or: it('<then>', () => { expect(false).toBe(true); });
});

# pytest (*_test.py, test_*.py)
import pytest
@pytest.mark.skip(reason="BC-001 <behavior> — not implemented")
def test_<then>():
    assert False

# Go (*_test.go)
func TestBC001<Behavior>(t *testing.T) {
    t.Skip("BC-001 <behavior> — not implemented")  // or: t.Fatal("not implemented")
}

# Rust (in a #[cfg(test)] mod)
#[test]
#[ignore = "BC-001 <behavior> — not implemented"]
fn bc_001_<then>() { unimplemented!() }
```
