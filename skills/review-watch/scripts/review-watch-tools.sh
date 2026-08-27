#!/usr/bin/env bash
# Compatibility wrapper. The notifications skill owns daemon diagnostics.

set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
exec bash "$SKILL_DIR/notifications/scripts/notification-tools.sh" "$@"
