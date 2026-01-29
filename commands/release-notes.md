---
description: Enhance GitHub release with detailed notes after release PR is merged to main
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
user-invocable: true
---

You are helping enhance a GitHub release with comprehensive release notes. This command should be run AFTER the release PR has been merged to the production branch.

## Step 1: Load Configuration

Check for configuration:

```bash
[ -f ".claude/config.yaml" ] && echo "CONFIG=true" || echo "CONFIG=false"
```

**Load from `.claude/config.yaml` (if exists):**

```yaml
workflow:
  productionBranch: main
versioning:
  file: auto
release:
  generateChangelog: true
  changelogCategories:
    - name: "Bug Fixes"
      prefixes: ["[Fix]", "[FIX]", "fix:"]
      emoji: "bug"
    - name: "Features"
      prefixes: ["[Feature]", "feat:"]
      emoji: "sparkles"
```

**Default Values:**

```yaml
workflow:
  productionBranch: main
versioning:
  file: auto
```

## Step 2: Verify Current State

Check that you're on the production branch and up-to-date:

```bash
PROD_BRANCH=$(config.workflow.productionBranch || "main")

# Get current branch
CURRENT=$(git branch --show-current)

# Pull latest
git pull origin ${PROD_BRANCH}
```

**Validation:**

- If not on production branch:
  ```
  You should be on {PROD_BRANCH} branch after the release PR is merged.
  Run: git checkout {PROD_BRANCH} && git pull
  ```

## Step 3: Get Current Version

Detect version file and read current version:

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
fi

TAG_NAME="v${VERSION}"
```

Display to user:

```
Current version: {VERSION}
Release tag: v{VERSION}
```

## Step 4: Check if Release Exists

```bash
gh release view v${VERSION} 2>&1
```

**Possible States:**

1. Release exists → Will update with enhanced notes
2. Release doesn't exist → Will create new release
3. Tag doesn't exist → Error, release flow not completed

Store this result for Step 8 (create vs edit).

## Step 5: Get Previous Release

Find the previous release tag for changelog comparison:

```bash
# Get all version tags sorted by version number
PREV_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 2 | tail -n 1)

# If no previous tag, use initial commit
if [ -z "$PREV_TAG" ]; then
  PREV_TAG=$(git rev-list --max-parents=0 HEAD)
