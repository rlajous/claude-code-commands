# Contributing to Git Workflow

Git Workflow is an agent-neutral package shared by Claude Code and Codex. Contributions should improve one canonical workflow without creating host-specific forks or hidden runtime assumptions.

## Before you begin

- Use Bash, Python 3, Node.js, Git, and the GitHub CLI versions supported by the repository and documentation site.
- Search [existing issues](https://github.com/rlajous/claude-code-commands/issues) and pull requests before starting overlapping work.
- Open an issue before a large feature, new skill, breaking configuration change, or architectural refactor so the behavior can be agreed on first.
- Small fixes, tests, and documentation improvements can go directly to a focused pull request.

## Source-of-truth rules

- Edit shared skill instructions and their bundled resources under `skills/*/`; never create separate Claude and Codex implementations.
- Keep deterministic helpers in the owning skill. Root scripts are compatibility wrappers, not canonical implementations.
- Edit agent instructions under `agents/*.md`, then regenerate `.codex/agents/*.toml`; never edit generated TOML by hand.
- Keep canonical workflow configuration and state under `.git-workflow/`. Legacy `.claude/` reads are compatibility fallbacks only.
- Resolve bundled resources from the loaded `SKILL.md`, with verified plugin environment variables used only as fallbacks.
- Document Claude invocation as `/skill-name` and Codex invocation as `$skill-name`.

Read the complete [runtime compatibility contract](references/runtime-compatibility.md) before changing packaging, paths, hooks, agents, or skill resources.

## Make the change

1. Branch from `main` and keep the pull request focused on one outcome.
2. Add or update tests for behavior changes and failure paths.
3. Update canonical Markdown when an interface, configuration key, installation step, or operational workflow changes.
4. If `agents/*.md` changed, regenerate and verify the Codex definitions:

   ```bash
   node scripts/generate-codex-agents.mjs
   node scripts/generate-codex-agents.mjs --check
   ```

5. Validate the shared package:

   ```bash
   bash scripts/validate.sh
   ```

## Documentation site changes

Repository Markdown remains the source of truth. Do not edit generated files under `site/src/content/docs/generated/`, `site/public/assets/`, or `site/dist/`.

For site changes, run:

```bash
cd site
npm ci
npm run check
npm run build
npx playwright install chromium
npm run test:site
npm run test:lighthouse
```

New UI must use the existing Ceibo tokens and component patterns, remain usable at 360, 768, and 1440 pixels, support light and dark themes, and meet WCAG 2.2 AA.

## Pull request expectations

A good pull request explains the user outcome, the implementation boundaries, and how reviewers can verify it. Include screenshots for visible UI changes and exact command or API evidence where relevant.

Before requesting review:

- Ensure `git diff --check` is clean.
- Confirm tests pass from a clean checkout when practical.
- Keep generated artifacts, dependencies, credentials, and local state out of the commit.
- Preserve compatibility with both Claude Code and Codex unless the change explicitly documents a supported-host boundary.

All contributions are submitted under the repository's [MIT License](LICENSE).
