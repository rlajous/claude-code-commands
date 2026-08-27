#!/usr/bin/env bash
# Compatibility wrapper. The notifications skill owns the shared daemon.

set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec bash "$PACKAGE_ROOT/skills/notifications/scripts/activity-watch.sh" "$@"
