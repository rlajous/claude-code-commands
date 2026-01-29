---
description: Back-merge main to staging after a release to keep branches synchronized
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

You are helping sync the production branch changes back to the development branch. This command should be run AFTER a release has been merged to production and deployed to keep branches aligned.

## Step 1: Load Configuration

Check for configuration:

```bash
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
workflow:
  developmentBranch: staging
  productionBranch: main
branches:
  sync: "sync/main-to-{devBranch}"
versioning:
  file: auto
```

**Default Values:**

```yaml
workflow:
  developmentBranch: staging
  productionBranch: main
branches:
  sync: "sync/main-to-{devBranch}"
```

## Step 2: Verify Current State

Check that you're on the production branch and up-to-date:

```bash
PROD_BRANCH=$(config.workflow.productionBranch || "main")
DEV_BRANCH=$(config.workflow.developmentBranch || "staging")

# Get current branch
CURRENT=$(git branch --show-current)

# Pull latest
git pull origin ${PROD_BRANCH}
```

**Validation:**

- If not on production branch:
  ```
  You should be on {PROD_BRANCH} branch to create a sync PR.
  Run: git checkout {PROD_BRANCH} && git pull
  ```

## Step 3: Get Current Version

Read the version for reference in PR:

```bash
# Auto-detect version file
if [ -f "package.json" ]; then
  VERSION=$(node -p "require('./package.json').version")
elif [ -f "pyproject.toml" ]; then
  VERSION=$(grep -Po '(?<=version = ")[^"]*' pyproject.toml)
elif [ -f "Cargo.toml" ]; then
  VERSION=$(grep -Po '(?<=^version = ")[^"]*' Cargo.toml)
elif [ -f "VERSION" ]; then
  VERSION=$(cat VERSION)
else
  VERSION="unknown"
fi
```

## Step 4: Check What Needs Syncing

Show what commits will be synced:

```bash
git fetch origin ${DEV_BRANCH}
git log origin/${DEV_BRANCH}..origin/${PROD_BRANCH} --oneline --no-merges
```

Display to user:

```
Commits to sync from {PROD_BRANCH} to {DEV_BRANCH}:

abc1234 2.77.0
def5678 Merge pull request #679 from org/release/2.77.0
ghi9012 [Fix] Hotfix for production issue (#680)

These changes from release v{VERSION} need to be back-merged.
```

**If No Commits:**

```
{DEV_BRANCH} is already up-to-date with {PROD_BRANCH}.
No sync needed!
```

Exit early if nothing to sync.

## Step 5: Create Sync Branch

Generate sync branch name from pattern:

```bash
SYNC_PATTERN=$(config.branches.sync || "sync/main-to-{devBranch}")
SYNC_BRANCH=${SYNC_PATTERN/\{devBranch\}/${DEV_BRANCH}}

# Create sync branch from production
git checkout -b ${SYNC_BRANCH}
```

Example: `sync/main-to-staging`

## Step 6: Push Sync Branch

```bash
git push -u origin ${SYNC_BRANCH}
```

## Step 7: Rebase onto Development Branch

**Critical Step**: Rebase to skip commits already in development:

```bash
git fetch origin ${DEV_BRANCH}
git rebase origin/${DEV_BRANCH}
```

**What Happens:**

- Git automatically skips commits already in development branch
- Usually 90%+ of commits are skipped (already merged via feature PRs)
- Typically only version bump commit remains
- This is expected and correct!

**Example Output:**

```
warning: skipped previously applied commit 357fab94
warning: skipped previously applied commit 9de0e8fd
...
Successfully rebased and updated refs/heads/sync/main-to-staging.
```

After rebase, force-push:

```bash
git push origin ${SYNC_BRANCH} --force-with-lease
```

Check remaining commits:

```bash
git log origin/${DEV_BRANCH}..${SYNC_BRANCH} --oneline
```

**Expected Result**: Usually just 1-2 commits (version bump, release merge commit).

If 0 commits remain, development is already in sync - no PR needed.

## Step 8: Generate Sync PR Description

