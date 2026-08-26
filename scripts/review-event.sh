#!/usr/bin/env bash
# Compatibility wrapper. The canonical resolver lives with the review skill.

set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec bash "$PACKAGE_ROOT/skills/review/scripts/review-event.sh" "$@"
