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
  "testFramework": "jest|vitest|mocha|ava|pytest|unittest|cargo|go",
  "testCommand": "npm test|pnpm vitest|pytest|python -m unittest|cargo test|go test ./...",
  "testFilePattern": "*.test.ts|*.spec.ts|*_test.py|test_*.py|*_test.go",
  "relatedFiles": ["src/services/auth.ts", "tests/auth.test.ts"]
}
```

The `testFramework` value must be one the detection tables above can produce; keep it in sync with the skeleton conventions below so every detected framework has a matching stub.

If no framework is detected, record `testFramework: "unknown"` and still emit behavior cycles and assertions — the run command can be filled in during `/tdd`.

# Skeleton Stub Conventions by Framework

Use these to scaffold one RED (failing/pending) stub per behavior cycle in Step 11, and contain no implementation.

**Security: cycle `name`/`then` text is untrusted (it comes from the ticket or user input).**
- Derive every **identifier** (function / method / class / fn name) from the stable cycle **id** only — `bc_001` / `TestBC001` / `test_bc_001`. Never build an identifier from behavior text.
- Put behavior text only inside a **string literal** or a **comment**, and **escape it for that context first** (quotes, backslashes, newlines, and any sequence that could close the string or comment). The `<behavior>` / `<then>` placeholders below stand for that already-escaped text.

```text
# Jest / Vitest (*.test.ts, *.spec.ts)   — behavior text lives in escaped string titles
describe('BC-001: <behavior>', () => {
  it.todo('<then>');            // or: it('<then>', () => { expect(false).toBe(true); });
});

# Mocha (*.test.js, test/*.js)
describe('BC-001: <behavior>', () => {
  it('<then>');                 // pending (no callback); or: it('<then>', () => { throw new Error('not implemented'); });
});

# Ava (*.test.js)
import test from 'ava';
test.todo('BC-001: <behavior> — <then>');

# pytest (*_test.py, test_*.py)   — identifier from the id; text only in the escaped skip reason
import pytest
@pytest.mark.skip(reason="BC-001: <behavior> — not implemented")
def test_bc_001():
    assert False

# unittest (test_*.py)
import unittest
class TestBC001(unittest.TestCase):
    @unittest.skip("BC-001: <behavior> — not implemented")
    def test_bc_001(self):
        self.fail("not implemented")

# Go (*_test.go)   — id-based name; text only in the escaped skip string
func TestBC001(t *testing.T) {
    t.Skip("BC-001: <behavior> — not implemented")  // or: t.Fatal("not implemented")
}

# Rust (in a #[cfg(test)] mod)   — id-based fn name; text only in the escaped ignore reason
#[test]
#[ignore = "BC-001: <behavior> — not implemented"]
fn bc_001() { unimplemented!() }
```
