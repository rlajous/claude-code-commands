---
name: clean-gone
description: Delete local Git branches whose upstream was deleted on the remote ("[gone]"), and remove any worktrees attached to them. Use when the user asks to clean up merged/stale branches, prune gone branches, tidy local branches after merging PRs, or "delete branches that are gone on the remote".
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Bash(git fetch:*), Bash(git branch:*), Bash(git worktree:*), Bash(git for-each-ref:*), AskUserQuestion
user-invocable: true
---

You are cleaning up local Git branches whose remote tracking branch has been deleted (shown as `[gone]` by Git), along with any worktrees checked out to them. This is the safe way to tidy local branches after their PRs are merged and the remote branches are deleted. Follow each step in order.

## Step 1: Parse Arguments

- `--dry-run` → list what would be removed, but do not delete anything.

Default (no args): prompt for confirmation before deleting (Step 4).

## Step 2: Refresh Remote State

Prune stale remote-tracking refs so Git knows which upstreams are gone:

```bash
git fetch --prune
```

If `fetch` fails (offline, no remote), warn and continue using the current state.

## Step 3: Identify Gone Branches

List local branches whose upstream is marked `[gone]`:

```bash
git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads \
  | awk '$2 == "[gone]" { print $1 }'
```

**Safety rules — never delete:**

- The current branch (the one you are on).
- The default/production branch (`main`, `master`) and the development branch from `.claude/config.yaml` (`workflow.developmentBranch`, `workflow.productionBranch`).
- Any branch with uncommitted work you are unsure about.

Exclude those from the deletion list.

## Step 4: Confirm

Show the branches to be removed and, for each, whether it has an associated worktree (see Step 5). If not `--dry-run`, ask the user to confirm before proceeding (use AskUserQuestion). On `--dry-run`, print the list and stop here.

## Step 5: Remove Associated Worktrees

A branch checked out in a linked worktree cannot be deleted until the worktree is removed. Map worktrees to branches:

```bash
git worktree list --porcelain
```

For each gone branch that a worktree is checked out to, remove that worktree first:

```bash
git worktree remove --force "{worktree_path}"
```

Then prune any administrative leftovers:

```bash
git worktree prune
```

## Step 6: Delete the Branches

For each confirmed gone branch:

```bash
git branch -D "{branch_name}"
```

(`-D` because a gone branch is usually already merged upstream but may look "unmerged" locally.)

## Step 7: Report

Print a summary:

```text
Pruned gone branches:
  ✓ feature/eng-123-old-thing        (worktree removed: ../wt-eng-123)
  ✓ fix/proj-456-done

Removed: 2 branches, 1 worktree.
```

If nothing was gone, say so plainly: "No gone branches to clean up."

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `git fetch` fails | Warn, continue with current tracking state |
| Branch is the current branch | Skip it, note it must be left alone |
| Worktree path is missing/locked | Report the error, skip that branch, continue |
| `git branch -D` fails | Report and continue with the rest |
