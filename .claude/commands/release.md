---
description: Create a release branch and PR to main with auto-extracted changes from staging
---

You are helping create a production release. Your task is to create a release branch from staging, bump the version, auto-extract changes, and create a comprehensive release PR to main.

## Step 1: Verify Current State

Check that you're on staging branch and it's up-to-date:

```bash
git branch --show-current
git fetch origin
git status
```

If not on staging:

```
⚠️ You must be on staging branch to create a release.
Please run: git checkout staging && git pull
```

If behind origin/staging:

```
⚠️ Your staging branch is behind origin/staging.
Please run: git pull origin staging
```

## Step 2: Ask for Version Type

Ask the user which version bump to perform (use AskUserQuestion tool):

- **Question**: "What type of version bump for this release?"
- **Options**:
  - **minor**: New features (2.76.0 → 2.77.0)
  - **patch**: Bug fixes only (2.76.0 → 2.76.1)
  - **major**: Breaking changes (2.76.0 → 3.0.0)

## Step 3: Calculate New Version

Read current version from package.json and calculate new version:

```bash
# Get current version
CURRENT_VERSION=$(node -p "require('./package.json').version")

# Calculate new version based on user's choice
# For minor: 2.76.0 → 2.77.0
# For patch: 2.76.0 → 2.76.1
# For major: 2.76.0 → 3.0.0
```

Show the user:

```
Current version: 2.76.0
New version will be: 2.77.0
```

## Step 4: Auto-Extract Changes from Staging

Run the following commands to extract commits between main and staging:

```bash
git log origin/main..origin/staging --pretty=format:"%s" --no-merges
```

Parse the commits and categorize them:

- **Bug Fixes**: Lines starting with `[Fix]`, `[FIX]`, `fix:`
- **Features**: Lines starting with `[Feature]`, `feat:`, `feature:`
- **Improvements**: Lines with "Improve", "enhance", "optimization"

Extract PR numbers using regex: `#(\d+)`

Example output structure:

```
### Bug Fixes
- Fix trending coins endpoint and date formatting (#662)
- Improve holder analysis accuracy with per-address queries (#655)
- Fix EIP-7702 delegated EOA detection (#661)

### Features
- Add cross-chain risk tag aggregation for EVM addresses (#648)

### Improvements
- Preserve holder concentration measurement precision (#647)
```

## Step 4.5: Detect OpenAPI Changes (Optional Check)

Check if the OpenAPI specification has been modified between main and staging:

```bash
# Check for OpenAPI changes
# Configure your OpenAPI file path:
OPENAPI_FILE="docs/openapi.json"  # Change to your OpenAPI spec path

# Verify file exists on both branches
if git cat-file -e origin/staging:${OPENAPI_FILE} 2>/dev/null && \
   git cat-file -e origin/main:${OPENAPI_FILE} 2>/dev/null; then

  # Check if file has changes
  if git diff --quiet origin/main..origin/staging -- "${OPENAPI_FILE}"; then
    OPENAPI_CHANGED="false"
    echo "OpenAPI spec: No changes detected"
  else
    OPENAPI_CHANGED="true"
    echo "OpenAPI spec: Changes detected"

    # Extract current version from the file
    OPENAPI_VERSION=$(node -p "try { require('./${OPENAPI_FILE}').info.version } catch(e) { 'unknown' }" 2>/dev/null || echo "unknown")
    echo "Current OpenAPI version: ${OPENAPI_VERSION}"
  fi
else
  # File doesn't exist on one or both branches - skip detection
  OPENAPI_CHANGED="false"
  echo "OpenAPI spec: File not found on both branches, skipping detection"
fi
```

**Store these variables for use in Step 12**:

- `OPENAPI_CHANGED`: "true" or "false"
- `OPENAPI_VERSION`: version string or "unknown"

**Note**: This check never fails the release process. If any command errors, we default to `OPENAPI_CHANGED="false"`.

## Step 4.6: Detect Database Migration Changes

Check if database migrations have been added between main and staging:

