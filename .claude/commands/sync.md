---
description: Back-merge main to staging after a release to keep branches synchronized
---

You are helping sync main branch changes back to staging. This command should be run AFTER a release has been merged to main and deployed to keep branches aligned.

## Step 1: Verify Current State

Check that you're on main branch and it's up-to-date:

```bash
git branch --show-current
git pull origin main
```

If not on main:

```
⚠️ You should be on main branch to create a sync PR.
Please run: git checkout main && git pull
```

## Step 2: Get Current Version

Read the version from package.json to reference in PR:

```bash
VERSION=$(node -p "require('./package.json').version")
```

This will be used in the PR title/description.

## Step 3: Check What Needs to be Synced

Show the user what commits will be synced from main to staging:

```bash
git log origin/staging..origin/main --oneline --no-merges
```

Display the commits:

```
Commits to be synced from main to staging:

{LIST_OF_COMMITS}

These are the changes from release v{VERSION} that need to be back-merged to staging.
```

If there are no commits to sync:

```
✅ Staging is already up-to-date with main. No sync needed.
```

Exit early if nothing to sync.

## Step 4: Create Sync Branch

Create a sync branch from main:

```bash
git checkout -b sync/main-to-staging
```

Alternative naming (if preferred): `sync/main-to-staging-{VERSION}` or `sync/main-to-staging-{TIMESTAMP}`

## Step 5: Push Sync Branch

Push the sync branch:

```bash
git push -u origin sync/main-to-staging
```

## Step 5.5: Rebase Sync Branch onto Staging (Critical!)

**IMPORTANT**: Before creating the PR, rebase the sync branch onto staging to skip commits that are already in staging.

Fetch latest staging and rebase:

```bash
git fetch origin staging
git rebase origin/staging
```

**What will happen:**

- Git will automatically skip commits that are already in staging
- Usually 90% of commits will be skipped (already merged via feature PRs)
- Typically only the version bump commit remains
- This is the expected and correct behavior!

Example output:

```
warning: skipped previously applied commit 357fab94
warning: skipped previously applied commit 9de0e8fd
...
Successfully rebased and updated refs/heads/sync/main-to-staging.
```

After rebase, force-push the updated branch:

```bash
git push origin sync/main-to-staging --force-with-lease
```

Check what commits remain after rebase:

```bash
git log origin/staging..sync/main-to-staging --oneline
```

**Expected result**: Usually just 1 commit (the version bump from `npm version`).

If you see 0 commits, it means staging already has everything from main and no sync is needed.

## Step 6: Generate Sync PR Description

Use the following template:

```markdown
# Sync main to staging (Post-Release v{VERSION})

## Description

Back-merge production changes from main to staging to keep branches aligned after release v{VERSION} deployment.

### Commits Being Synced

{LIST_COMMITS_WITH_TITLES}

### Purpose

This PR ensures staging branch includes all production changes and version bumps from the latest release. This is a standard post-release sync operation that maintains branch alignment between staging and main.

### What's Included

- Version bump to {VERSION}
- All bug fixes, features, and improvements from release v{VERSION}
- Release PR merge commit

## Checklist

- [x] Main branch is up-to-date
- [x] No conflicts with staging (auto-checked by GitHub)
- [ ] Code review completed (fast-track approval expected for sync PRs)
- [ ] Ready to merge to staging

---

**Note**: This is an automated sync PR. All changes have already been reviewed and merged to main via the release PR.
```

## Step 7: Create PR to Staging

Create the PR using gh CLI:

```bash
gh pr create --base staging --title "[SYNC] Back-merge main to staging (post-release v{VERSION})" --body "$(cat <<'EOF'
{GENERATED_DESCRIPTION}
EOF
)"
```

**Important**: Always use `--base staging` for sync PRs (not main).

## Step 8: Confirm and Next Steps

Output a confirmation message:

```
✅ Sync branch created: sync/main-to-staging
✅ PR created: {PR_URL}
✅ Title: [SYNC] Back-merge main to staging (post-release v{VERSION})

This sync PR back-merges all changes from release v{VERSION} to staging.

Next steps:
1. Review the PR (should be straightforward - all changes already reviewed)
2. Get fast-track approval (sync PRs are typically approved quickly)
3. Merge PR to staging
4. Staging and main are now synchronized!

---

✨ Release workflow complete! ✨
- Release v{VERSION} deployed to production ✓
- GitHub release enhanced with detailed notes ✓
- Main and staging branches synchronized ✓
```

## Important Notes

- Sync PRs always go from main → staging (opposite of regular feature PRs)
- This should be done after EVERY release to keep branches aligned
- Sync PRs typically get fast-track approval since changes were already reviewed
- The sync ensures staging has the version bump and any hotfixes
- This is a critical step - skipping it leads to merge conflicts later

## Error Handling

- If not on main: Instruct to checkout main
- If no commits to sync: Skip PR creation, branches are aligned
- If sync branch already exists: Ask if they want to delete and recreate
- If `gh pr create` fails: Provide manual PR creation instructions
- If there are conflicts: Show conflicts and provide resolution guidance

## Conflict Resolution

If GitHub detects conflicts during sync:

1. Show the user the conflicting files
2. Provide instructions:

```
⚠️ Conflicts detected in the following files:
{CONFLICTING_FILES}

To resolve:
1. git checkout sync/main-to-staging
2. git merge origin/staging
3. Resolve conflicts in the listed files
4. git add {CONFLICTING_FILES}
5. git commit -m "Resolve sync conflicts"
6. git push origin sync/main-to-staging

The PR will automatically update.
```

## Example Complete Flow

```bash
# User runs: /sync
# Checks: on main, up-to-date ✓
# Gets: version 2.77.0 from package.json
# Lists: 3 commits to sync (release merge + version bump + changelog)
# Creates: sync/main-to-staging branch
# Pushes: sync/main-to-staging
# Creates: PR #680 to staging
# Output: Success message with next steps
```

## Example Sync PR Description

```markdown
# Sync main to staging (Post-Release v2.77.0)

## Description

Back-merge production changes from main to staging to keep branches aligned after release v2.77.0 deployment.

### Commits Being Synced

- Merge pull request #679 from your-org/release/2.77.0
- 2.77.0 (version bump)
- Merge pull request #662 from your-org/fix/trending-coins
- Merge pull request #655 from your-org/fix/holder-analysis

### Purpose

This PR ensures staging branch includes all production changes and version bumps from the latest release. This is a standard post-release sync operation that maintains branch alignment between staging and main.

### What's Included

- Version bump to 2.77.0
- All bug fixes, features, and improvements from release v2.77.0
- Release PR merge commit

## Checklist

- [x] Main branch is up-to-date
- [x] No conflicts with staging
- [ ] Code review completed (fast-track approval expected for sync PRs)
- [ ] Ready to merge to staging

---

**Note**: This is an automated sync PR. All changes have already been reviewed and merged to main via the release PR.
```

## When to Run This Command

**Always run `/sync` after:**

1. Release PR merged to main
2. Hotfix PR merged to main
3. Any direct merge to main that needs to be in staging

**Typical sequence:**

```
/release → Review → Merge to main → Deploy → /release-notes → /sync → Merge sync PR
```

This ensures staging always reflects what's in production.
