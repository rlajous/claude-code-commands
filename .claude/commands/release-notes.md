---
description: Enhance GitHub release with detailed notes after release PR is merged to main
---

You are helping enhance a GitHub release with comprehensive release notes. This command should be run AFTER the release PR has been merged to main and GitHub Actions has created the basic release.

## Step 1: Verify Current State

Check that you're on main branch and it's up-to-date:

```bash
git branch --show-current
git pull origin main
```

If not on main:

```
⚠️ You should be on main branch after the release PR is merged.
Please run: git checkout main && git pull
```

## Step 2: Get Current Version

Read the version from package.json:

```bash
VERSION=$(node -p "require('./package.json').version")
TAG_NAME="v${VERSION}"
```

Show the user:

```
Current version: {VERSION}
Release tag: v{VERSION}
```

## Step 3: Check if Release Exists

Check if GitHub release already exists:

```bash
gh release view v{VERSION} 2>&1
```

**Note**: GitHub Actions does NOT automatically create releases - this command will create it.

If release exists, you'll see release details. If not, you'll see "release not found".

Store this result to determine whether to CREATE or EDIT the release in Step 8.

## Step 4: Get Previous Release Version

Find the previous release tag:

```bash
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 2 | tail -n 1
```

This will be used for the "Full Changelog" link.

## Step 5: Extract Detailed Changes

Get commits between previous and current release:

```bash
git log {PREV_TAG}..v{VERSION} --pretty=format:"%s|%b" --no-merges
```

Parse and categorize commits with MORE detail than the PR:

### Bug Fixes (🐛)

For each fix, try to extract:

- Main title from commit
- PR number
- Additional context from commit body if available
- Format as detailed bullet points

Example:

```
- **[API] Fix trending coins endpoint and date formatting** (#662)
  - Fixed invalid query parameters and date format issues
  - Improved error handling for trending coins API
```

### Enhancements (✨)

For features and improvements:

- Title
- PR number
- Key improvements bullet points

Example:

```
- **[Fix] Improve holder analysis accuracy with per-address queries** (#655)
  - Implemented net flow calculation to prevent double-counting
  - Added unique buyer count and segmentation flags
  - Increased analysis depth from 200 to 500 first traders
```

## Step 6: List Previous Releases

Get the last 2-3 releases for context:

```bash
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 4 | tail -n 3
```

Format as:

```
### 📊 Previous Releases Included

- v2.76.0 - EIP-7702 support, holder analysis improvements
- v2.75.0 - OFAC enrichment, cross-chain risk tags
- v2.74.8 - Token metadata improvements
```

## Step 7: Generate Enhanced Release Notes

Use the following template:

```markdown
## Release v{VERSION}

This release includes multiple bug fixes, security enhancements, and improved token analysis accuracy.

### 🐛 Bug Fixes

{DETAILED_BUG_FIXES}

### ✨ Enhancements

{DETAILED_ENHANCEMENTS}

### 📊 Previous Releases Included

{PREVIOUS_RELEASES_LIST}

**Full Changelog**: https://github.com/your-org/your-repo/compare/{PREV_TAG}...v{VERSION}
```

## Step 8: Create or Update GitHub Release

Based on Step 3 result, either CREATE or EDIT the release:

### If Release Does NOT Exist (Most Common):

Create the release using gh CLI:

```bash
gh release create v{VERSION} --title "v{VERSION}" --notes "$(cat <<'EOF'
{ENHANCED_NOTES}
EOF
)"
```

### If Release Already Exists:

Update the existing release:

```bash
gh release edit v{VERSION} --notes "$(cat <<'EOF'
{ENHANCED_NOTES}
EOF
)"
```

**Alternative** if gh command fails, provide manual instructions:

```
To manually create/update the release:
1. Go to: https://github.com/your-org/your-repo/releases
2. Click "Create a new release" or find v{VERSION} and click "Edit"
3. Tag: v{VERSION}
4. Title: v{VERSION}
5. Paste the enhanced notes in the description
6. Click "Publish release" or "Update release"
```

## Step 9: Confirm

Output a confirmation message:

```
✅ GitHub release v{VERSION} created/updated with detailed notes
✅ Release URL: https://github.com/your-org/your-repo/releases/tag/v{VERSION}

Next step:
Run `/sync` to back-merge main to staging
```

## Important Notes

- This command should be run AFTER the release PR is merged to main
- **GitHub Actions does NOT create releases** - this command creates them
- Usually the release won't exist yet, so `gh release create` will be used
- Uses emoji section headers (🐛, ✨, 📊) for visual clarity
- Includes Full Changelog link for complete diff view
- This is the official way to create release notes for this repository

## Error Handling

- If not on main: Instruct to checkout main
- If release doesn't exist: Check GitHub Actions status
- If `gh release edit` fails: Provide manual update instructions
- If previous tag not found: Skip "Previous Releases" section

## Detailed Extraction Strategy

When parsing commits for detailed notes:

1. **Extract from PR description if possible**:

   - Use `gh pr view {PR_NUMBER} --json body` to get full PR description
   - Extract key points from "What Changed" or "Issues Fixed" sections

2. **Fallback to commit message**:

   - Use commit title as main bullet
   - Use commit body for sub-bullets (if exists)

3. **Categorization**:
   - `[Fix]`, `[FIX]`, `fix:` → Bug Fixes
   - `[Feature]`, `feat:` → Enhancements
   - `[API]`, `[TEAM-XXXX]` → Keep prefix in title

## Example Complete Flow

```bash
# User runs: /release-notes
# Checks: on main, up-to-date ✓
# Gets: version 2.77.0 from package.json
# Verifies: release v2.77.0 exists ✓
# Finds: previous release v2.76.0
# Extracts: 15 commits with details
# Generates: Enhanced release notes with emojis
# Updates: GitHub release v2.77.0
# Output: Success with release URL
```

## Example Enhanced Note Format

```markdown
## Release v2.77.0

This release includes multiple bug fixes, security enhancements, and improved token analysis accuracy.

### 🐛 Bug Fixes

- **[API] Fix trending coins endpoint and date formatting** (#662)

  - Fixed invalid query parameters and date format issues
  - Improved error handling for trending coins API
  - Enhanced validation for date range inputs

- **[FIX][TEAM-2552] Unlimited plan quota alert false positives** (#657)
  - Excluded unlimited usage plans from quota alerts
  - Prevents false positive Slack notifications
  - Improved plan type detection logic

### ✨ Enhancements

- **[Fix] Improve holder analysis accuracy with per-address queries** (#655)

  - Implemented net flow calculation to prevent double-counting
  - Added unique buyer count and segmentation flags
  - Increased analysis depth from 200 to 500 first traders
  - Enhanced percentage calculation precision

- **Add tri-state renounced field to token risk** (#645)
  - Added tri-state renounced field (true/false/null)
  - Enhanced with EIP-1967 proxy admin slot detection
  - Added DEFAULT_ADMIN_ROLE enumeration support

### 📊 Previous Releases Included

- v2.76.0 - EIP-7702 delegated EOA detection, holder analysis improvements
- v2.75.0 - OFAC enrichment, cross-chain risk tags, token by risk level endpoint
- v2.74.8 - Token metadata improvements, logo handling fixes

**Full Changelog**: https://github.com/your-org/your-repo/compare/v2.76.0...v2.77.0
```
