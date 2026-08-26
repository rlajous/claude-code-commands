#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-self-contained-html.py"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

write_page() {
  local body="$1"
  printf '%s\n' '<!doctype html><html><head>' \
    '<meta http-equiv="Content-Security-Policy" content="default-src '\''none'\''; style-src '\''unsafe-inline'\''; script-src '\''unsafe-inline'\''">' \
    '</head><body>' "$body" '</body></html>' > "$TEST_ROOT/index.html"
}

write_page '<pre>PR text may say fetch(https://example.com) or &lt;link href="//example.com"&gt;</pre>'
python3 "$VALIDATOR" "$TEST_ROOT/index.html" || fail "escaped PR text caused a false positive"

write_page '<img src="data:image/png;base64,iVBORw0KGgo=" alt="Embedded before screenshot">'
python3 "$VALIDATOR" "$TEST_ROOT/index.html" || fail "embedded screenshot data URI was rejected"

for unsafe in \
  '<link rel="stylesheet" href="https://example.com/a.css">' \
  '<style>.x{background:url(//example.com/a.png)}</style>' \
  '<style>.x{background:url(/local-still-fetches.png)}</style>' \
  '<script>fetch("/api")</script>' \
  '<button onclick="fetch('\''/api'\'')">go</button>' \
  '<img src="https://example.com/pixel" src="data:,ok">' \
  '<img src="https://example.com/a.png">'; do
  write_page "$unsafe"
  if python3 "$VALIDATOR" "$TEST_ROOT/index.html" >/dev/null 2>&1; then
    fail "unsafe network-capable HTML was accepted: $unsafe"
  fi
done

printf '%s\n' '<!doctype html><html><head>' \
  '<meta http-equiv="Content-Security-Policy" content="default-src '\''none'\''; connect-src *">' \
  '</head><body>unsafe policy</body></html>' > "$TEST_ROOT/index.html"
if python3 "$VALIDATOR" "$TEST_ROOT/index.html" >/dev/null 2>&1; then
  fail "CSP with a broad connect-src override was accepted"
fi

printf '%s\n' '<!doctype html><html><head></head><body>' \
  '<meta http-equiv="Content-Security-Policy" content="default-src '\''none'\''">' \
  'policy is too late</body></html>' > "$TEST_ROOT/index.html"
if python3 "$VALIDATOR" "$TEST_ROOT/index.html" >/dev/null 2>&1; then
  fail "CSP meta outside head was accepted"
fi

printf '%s\n' '<!doctype html><p>no policy</p>' > "$TEST_ROOT/index.html"
if python3 "$VALIDATOR" "$TEST_ROOT/index.html" >/dev/null 2>&1; then
  fail "page without a restrictive CSP was accepted"
fi

printf 'ok: self-contained HTML validation scenarios\n'