```markdown
# Sync {PROD_BRANCH} to {DEV_BRANCH} (Post-Release v{VERSION})

## Description

Back-merge production changes from {PROD_BRANCH} to {DEV_BRANCH} to keep branches aligned after release v{VERSION} deployment.

### Commits Being Synced

{LIST_OF_REMAINING_COMMITS}

### Purpose

This PR ensures {DEV_BRANCH} branch includes all production changes and version bumps from the latest release. This is a standard post-release sync operation.

### What's Included

- Version bump to {VERSION}
- Any hotfixes that went to production
- Release PR merge commit

## Checklist

- [x] {PROD_BRANCH} branch is up-to-date
- [x] Rebased onto {DEV_BRANCH} to skip duplicate commits
- [ ] Code review completed (fast-track expected)
- [ ] Ready to merge

---

**Note**: This is an automated sync PR. All changes have already been reviewed and merged to {PROD_BRANCH} via the release PR.
```

## Step 9: Create PR to Development

```bash
gh pr create \
  --base ${DEV_BRANCH} \
  --title "[SYNC] Back-merge ${PROD_BRANCH} to ${DEV_BRANCH} (post-release v${VERSION})" \
  --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)"
```

**Important**: Sync PRs target development branch (opposite of feature PRs).

## Step 10: Confirm

```
Sync branch created: {SYNC_BRANCH}
PR created: {PR_URL}
Title: [SYNC] Back-merge {PROD_BRANCH} to {DEV_BRANCH} (post-release v{VERSION})

This sync PR back-merges changes from release v{VERSION}.

Next steps:
1. Review PR (should be straightforward)
2. Get fast-track approval
3. Merge to {DEV_BRANCH}

---

Release workflow complete!
- Release v{VERSION} deployed to production
- GitHub release created with detailed notes
- {PROD_BRANCH} and {DEV_BRANCH} synchronized
```

## Configuration Reference

| Setting                      | Default                    | Description                    |
| ---------------------------- | -------------------------- | ------------------------------ |
| `workflow.developmentBranch` | `staging`                  | Development branch name        |
| `workflow.productionBranch`  | `main`                     | Production branch name         |
| `branches.sync`              | `sync/main-to-{devBranch}` | Sync branch naming pattern     |

## Error Handling

| Scenario                | Action                                         |
| ----------------------- | ---------------------------------------------- |
| Not on production branch | Instruct to checkout and pull                 |
| No commits to sync      | Exit early with success message               |
| Sync branch exists      | Ask to delete and recreate                    |
| Rebase conflicts        | Show resolution instructions                  |
| gh not authenticated    | Provide auth instructions                     |

## Conflict Resolution

If conflicts occur during rebase:

```
Conflicts detected during rebase:

{LIST_OF_CONFLICTING_FILES}

To resolve:

1. Open each file and resolve conflicts
2. Stage resolved files:
   git add {files}
3. Continue rebase:
   git rebase --continue
4. Force push:
   git push origin {SYNC_BRANCH} --force-with-lease

Or abort and resolve manually:
   git rebase --abort
```

## When to Run This Command

**Always run `/sync` after:**

1. Release PR merged to production
2. Hotfix PR merged to production
3. Any direct merge to production that needs to be in development

**Typical sequence:**

```
/release → Review → Merge → Deploy → /release-notes → /sync → Merge sync PR
```

## Example Flow

```bash
# User runs: /sync
# Checks: on main, up-to-date ✓
# Gets: version 2.77.0 from package.json
# Lists: 5 commits to sync initially
# Creates: sync/main-to-staging branch
# Pushes: sync/main-to-staging
# Rebases: onto origin/staging
# Result: 4 commits skipped, 1 remains (version bump)
# Force pushes: updated branch
# Creates: PR #680 to staging
# Output: Success with completion message
```

## Alternative Workflows

### Tag-Based Workflow

For projects without a staging branch:

```yaml
workflow:
  type: tag-based
  developmentBranch: develop
  productionBranch: main
```

### Direct Workflow

For simpler projects:

```yaml
workflow:
  type: direct
  developmentBranch: main
  productionBranch: main
```

In direct workflow, sync is not needed as there's only one branch.
