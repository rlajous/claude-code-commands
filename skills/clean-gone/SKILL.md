---
name: clean-gone
description: Delete local Git branches whose upstream was deleted on the remote ("[gone]"), and remove any worktrees attached to them. Use when the user asks to clean up merged/stale branches, prune gone branches, tidy local branches after merging PRs, or "delete branches that are gone on the remote".
argument-hint: "[--dry-run]"
disable-model-invocation: false
allowed-tools: Read, Bash(git fetch:*), Bash(git branch:*), Bash(git worktree:*), Bash(git for-each-ref:*), Bash(git status:*), Bash(git config:*), Bash(git log:*), AskUserQuestion
user-invocable: true
---

> Cross-runtime: follow [runtime compatibility](../../references/runtime-compatibility.md) for invocation, delegation, configuration precedence, state paths, and permissions.

You are cleaning up local Git branches whose remote tracking branch has been deleted (shown as `[gone]` by Git), along with any worktrees checked out to them. This is destructive, so it is designed to be **safe by default**: it never discards uncommitted work or unmerged commits without explicit, informed confirmation. Follow each step in order.

## Step 1: Parse Arguments

- `--dry-run` → show exactly what *would* be removed and stop. In dry-run, **make no changes to Git state at all** (no fetch/prune, no deletion).

Default (no args): proceed through confirmation (Step 4) before any deletion.

## Step 2: Refresh Remote State (skip on `--dry-run`)

Only when NOT `--dry-run`, prune stale remote-tracking refs so `[gone]` is accurate:

```bash
git fetch --prune
```

- On `--dry-run`, do NOT run this (it mutates local refs). Use the current tracking state and note in the output that it may be stale — the user can re-run without `--dry-run` to refresh.
- If `fetch` fails (offline, no remote), warn and continue with the current state.

## Step 3: Identify Gone Branches

List local branches whose upstream is marked `[gone]`:

```bash
git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads \
  | awk '$2 == "[gone]" { print $1 }'
```

**Resolve the protected branches** (never delete these) from `.git-workflow/config.yaml`, then `.claude/config.yaml` as a legacy read-only fallback, then defaults:

- `workflow.developmentBranch` — default **`staging`**
- `workflow.productionBranch` — default **`main`**
- Also always protect: the **current branch** (`git branch --show-current`), and `master`.

Exclude every protected branch from the deletion list **even if it is marked `[gone]`** (a gone `staging`/`main` is a config/remote quirk, not a signal to delete it).

## Step 4: Assess Safety and Confirm

For each candidate branch, gather safety signals to show the user:

- **Merged?** Whether the branch's commits are already integrated (see Step 6 — prefer `git branch -d`, which refuses unmerged branches).
- **Attached worktree?** And whether that worktree is **dirty** (see Step 5).

Present a table: branch → merged/unmerged → worktree path (clean/dirty). Then:

- On `--dry-run`: print the table and **stop** (no changes).
- Otherwise, ask the user to confirm. Call out any **unmerged** branches and any **dirty** worktrees explicitly — these lose data if removed. Default to NOT removing those unless the user explicitly opts in.

## Step 5: Remove Associated Worktrees (safely)

A branch checked out in a linked worktree cannot be deleted until the worktree is removed. Map worktrees to branches:

```bash
git worktree list --porcelain
```

For each gone branch with a worktree, **check for uncommitted work first**:

```bash
git -C "{worktree_path}" status --porcelain --untracked-files=all
```

- If the output is **empty** (clean): remove it with `git worktree remove "{worktree_path}"` (no `--force` needed for a clean worktree).
- If **non-empty** (dirty/untracked files): do NOT remove it unless the user explicitly confirmed discarding its contents in Step 4. Only then use `git worktree remove --force "{worktree_path}"`. Otherwise skip the branch and report why.

Then prune administrative leftovers: `git worktree prune`.

## Step 6: Delete the Branches (merged-safe)

For each confirmed branch, try the **safe** delete first:

```bash
git branch -d "{branch_name}"
```

- `-d` succeeds only if the branch is already merged (into HEAD or its upstream). This is the desired path for the common "PR merged, remote branch deleted" case.
- If `-d` **fails because the branch is not merged**, the branch has local commits that exist nowhere else. Show them:

  ```bash
  git log --oneline "{branch_name}" --not --remotes
  ```

  Report these commits and ask the user for explicit confirmation before force-deleting. Only on explicit confirmation:

  ```bash
  git branch -D "{branch_name}"
  ```

Never force-delete (`-D`) unmerged branches without showing the commits and getting a clear yes.

## Step 7: Report

Print a summary:

```text
Pruned gone branches:
  ✓ feature/eng-123-old-thing    (merged; worktree removed: ../wt-eng-123)
  ✓ fix/proj-456-done            (merged)
  ⚠ spike/experiment             (skipped: 3 unmerged commits — not deleted)
  ⚠ feature/wip                  (skipped: worktree has uncommitted changes)

Removed: 2 branches, 1 worktree. Skipped: 2.
```

If nothing was gone, say so plainly: "No gone branches to clean up."

## Error Handling

| Scenario | Action |
| -------- | ------ |
| `git fetch` fails | Warn, continue with current tracking state |
| Branch is protected (current/dev/prod/master) | Skip it, note it is protected |
| Branch is unmerged | Skip by default; only force-delete after showing commits + explicit confirmation |
| Worktree is dirty | Skip by default; only `--force` remove after explicit confirmation |
| Worktree path is missing/locked | Report the error, skip that branch, continue |
| `git branch -d`/`-D` fails | Report and continue with the rest |