```bash
# Check for new migration files
MIGRATION_FILES=$(git diff --name-only --diff-filter=A origin/main..origin/staging -- 'prisma/migrations/**/migration.sql')
MIGRATION_COUNT=$(echo "$MIGRATION_FILES" | grep -c "migration.sql" || echo "0")

if [ "$MIGRATION_COUNT" -gt 0 ]; then
  MIGRATIONS_CHANGED="true"

  # Extract migration folder names
  MIGRATION_NAMES=$(echo "$MIGRATION_FILES" | xargs dirname | xargs -n1 basename | paste -sd "," -)

  echo "Database migrations: Changes detected"
  echo "Migration count: $MIGRATION_COUNT"
  echo "Migration folders: $MIGRATION_NAMES"
else
  MIGRATIONS_CHANGED="false"
  echo "Database migrations: No changes detected"
fi

# Check if schema changed
if git diff --quiet origin/main..origin/staging -- prisma/schema.prisma; then
  SCHEMA_CHANGED="false"
else
  SCHEMA_CHANGED="true"
  echo "Prisma schema: Changes detected"
fi
```

**Store these variables for use in Step 12**:

- `MIGRATIONS_CHANGED`: "true" or "false"
- `MIGRATION_COUNT`: number of new migrations
- `MIGRATION_NAMES`: comma-separated migration folder names
- `SCHEMA_CHANGED`: "true" or "false"

**Note**: This check is informational only and does not block the release.

## Step 5: Extract Contributors

Get list of contributors from commits:

```bash
git log origin/main..origin/staging --format='%an' --no-merges | sort -u
```

Format as: `@username1 @username2 @username3`

## Step 6: Create Release Branch

Create the release branch from staging:

```bash
git checkout -b release/{NEW_VERSION}
```

Example: `release/2.77.0`

## Step 7: Merge Main into Release Branch

Merge main into the release branch to ensure it includes any hotfixes:

```bash
git fetch origin main
git merge origin/main --no-edit
```

This ensures the release branch has all changes from both staging and main.

## Step 8: Bump Version

Run npm version command:

```bash
npm version {TYPE}
```

This will:

- Update package.json and package-lock.json
- Create a commit with message "{VERSION}"
- Create a git tag "v{VERSION}"

**Important**: Do NOT use `--no-git-tag-version`. We want the tag created.

## Step 9: Push Release Branch

Push the release branch with tags:

```bash
git push -u origin release/{VERSION} --follow-tags
```

## Step 10: Generate Release PR Description

Use the following template and fill with extracted data:

```markdown
## Release v{VERSION}

This release includes multiple bug fixes, new features, and improvements from staging.

### Key Changes

{CATEGORIZED_CHANGES}

### Contributors

{CONTRIBUTORS_LIST}

### Testing & QA

All changes have been tested on staging environment and are ready for production deployment.

---

**Release Checklist:**

- [x] Version bumped to {VERSION} in package.json
- [x] All tests passing on staging
- [ ] Code review completed
- [ ] CI checks passing
- [ ] Ready for production deployment
```

## Step 11: Create PR to Main

Create the PR using gh CLI:

```bash
gh pr create --base main --title "[RELEASE] v{VERSION}" --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)"
```

**Important**: Always use `--base main` for release PRs.

## Step 12: Confirm and Next Steps

Output a confirmation message with conditional OpenAPI reminder:

```
✅ Release branch created: release/{VERSION}
✅ Version bumped to {VERSION}
✅ PR created: {PR_URL}
✅ Title: [RELEASE] v{VERSION}

Next steps:
1. Review the PR for accuracy
2. Get team approval (mention all contributors in PR)
3. Merge PR to main (use "Squash and merge")
4. GitHub Actions will auto-deploy to production
5. Run `/release-notes` to CREATE the GitHub release with detailed notes
6. Run `/sync` to back-merge main to staging
```

**If MIGRATIONS_CHANGED="true", append this critical section**:

