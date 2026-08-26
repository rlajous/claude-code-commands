#!/usr/bin/env bash
# Compatibility wrapper. The notifications skill owns the generic notifier.

set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
exec bash "$SKILL_DIR/notifications/scripts/notify.sh" "$@"
