---
description: Create a release branch and PR to main with auto-extracted changes from staging
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Edit
user-invocable: true
---

You are helping create a production release. Your task is to create a release branch from the development branch, bump the version, extract changes, and create a comprehensive release PR to the production branch.

## Step 1: Load Configuration

Check for configuration:

```bash
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
workflow:
  type: staging # staging | tag-based | direct
  developmentBranch: staging
  productionBranch: main
branches:
  release: "release/{version}"
versioning:
  file: auto # auto | package.json | pyproject.toml | VERSION | Cargo.toml
release:
  watchFiles:
    openapi: docs/openapi.json
    migrations: prisma/migrations/**/migration.sql
    schema: prisma/schema.prisma
  generateChangelog: true
```

**Default Values:**

```yaml
workflow:
  developmentBranch: staging
  productionBranch: main
branches:
  release: "release/{version}"
versioning:
  file: auto
```

## Step 2: Verify Current State

Check that you're on the development branch and up-to-date:

```bash
# Get configured branches
DEV_BRANCH=$(config.workflow.developmentBranch || "staging")
PROD_BRANCH=$(config.workflow.productionBranch || "main")

# Check current branch
CURRENT=$(git branch --show-current)
echo "Current branch: $CURRENT"
echo "Expected: $DEV_BRANCH"

# Fetch latest
git fetch origin

# Check if up-to-date
git status
```

**Validation:**

- If not on development branch:
  ```
  You must be on {DEV_BRANCH} branch to create a release.
  Run: git checkout {DEV_BRANCH} && git pull
  ```
- If behind remote:
  ```
  Your {DEV_BRANCH} branch is behind origin.
  Run: git pull origin {DEV_BRANCH}
  ```
- If there are uncommitted changes:
  ```
  You have uncommitted changes. Commit or stash them first.
  ```

## Step 3: Detect Version File

Auto-detect or use configured version file:

```bash
# Check for version files in order of priority
if [ -f "package.json" ]; then
  VERSION_FILE="package.json"
  VERSION_TYPE="node"
elif [ -f "pyproject.toml" ]; then
  VERSION_FILE="pyproject.toml"
  VERSION_TYPE="python"
elif [ -f "Cargo.toml" ]; then
  VERSION_FILE="Cargo.toml"
  VERSION_TYPE="rust"
elif [ -f "VERSION" ]; then
  VERSION_FILE="VERSION"
  VERSION_TYPE="plain"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  VERSION_FILE="build.gradle"
  VERSION_TYPE="gradle"
else
  VERSION_FILE="VERSION"
  VERSION_TYPE="plain"
fi
```

**Read Current Version:**

| Type     | Command                                                    |
| -------- | ---------------------------------------------------------- |
| Node.js  | `node -p "require('./package.json').version"`              |
| Python   | `grep -Po '(?<=version = ")[^"]*' pyproject.toml`          |
| Rust     | `grep -Po '(?<=^version = ")[^"]*' Cargo.toml`             |
| Plain    | `cat VERSION`                                              |
| Gradle   | `grep -Po '(?<=version = ")[^"]*' build.gradle`            |

## Step 4: Ask for Version Type

Ask the user which version bump to perform (use AskUserQuestion tool):

**Question**: "What type of version bump for this release?"

**Options**:

- **patch**: Bug fixes only (1.2.3 → 1.2.4)
- **minor**: New features, backward compatible (1.2.3 → 1.3.0)
- **major**: Breaking changes (1.2.3 → 2.0.0)

**Display**:

```
Current version: {CURRENT_VERSION}
Version file: {VERSION_FILE}

Select version bump:
- patch: {CURRENT} → {PATCH_VERSION}
- minor: {CURRENT} → {MINOR_VERSION}
- major: {CURRENT} → {MAJOR_VERSION}
```

## Step 5: Calculate New Version

Based on user selection:

```
Current: 1.2.3
Patch:   1.2.4
Minor:   1.3.0
Major:   2.0.0
```

**Version Calculation Logic:**

```javascript
// Parse version
const [major, minor, patch] = currentVersion.split('.').map(Number);

// Calculate new version based on type
switch (bumpType) {
  case 'patch':
    return `${major}.${minor}.${patch + 1}`;
  case 'minor':
    return `${major}.${minor + 1}.0`;
  case 'major':
    return `${major + 1}.0.0`;
}
```

Confirm with user:

```
Current version: 1.2.3
New version: 1.3.0

Proceed with release v1.3.0?
```

## Step 6: Extract Changes from Development Branch

