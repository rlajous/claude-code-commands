#!/usr/bin/env bash

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail=0
warn=0
err() { printf 'FAIL: %s\n' "$1"; fail=$((fail + 1)); }
warns() { printf 'WARN: %s\n' "$1"; warn=$((warn + 1)); }
ok() { printf 'ok:   %s\n' "$1"; }

for file in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json hooks/claude-hooks.json hooks/hooks.json; do
  if [ ! -f "$file" ]; then
    err "$file missing"
  elif python3 -m json.tool "$file" >/dev/null 2>&1; then
    ok "$file valid JSON"
  else
    err "$file is not valid JSON"
  fi
done

if python3 - <<'PY'
import json
from pathlib import Path

claude = json.loads(Path(".claude-plugin/plugin.json").read_text())
market = json.loads(Path(".claude-plugin/marketplace.json").read_text())
codex = json.loads(Path(".codex-plugin/plugin.json").read_text())
versions = {claude["version"], codex["version"]}
versions.update(plugin["version"] for plugin in market["plugins"])
assert versions == {"2.4.0"}, versions
assert claude["name"] == codex["name"] == "git-workflow"
assert codex["skills"] == "./skills/"
assert claude["hooks"] == "./hooks/claude-hooks.json"
assert "hooks" not in codex, "Codex hooks are discovered from hooks/hooks.json"

codex_hooks = json.loads(Path("hooks/hooks.json").read_text())["hooks"]["PostToolUse"]
assert any(entry.get("matcher") == "Bash" and any(hook.get("async") is True for hook in entry.get("hooks", [])) for entry in codex_hooks)
PY
then ok "manifest versions, paths, and Codex hook registration aligned"
else err "manifest versions, paths, or hook registration are inconsistent"
fi

if python3 scripts/validate-codex-plugin.py >/dev/null; then
  ok "Codex plugin ingestion contract"
else
  err "Codex plugin ingestion contract"
fi

if node scripts/generate-codex-agents.mjs --check >/dev/null; then
  ok "generated Codex agents are current"
else
  err "generated Codex agents drifted from agents/*.md"
fi

if python3 - <<'PY'
import re
import tomllib
from pathlib import Path

sources = {}
for path in sorted(Path("agents").glob("*.md")):
    text = path.read_text()
    match = re.match(r"^---\n(.*?)\n---\n+(.*)$", text, re.S)
    assert match, f"invalid frontmatter: {path}"
    fields = dict(re.findall(r"^([a-z-]+):\s*(.*)$", match.group(1), re.M))
    assert fields.get("name") and fields.get("description"), path
    sources[fields["name"]] = match.group(2).rstrip()

generated = {}
for path in sorted(Path(".codex/agents").glob("*.toml")):
    with path.open("rb") as file:
        data = tomllib.load(file)
    assert set(data) == {"name", "description", "sandbox_mode", "developer_instructions"}, path
    assert data["sandbox_mode"] in {"read-only", "workspace-write"}, path
    assert "model" not in data and "model_reasoning_effort" not in data, path
    generated[data["name"]] = data

assert len(sources) == len(generated) == 8
assert set(sources) == set(generated)
for name, instructions in sources.items():
    assert generated[name]["developer_instructions"] == instructions
    expected = "workspace-write" if name in {"release-validator", "qa-executor"} else "read-only"
    assert generated[name]["sandbox_mode"] == expected
PY
then ok "eight canonical agents have one-to-one valid TOML definitions"
else err "canonical and Codex agent definitions failed parity validation"
fi

if python3 - <<'PY'
import re
from pathlib import Path

skills = sorted(Path("skills").glob("*/SKILL.md"))
assert len(skills) == 17, len(skills)
for path in skills:
    text = path.read_text()
    match = re.match(r"^---\n(.*?)\n---\n+(.*)$", text, re.S)
    assert match, f"invalid frontmatter: {path}"
    fields = dict(re.findall(r"^([a-z-]+):\s*(.*)$", match.group(1), re.M))
    assert fields.get("name") == path.parent.name, path
    assert fields.get("description"), path
    body = match.group(2)
    for host_tool in ("AskUserQuestion", "WebFetch", "Task tool", "Task agent"):
        assert host_tool not in body, f"{path}: host-only wording {host_tool!r}"
    assert "runtime compatibility" in body.lower(), f"{path}: missing compatibility guidance"
    lines = len(text.splitlines())
    if lines > 500:
        print(f"WARN {path} has {lines} lines")
PY
then ok "17 shared skills have valid neutral instructions"
else err "skill count, frontmatter, or runtime-neutral wording failed validation"
fi

if python3 - <<'PY'
from pathlib import Path

def read(path):
    return Path(path).read_text()

qa = read("agents/qa-executor.md")
assert "Redact `Authorization`" in qa
assert "full bodies only after explicit user approval" in qa

reviewer = read("agents/pr-reviewer.md")
assert "BASE_SHA...HEAD" in reviewer
assert "HEAD~1..HEAD" in reviewer
review = read("skills/review/SKILL.md")
assert "baseRefOid" in review and "baseRefOid...HEAD" in review

for path in ("skills/start/SKILL.md", "skills/rfc/SKILL.md", "skills/start-qa/SKILL.md"):
    text = read(path)
    assert "explicit confirmation" in text, path
    assert "Immediately before" in text, path

for path in ("skills/start/SKILL.md", "skills/tdd/SKILL.md", "skills/status/SKILL.md"):
    assert "mkdir -p .git-workflow" in read(path), path

for path in (
    "skills/review-request/SKILL.md",
    "skills/review/SKILL.md",
    "skills/start-qa/SKILL.md",
    "skills/start/SKILL.md",
    "skills/standup/SKILL.md",
    "skills/sync/SKILL.md",
    "skills/tdd/SKILL.md",
):
    text = read(path)
    assert ".git-workflow/config.yaml" in text, path
    assert ".claude/config.yaml" in text, path

tdd = read("skills/tdd/SKILL.md")
assert ".git-workflow/pr-context.json" in tdd
assert ".claude/.pr-context.json" in tdd

workflow = read(".github/workflows/validate.yml")
assert "permissions:\n  contents: read" in workflow
assert "```text\n/start PROJ-123" in read("COMMANDS.md")

template = read("templates/config.yaml.template")
assert '"mcpServers"' in template
assert "[mcp_servers.linear]" in template
assert "[mcp_servers.jira]" in template
PY
then ok "review-remediation safety and compatibility assertions"
else err "review-remediation safety or compatibility assertions failed"
fi

for script in hooks/review-commit.sh scripts/test-review-hook.sh scripts/test-runtime-state.sh scripts/test-sync-project.sh; do
  if bash -n "$script"; then ok "$script syntax"; else err "$script syntax"; fi
done

if bash scripts/test-review-hook.sh >/dev/null; then ok "review hook behavior"; else err "review hook behavior"; fi
if bash scripts/test-runtime-state.sh >/dev/null; then ok "runtime state precedence"; else err "runtime state precedence"; fi
if bash scripts/test-sync-project.sh >/dev/null; then ok "setup/update synchronization behavior"; else err "setup/update synchronization behavior"; fi

if node scripts/status-report.mjs | grep -q '<!doctype html>'; then
  ok "status report smoke test"
else
  err "status report smoke test"
fi

printf '\n'
if [ "$fail" -gt 0 ]; then
  printf 'RESULT: %d failure(s), %d warning(s)\n' "$fail" "$warn"
  exit 1
fi
printf 'RESULT: all checks passed (%d warning(s))\n' "$warn"
