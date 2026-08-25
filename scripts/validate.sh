#!/usr/bin/env bash
# git-workflow — plugin self-validation.
#
# Checks that the plugin is internally consistent. Run locally or in CI:
#   bash scripts/validate.sh
#
# Validates:
#   - .claude-plugin/plugin.json and marketplace.json are valid JSON
#   - the plugin version matches across plugin.json + marketplace.json (both places)
#   - every skills/<name>/SKILL.md has a name + description in its frontmatter
#   - every agents/*.md has name + description
#   - hooks/hooks.json (if present) is valid JSON
#   - no SKILL.md exceeds the soft 500-line progressive-disclosure guideline (warning)
#
# Exit code 0 = all hard checks pass, non-zero = at least one failure.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail=0
warn=0
err()  { printf 'FAIL: %s\n' "$1"; fail=$((fail+1)); }
warns(){ printf 'WARN: %s\n' "$1"; warn=$((warn+1)); }
ok()   { printf 'ok:   %s\n' "$1"; }

json_ok() { python3 -m json.tool "$1" >/dev/null 2>&1; }

# --- JSON manifests ----------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  if [ ! -f "$f" ]; then err "$f missing"; continue; fi
  if json_ok "$f"; then ok "$f valid JSON"; else err "$f is not valid JSON"; fi
done

if [ -f hooks/hooks.json ]; then
  if json_ok hooks/hooks.json; then ok "hooks/hooks.json valid JSON"; else err "hooks/hooks.json is not valid JSON"; fi
fi

# --- version alignment -------------------------------------------------------
# Collect every "version": "..." from the two manifests; they must all match.
versions="$(grep -hoE '"version":[[:space:]]*"[^"]+"' .claude-plugin/plugin.json .claude-plugin/marketplace.json 2>/dev/null \
  | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/' | sort -u)"
vcount="$(printf '%s\n' "$versions" | grep -c .)"
if [ "$vcount" -eq 1 ] && [ -n "$versions" ]; then
  ok "version aligned: $versions"
else
  err "version mismatch across manifests: $(printf '%s ' $versions)"
fi

# --- frontmatter helper ------------------------------------------------------
# Prints "ok" if the file has a YAML frontmatter block containing `field:`.
has_frontmatter_field() {
  awk -v field="$2" '
    NR==1 && $0!="---" { print "no-open"; exit }
    NR>1 && $0=="---"  { exit }
    NR>1 && $0 ~ "^" field ":" { found=1 }
    END { if (found) print "yes"; else print "no" }
  ' "$1"
}

# --- skills ------------------------------------------------------------------
skill_count=0
if [ -d skills ]; then
  for d in skills/*/; do
    sk="$d/SKILL.md"
    name="$(basename "$d")"
    [ -f "$sk" ] || { err "skills/$name has no SKILL.md"; continue; }
    skill_count=$((skill_count+1))
    [ "$(has_frontmatter_field "$sk" name)" = "yes" ] || err "skills/$name: missing 'name' in frontmatter"
    [ "$(has_frontmatter_field "$sk" description)" = "yes" ] || err "skills/$name: missing 'description' in frontmatter"
    lines="$(wc -l < "$sk" | tr -d ' ')"
    [ "$lines" -gt 500 ] && warns "skills/$name/SKILL.md is $lines lines (>500 soft guideline — consider references/)"
  done
  ok "skills checked: $skill_count"
fi

# --- agents ------------------------------------------------------------------
agent_count=0
if [ -d agents ]; then
  for a in agents/*.md; do
    [ -f "$a" ] || continue
    agent_count=$((agent_count+1))
    [ "$(has_frontmatter_field "$a" name)" = "yes" ] || err "$a: missing 'name' in frontmatter"
    [ "$(has_frontmatter_field "$a" description)" = "yes" ] || err "$a: missing 'description' in frontmatter"
  done
  ok "agents checked: $agent_count"
fi

# --- result ------------------------------------------------------------------
echo
if [ "$fail" -gt 0 ]; then
  printf 'RESULT: %d failure(s), %d warning(s)\n' "$fail" "$warn"
  exit 1
fi
printf 'RESULT: all checks passed (%d warning(s))\n' "$warn"
exit 0
