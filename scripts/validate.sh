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
versions.add(market["metadata"]["version"])
versions.update(plugin["version"] for plugin in market["plugins"])
assert versions == {"2.5.2"}, versions
assert claude["name"] == codex["name"] == "git-workflow"
assert len(market["plugins"]) == 1
assert market["plugins"][0]["name"] == "git-workflow"
assert codex["skills"] == "./skills/"
assert claude["hooks"] == "./hooks/claude-hooks.json"
assert "hooks" not in codex, "Codex hooks are discovered from hooks/hooks.json"

codex_hooks = json.loads(Path("hooks/hooks.json").read_text())["hooks"]["PostToolUse"]
assert any(entry.get("matcher") == "Bash" and all("async" not in hook and "--host codex" in hook["command"] for hook in entry.get("hooks", [])) for entry in codex_hooks)
claude_hooks = json.loads(Path("hooks/claude-hooks.json").read_text())["hooks"]["PostToolUse"]
assert all(hook.get("asyncRewake") is True and "--host claude" in hook["command"] for entry in claude_hooks for hook in entry["hooks"])
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
assert len(skills) == 19, len(skills)
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
then ok "19 shared skills have valid neutral instructions"
else err "skill count, frontmatter, or runtime-neutral wording failed validation"
fi

if python3 - <<'PY'
from pathlib import Path

root = Path.cwd()
link = root / ".agents" / "skills"
assert link.is_symlink() and link.readlink() == Path("../skills")
assert len(list(link.resolve().glob("*/SKILL.md"))) == 19

resources = (
    "skills/review-watch/scripts/review-watch.sh",
    "skills/review-watch/scripts/notify.sh",
    "skills/review-watch/scripts/review-watch-tools.sh",
    "skills/review-watch/references/known-issues.md",
    "skills/review/scripts/review-event.sh",
    "skills/review/scripts/to-sarif.mjs",
    "skills/change-brief/scripts/validate-self-contained-html.py",
    "skills/status/scripts/status-report.mjs",
    "skills/status/assets/status-template.html",
    "skills/setup/scripts/sync-project.mjs",
)
for relative in resources:
    assert (root / relative).is_file(), relative

affected = (
    "skills/setup/SKILL.md",
    "skills/update/SKILL.md",
    "skills/status/SKILL.md",
    "skills/review/SKILL.md",
    "skills/review-watch/SKILL.md",
    "skills/change-brief/SKILL.md",
)
for relative in affected:
    text = (root / relative).read_text()
    assert "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/scripts" not in text, relative
    assert "{SKILL_DIR}" in text, relative
PY
then ok "skill-local resources and Codex checkout discovery contract"
else err "skill-local resource or Codex checkout discovery contract failed"
fi

if python3 - <<'PY'
from pathlib import Path

def read(path):
    return Path(path).read_text()

qa = read("agents/qa-executor.md")
assert "Redact `Authorization`" in qa
assert "full bodies only after explicit user approval" in qa

reviewer = read("agents/pr-reviewer.md")
assert "BASE_SHA...HEAD_SHA" in reviewer
assert "HEAD~1..HEAD" in reviewer
review = read("skills/review/SKILL.md")
assert "baseRefOid" in review and "BASE_SHA...HEAD_SHA" in review
assert "locally checked-out `HEAD`" in review
assert "{SKILL_DIR}/scripts/review-event.sh" in review
assert "{SKILL_DIR}/scripts/to-sarif.mjs" in review

review_watch = read("skills/review-watch/SKILL.md")
assert "reviewWatch.enabled=false" in review_watch
assert "{SKILL_DIR}/../review/scripts/review-event.sh" in review_watch
assert "--doctor" in review_watch and "--daemon-command" in review_watch
assert '"{owner}/{repo} · PR #{PR}"' in review_watch
assert '"{AUTHOR_LABEL} — Ready for merge: {title}"' in review_watch