```
🗄️ DATABASE MIGRATION ALERT - PRODUCTION DEPLOYMENT

This release includes ${MIGRATION_COUNT} database migration(s):
${MIGRATION_NAMES}

⚠️ CRITICAL: Migrations run automatically via docker/entrypoint.sh during ECS deployment

POST-MERGE ACTIONS REQUIRED:

1. Before Merge to Main:
   ✅ Verify migrations ran successfully in staging
   ✅ Verify staging application is fully functional
   ✅ Review migration SQL for issues (locks, data loss, etc.)
   ✅ Coordinate team: notify about deployment timing
   ✅ Prepare rollback plan if needed

2. During Production Deployment (after merge):
   👀 Monitor ECS task logs in real-time
   👀 Watch CloudWatch for migration execution
   👀 Check Datadog for application errors
   ⏱️ Be available for immediate response if issues occur

3. Migration Execution:
   - Runs automatically: npx prisma migrate deploy (in entrypoint.sh)
   - Before app starts: node dist/src/main.js
   - If migration fails: ECS task will crash and not start
   - Auto-rollback may occur if task health checks fail

4. Post-Deployment Verification:
   - Check database schema matches expectations
   - Run smoke tests on critical endpoints
   - Monitor performance metrics for degradation
   - Verify data integrity if migration involved data changes

5. If Migration Fails:
   - ECS task will crash loop
   - Check task logs for migration error details
   - Options: (a) Fix migration and redeploy, (b) Manual database fix, (c) Rollback entire release
   - Coordinate with DevOps for database access if needed

Migration Verification Checklist:
- [ ] Staging migration completed successfully
- [ ] Staging application fully tested after migration
- [ ] Team notified about production migration timing
- [ ] Monitoring dashboards ready (CloudWatch, Datadog)
- [ ] Rollback plan documented and ready
- [ ] Database backup confirmed (RDS automatic backup)
- [ ] On-call engineer available during deployment

Database Schema Changes: ${SCHEMA_CHANGED === "true" ? "Yes - Prisma schema modified" : "No schema.prisma changes"}

See docs/database-migration-checklist.md for full deployment checklist.
See docker/entrypoint.sh for migration execution details.
```

**If OPENAPI_CHANGED="true", append this additional section**:

````
📚 OpenAPI Documentation Update Detected

The OpenAPI specification was modified in this release.
Current version: {OPENAPI_VERSION}

After the release PR is merged to main, create a documentation tag to publish the updated spec:

```bash
# Checkout main and pull the merged changes
git checkout main && git pull origin main

# Create and push the documentation tag
git tag docs-v{OPENAPI_VERSION}
git push origin docs-v{OPENAPI_VERSION}
````

This will trigger the documentation publishing workflow (if configured):
`.github/workflows/docs-publish.yml`

Note: If the version in the OpenAPI spec needs updating, do so before creating the tag.

````

## Important Notes

- Release PRs always target `main` branch (not staging)
- The version bump happens on the release branch before creating PR
- `npm version` automatically creates a git tag
- GitHub Actions (`version.yml`) will verify version bump before allowing merge
- After merge, `deploy-prod.yml` will deploy to production (does NOT create GitHub release)
- The `/release-notes` command creates the GitHub release with enhanced notes
- Contributors should be mentioned in the PR for notification

## Error Handling

- If not on staging: Instruct to checkout staging
- If release branch already exists: Ask if they want to delete and recreate
- If `npm version` fails: Show error and ask user to fix manually
- If `gh pr create` fails: Provide manual PR creation instructions
- If there are no commits between staging and main: Warn user there's nothing to release

## Example Complete Flow

```bash
# User runs: /release
# Checks: on staging, up-to-date ✓
# Asks: What type? → User selects "minor"
# Shows: 2.76.0 → 2.77.0
# Extracts: 15 commits (8 fixes, 4 features, 3 improvements)
# Contributors: @rlajous @jtru13 @valentin-ratti
# Creates: release/2.77.0 branch
# Merges: origin/main into release branch
# Runs: npm version minor (updates to 2.77.0)
# Pushes: release/2.77.0 with tags
# Creates: PR #679 to main
# Output: Success message with next steps
````