Get commits between production and development:

```bash
PROD_BRANCH=$(config.workflow.productionBranch || "main")
DEV_BRANCH=$(config.workflow.developmentBranch || "staging")

git log origin/${PROD_BRANCH}..origin/${DEV_BRANCH} --pretty=format:"%s" --no-merges
```

**Categorize Commits:**

Parse commits and group by type:

| Category         | Match Patterns                                 |
| ---------------- | ---------------------------------------------- |
| Bug Fixes        | `[Fix]`, `[FIX]`, `fix:`, `fix(`               |
| Features         | `[Feature]`, `feat:`, `feat(`                  |
| Improvements     | `[Refactor]`, `[Perf]`, `improve`, `enhance`   |
| Documentation    | `[Docs]`, `docs:`                              |
| Other            | Everything else                                |

**Extract PR Numbers:**

```bash
# Extract PR references: #123, (#456)
echo "$COMMIT_MSG" | grep -oE '#[0-9]+' | sort -u
```

**Example Output:**

```markdown
### Bug Fixes

- Fix trending coins endpoint and date formatting (#662)
- Improve holder analysis accuracy (#655)

### Features

- Add cross-chain risk tag aggregation (#648)

### Improvements

- Preserve holder concentration precision (#647)
```

## Step 7: Detect Special Changes

### OpenAPI Changes

If `release.watchFiles.openapi` is configured:

```bash
OPENAPI_FILE=$(config.release.watchFiles.openapi || "docs/openapi.json")

if git diff --quiet origin/${PROD_BRANCH}..origin/${DEV_BRANCH} -- "${OPENAPI_FILE}"; then
  OPENAPI_CHANGED=false
else
  OPENAPI_CHANGED=true
  # Extract version from OpenAPI spec if present
  OPENAPI_VERSION=$(jq -r '.info.version // "unknown"' "${OPENAPI_FILE}" 2>/dev/null)
fi
```

### Database Migrations

If `release.watchFiles.migrations` is configured:

```bash
MIGRATION_PATTERN=$(config.release.watchFiles.migrations || "prisma/migrations/**/migration.sql")

MIGRATION_FILES=$(git diff --name-only --diff-filter=A origin/${PROD_BRANCH}..origin/${DEV_BRANCH} -- "${MIGRATION_PATTERN}")
MIGRATION_COUNT=$(echo "$MIGRATION_FILES" | grep -c . || echo 0)

if [ "$MIGRATION_COUNT" -gt 0 ]; then
  MIGRATIONS_CHANGED=true
  MIGRATION_NAMES=$(echo "$MIGRATION_FILES" | xargs -n1 dirname | xargs -n1 basename | paste -sd "," -)
fi
```

### Schema Changes

```bash
SCHEMA_FILE=$(config.release.watchFiles.schema || "prisma/schema.prisma")

if git diff --quiet origin/${PROD_BRANCH}..origin/${DEV_BRANCH} -- "${SCHEMA_FILE}"; then
  SCHEMA_CHANGED=false
else
  SCHEMA_CHANGED=true
fi
```

## Step 8: Extract Contributors

Get list of contributors:

```bash
git log origin/${PROD_BRANCH}..origin/${DEV_BRANCH} --format='%an' --no-merges | sort -u
```

Format as GitHub mentions: `@username1 @username2 @username3`

## Step 9: Create Release Branch

```bash
RELEASE_BRANCH_PATTERN=$(config.branches.release || "release/{version}")
RELEASE_BRANCH=${RELEASE_BRANCH_PATTERN/\{version\}/${NEW_VERSION}}

# Create release branch from development
git checkout -b ${RELEASE_BRANCH}
```

Example: `release/1.3.0`

## Step 10: Merge Production into Release

Ensure release branch has any hotfixes from production:

```bash
git fetch origin ${PROD_BRANCH}
git merge origin/${PROD_BRANCH} --no-edit
```

This ensures the release includes:

- All development changes
- Any hotfixes that went directly to production

## Step 11: Bump Version

Based on detected version file type:

### Node.js (package.json)

```bash
npm version ${BUMP_TYPE} --no-git-tag-version
git add package.json package-lock.json
git commit -m "${NEW_VERSION}"
git tag "v${NEW_VERSION}"
```

### Python (pyproject.toml)

```bash
# Using poetry
poetry version ${BUMP_TYPE}
git add pyproject.toml
git commit -m "${NEW_VERSION}"
git tag "v${NEW_VERSION}"

# Or using hatch
hatch version ${BUMP_TYPE}

# Or manual sed
sed -i 's/version = "[^"]*"/version = "'${NEW_VERSION}'"/' pyproject.toml
```

