# Example Complete Flow

```bash
# User runs: /release
# Checks: on staging, up-to-date ✓
# Detects: package.json with version 2.76.0
# Asks: What type? → User selects "minor"
# Shows: 2.76.0 → 2.77.0
# Extracts: 15 commits (8 fixes, 4 features, 3 improvements)
# Detects: 2 new migrations, OpenAPI changes
# Contributors: @alice @bob @charlie
# Creates: release/2.77.0 branch
# Merges: origin/main into release branch
# Runs: npm version minor
# Pushes: release/2.77.0 with tags
# Creates: PR #679 to main
# Output: Success message with next steps and migration alert
```
