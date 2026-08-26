#!/usr/bin/env bash
# Compatibility wrapper. The canonical daemon lives with the review-watch skill.

set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec bash "$PACKAGE_ROOT/skills/review-watch/scripts/review-watch.sh" "$@"