fi
```

## Step 6: Extract Detailed Changes

Get commits between previous and current release:

```bash
git log ${PREV_TAG}..v${VERSION} --pretty=format:"%H|%s|%b" --no-merges
```

### Parse and Categorize

For each commit, extract:

1. **Commit hash** - For reference
2. **Title** - Main commit message
3. **Body** - Additional details
4. **PR Number** - From title or body

### Categorization Rules

| Category       | Match Patterns                               | Emoji |
| -------------- | -------------------------------------------- | ----- |
| Bug Fixes      | `[Fix]`, `[FIX]`, `fix:`, `fix(`             | 🐛    |
| Features       | `[Feature]`, `feat:`, `feat(`                | ✨    |
| Improvements   | `[Refactor]`, `[Perf]`, `improve`, `enhance` | ⚡    |
| Documentation  | `[Docs]`, `docs:`                            | 📝    |
| Security       | `[Security]`, `security:`                    | 🔒    |
| Other          | Everything else                              | 📦    |

### Get PR Details (Optional)

For richer release notes, fetch PR details:

```bash
# For each PR number found
gh pr view {PR_NUMBER} --json title,body,labels
```

Extract:

- PR title
- Key points from description
- Labels (for categorization)

### Format Detailed Notes

```markdown
### 🐛 Bug Fixes

- **[API] Fix trending coins endpoint and date formatting** (#662)
  - Fixed invalid query parameters
  - Improved date format validation
  - Added error handling for edge cases

### ✨ Features

- **Add cross-chain risk tag aggregation** (#648)
  - Supports EVM address risk analysis
  - Aggregates tags from multiple chains
```

## Step 7: Get Previous Releases Context

List recent releases for context:

```bash
# Get last 3-5 releases
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 5
```

For each, get a brief summary:

```bash
gh release view v{VERSION} --json tagName,name,body 2>/dev/null | jq -r '.name'
```

Format as:

```markdown
### 📊 Recent Releases

- **v2.76.0** - EIP-7702 support, holder analysis improvements
- **v2.75.0** - OFAC enrichment, cross-chain risk tags
- **v2.74.8** - Token metadata improvements
```

## Step 8: Generate Enhanced Release Notes

Use this template:

```markdown
## Release v{VERSION}

{Brief summary of release - 1-2 sentences}

### 🐛 Bug Fixes

{DETAILED_BUG_FIXES}

### ✨ Features

{DETAILED_FEATURES}

### ⚡ Improvements

{DETAILED_IMPROVEMENTS}

### 📝 Documentation

{DOCUMENTATION_CHANGES - if any}

### 📊 Recent Releases

{PREVIOUS_RELEASES_SUMMARY}

---

**Full Changelog**: https://github.com/{owner}/{repo}/compare/{PREV_TAG}...v{VERSION}
```

## Step 9: Create or Update GitHub Release

Based on Step 4 result:

### If Release Does NOT Exist (Common)

```bash
gh release create v${VERSION} \
  --title "v${VERSION}" \
  --notes "$(cat <<'EOF'
{ENHANCED_NOTES}
EOF
)"
```

### If Release Already Exists

```bash
gh release edit v${VERSION} \
  --notes "$(cat <<'EOF'
{ENHANCED_NOTES}
EOF
)"
```

### If Tag Doesn't Exist

```
Error: Tag v{VERSION} not found.

This usually means the release workflow didn't complete properly.
Please verify:
1. The release PR was merged to {PROD_BRANCH}
2. The version was bumped correctly
3. The tag was created during the release process

To manually create the tag:
git checkout {PROD_BRANCH}
git pull
git tag v{VERSION}
git push origin v{VERSION}

Then run /release-notes again.
```

## Step 10: Confirm

```
GitHub release v{VERSION} created with detailed notes
Release URL: https://github.com/{owner}/{repo}/releases/tag/v{VERSION}

Next step: Run /sync to back-merge {PROD_BRANCH} to {DEV_BRANCH}
```

## Configuration Reference

| Setting                     | Default    | Description                  |
| --------------------------- | ---------- | ---------------------------- |
| `workflow.productionBranch` | `main`     | Production branch name       |
| `versioning.file`           | `auto`     | Version file location        |
| `release.generateChangelog` | `true`     | Generate detailed changelog  |
| `release.changelogCategories` | (default)| Custom categorization rules  |

## Error Handling

| Scenario                | Action                                        |
| ----------------------- | --------------------------------------------- |
| Not on production branch | Instruct to checkout and pull                |
| Tag doesn't exist       | Provide manual tag creation steps            |
| gh not authenticated    | Run `gh auth login` instructions             |
| No previous tag         | Use initial commit as baseline               |
| gh release fails        | Provide manual creation instructions         |

## Manual Fallback

If `gh` command fails:

```
To manually create/update the release:

1. Go to: https://github.com/{owner}/{repo}/releases
2. Click "Create a new release" or find v{VERSION} and click "Edit"
3. Tag: v{VERSION}
4. Title: v{VERSION}
5. Paste these notes:

---
{ENHANCED_NOTES}
---

6. Click "Publish release" or "Update release"
```

## Example Enhanced Release Notes

```markdown
## Release v2.77.0

This release includes security enhancements, improved holder analysis accuracy, and multiple bug fixes.

### 🐛 Bug Fixes

- **[API] Fix trending coins endpoint and date formatting** (#662)

  - Fixed invalid query parameters and date format issues
  - Improved error handling for trending coins API
  - Enhanced validation for date range inputs

- **[FIX] Unlimited plan quota alert false positives** (#657)
  - Excluded unlimited usage plans from quota alerts
  - Prevents false positive Slack notifications

### ✨ Features

- **Add cross-chain risk tag aggregation for EVM addresses** (#648)
  - Aggregates risk tags from multiple chains
  - Supports comprehensive address risk analysis

### ⚡ Improvements

- **Improve holder analysis accuracy with per-address queries** (#655)
  - Implemented net flow calculation to prevent double-counting
  - Added unique buyer count and segmentation flags
  - Increased analysis depth from 200 to 500 first traders

### 📊 Recent Releases

- **v2.76.0** - EIP-7702 delegated EOA detection, holder analysis improvements
- **v2.75.0** - OFAC enrichment, cross-chain risk tags, token by risk level endpoint
- **v2.74.8** - Token metadata improvements, logo handling fixes

---

**Full Changelog**: https://github.com/org/repo/compare/v2.76.0...v2.77.0
```

## Example Flow

```bash
# User runs: /release-notes
# Checks: on main, up-to-date ✓
# Gets: version 2.77.0 from package.json
# Verifies: tag v2.77.0 exists ✓
# Checks: release doesn't exist yet
# Finds: previous release v2.76.0
# Extracts: 15 commits with details
# Generates: Enhanced release notes with emojis
# Creates: GitHub release v2.77.0
# Output: Success with release URL
```