watcher_script = read("skills/review-watch/scripts/review-watch.sh")
assert "gh api graphql" in watcher_script
assert "author { login }" in watcher_script
assert "REVIEW_WATCH_NOTIFY_SCRIPT" in watcher_script

change_brief = read("skills/change-brief/SKILL.md")
assert "validate-self-contained-html.py" in change_brief

setup = read("skills/setup/SKILL.md")
assert "--host <claude|codex|both>" in setup and "--dry-run" in setup and "--force" in setup
update = read("skills/update/SKILL.md")
assert "--source <path-or-git-url>" in update and "clone it shallowly" in update
finish = read("skills/finish/SKILL.md")
assert "read-only fallback" in finish and "must never be deleted or modified" in finish
status = read("skills/status/scripts/status-report.mjs")
assert "warnings" in status and "Ignored stale" in status
release_validator = read("agents/release-validator.md")
assert "obtain explicit user confirmation immediately before running `git fetch origin`" in release_validator
changelog = read("CHANGELOG.md")
assert "## 2.5.2" in changelog and "2.5.1" in changelog

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
assert "changeBrief:\n" in template

known_issues = read("skills/review-watch/references/known-issues.md")
assert "| `TODO|FIXME` |" not in known_issues
assert "| `TODO` |" in known_issues and "| `FIXME` |" in known_issues

change_brief = read("skills/change-brief/SKILL.md")
for requirement in (
    "less than\n10 minutes",
    "**Business logic**",
    "accessible inline SVG",
    "real before/after screenshots",
    "copyable cURL request",
    "`Observed` only when it was executed",
    "**Risk and delivery**",
    "references/evidence-playbook.md",
):
    assert requirement in change_brief, requirement

evidence_playbook = read("skills/change-brief/references/evidence-playbook.md")
for requirement in (
    "Never mutate production",
    "decision table",
    "temporary worktrees",
    "Expected — not executed",
    "6–8 minutes",
):
    assert requirement in evidence_playbook, requirement
PY
then ok "review-remediation safety and compatibility assertions"
else err "review-remediation safety or compatibility assertions failed"
fi

for script in hooks/review-commit.sh scripts/review-watch.sh scripts/review-event.sh scripts/notify.sh scripts/test-review-watch.sh scripts/test-review-event.sh scripts/test-self-contained-html.sh scripts/test-review-hook.sh scripts/test-runtime-state.sh scripts/test-sync-project.sh scripts/test-skill-resource-paths.sh scripts/test-generate-codex-agents.sh skills/review-watch/scripts/review-watch.sh skills/review-watch/scripts/notify.sh skills/review-watch/scripts/review-watch-tools.sh skills/review/scripts/review-event.sh; do
  if bash -n "$script"; then ok "$script syntax"; else err "$script syntax"; fi
done

if bash scripts/test-review-hook.sh >/dev/null; then ok "review hook behavior"; else err "review hook behavior"; fi
if bash scripts/test-review-watch.sh >/dev/null; then ok "review watcher configuration and queue behavior"; else err "review watcher configuration and queue behavior"; fi
if bash scripts/test-review-event.sh >/dev/null; then ok "review event configuration modes"; else err "review event configuration modes"; fi
if bash scripts/test-self-contained-html.sh >/dev/null; then ok "self-contained HTML network guard"; else err "self-contained HTML network guard"; fi
if bash scripts/test-runtime-state.sh >/dev/null; then ok "runtime state precedence"; else err "runtime state precedence"; fi
if bash scripts/test-sync-project.sh >/dev/null; then ok "setup/update synchronization behavior"; else err "setup/update synchronization behavior"; fi
if bash scripts/test-skill-resource-paths.sh >/dev/null; then ok "skill-local resources and compatibility wrappers"; else err "skill-local resource paths or wrappers"; fi
if bash scripts/test-generate-codex-agents.sh >/dev/null; then ok "Codex agent generator safety"; else err "Codex agent generator safety"; fi
if python3 scripts/test-codex-plugin-validator.py >/dev/null; then ok "Codex manifest negative fixtures"; else err "Codex manifest negative fixtures"; fi

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