### Rust (Cargo.toml)

```bash
# Using cargo-edit
cargo set-version ${NEW_VERSION}
git add Cargo.toml Cargo.lock
git commit -m "${NEW_VERSION}"
git tag "v${NEW_VERSION}"
```

### Plain VERSION file

```bash
echo "${NEW_VERSION}" > VERSION
git add VERSION
git commit -m "${NEW_VERSION}"
git tag "v${NEW_VERSION}"
```

## Step 12: Push Release Branch

```bash
git push -u origin ${RELEASE_BRANCH} --follow-tags
```

## Step 13: Generate Release PR Description

Use this template:

````markdown
## Release v{VERSION}

This release includes {summary of changes} from {DEV_BRANCH}.

### Key Changes

{CATEGORIZED_CHANGES}

### Contributors

{CONTRIBUTORS_LIST}

### Testing & QA

All changes have been tested on {DEV_BRANCH} environment and are ready for production deployment.

---

**Release Checklist:**

- [x] Version bumped to {VERSION}
- [x] All tests passing on {DEV_BRANCH}
- [ ] Code review completed
- [ ] CI checks passing
- [ ] Ready for production deployment
````

**If Migrations Detected:**

```markdown
## Database Migration Alert

This release includes {MIGRATION_COUNT} database migration(s):
{MIGRATION_NAMES}

**Pre-Deployment:**

- [ ] Verify migrations ran successfully in {DEV_BRANCH}
- [ ] Review migration SQL for issues
- [ ] Coordinate deployment timing with team
- [ ] Prepare rollback plan

**Post-Deployment:**

- [ ] Monitor deployment logs
- [ ] Verify database schema
- [ ] Run smoke tests
```

**If OpenAPI Changed:**

```markdown
## API Documentation Update

The OpenAPI specification was modified in this release.
Current spec version: {OPENAPI_VERSION}

After merge, create documentation tag:

```bash
git tag docs-v{OPENAPI_VERSION}
git push origin docs-v{OPENAPI_VERSION}
```
```

## Step 14: Create PR to Production

```bash
PROD_BRANCH=$(config.workflow.productionBranch || "main")

gh pr create \
  --base ${PROD_BRANCH} \
  --title "[RELEASE] v${NEW_VERSION}" \
  --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)"
```

**Important:** Release PRs always target production branch (main).

## Step 15: Confirm and Next Steps

```
Release branch created: {RELEASE_BRANCH}
Version bumped: {OLD_VERSION} → {NEW_VERSION}
PR created: {PR_URL}
Title: [RELEASE] v{NEW_VERSION}

Next steps:
1. Review the PR for accuracy
2. Get team approval
3. Merge PR to {PROD_BRANCH} (use "Squash and merge")
4. Run /release-notes to create GitHub release
5. Run /sync to back-merge {PROD_BRANCH} to {DEV_BRANCH}
```

## Configuration Reference

| Setting                       | Default              | Description                    |
| ----------------------------- | -------------------- | ------------------------------ |
| `workflow.developmentBranch`  | `staging`            | Development/integration branch |
| `workflow.productionBranch`   | `main`               | Production branch              |
| `branches.release`            | `release/{version}`  | Release branch pattern         |
| `versioning.file`             | `auto`               | Version file location          |
| `release.watchFiles.openapi`  | -                    | OpenAPI spec path              |
| `release.watchFiles.migrations` | -                  | Migration files pattern        |
| `release.watchFiles.schema`   | -                    | Schema file path               |
| `release.generateChangelog`   | `true`               | Generate changelog             |

## Error Handling

| Scenario                    | Action                                         |
| --------------------------- | ---------------------------------------------- |
| Not on development branch   | Instruct to checkout and pull                  |
| Behind remote               | Instruct to pull latest                        |
| Release branch exists       | Ask to delete and recreate                     |
| No commits to release       | Warn nothing to release                        |
| Version bump fails          | Show error, manual instructions                |
| Merge conflicts             | Show conflict resolution instructions          |
| `gh` not authenticated      | Provide auth instructions                      |

## Version File Examples

### package.json

```json
{
  "name": "my-app",
  "version": "1.2.3"
}
```

### pyproject.toml

```toml
[project]
name = "my-app"
version = "1.2.3"
```

### Cargo.toml

```toml
[package]
name = "my-app"
version = "1.2.3"
```

### VERSION

```
1.2.3
```

## Example Complete Flow

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
