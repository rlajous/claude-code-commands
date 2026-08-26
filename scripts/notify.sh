#!/usr/bin/env bash
# Compatibility wrapper. The notifications skill owns the generic notifier.

set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec bash "$PACKAGE_ROOT/skills/notifications/scripts/notify.sh" "$@"
