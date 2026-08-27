# Agent Tooling design system

The site is an editorial engineering field guide, not a generic component showcase. Real workflow evidence carries the visual weight; UI primitives stay compact and operational.

## Foundations

- **Color:** Ceibo coral is reserved for primary actions and human checkpoints. Sage communicates health, focus, and secondary state. Warm paper and blue-black ink provide the dominant surfaces.
- **Type:** Avenir Next carries product and documentation hierarchy; monospace is limited to commands and technical metadata. Display and section sizes scale fluidly while body copy remains stable at `1rem`.
- **Space:** A 4px foundation feeds a small fluid scale from `--space-3xs` through `--space-3xl`. Components use the smallest semantic step that preserves grouping and 44px targets.
- **Shape:** Restrained radii and borders define structure. Light mode may use subtle elevation; dark mode uses surface contrast instead of shadows.
- **Motion:** Feedback uses 80–140ms, state changes use 240ms, layout transitions use 420ms, and composed entrances use 600ms. Animate only opacity and transforms. Reduced motion removes spatial transitions.

## Token contract

`src/styles/tokens.css` owns primitive and semantic values. Components consume semantic names such as `--action`, `--border`, `--text-lead`, or `--duration-state`; they never introduce raw colors or CSS durations.

Run `npm run test:design-system` to detect token drift. Add a token only when a value has a reusable role, not to hide a one-off number.

## Component and interaction rules

- Use cards only for independently actionable or comparable content. Prefer dividers and spacing for hierarchy inside a larger surface.
- Every control needs default, hover, focus-visible, active, and disabled treatment where applicable.
- Tabs use one shared selection indicator and roving focus. Popovers use the native top layer and restore focus on dismissal.
- Motion explains state or sequence. The landing page has one entrance choreography, one in-view evidence sequence, and brief control feedback.
- Keep labels concrete and host-aware: `/skill-name` for Claude Code and `$skill-name` for Codex.

## Reference material

The implementation adapts principles rather than importing frameworks: [UI Skills](https://ui-skills.com/), [The Component Gallery](https://component.gallery/), [DesignSystems.one](https://designsystems.one/), [Utopia](https://utopia.fyi/), [Open Props](https://open-props.style/), [Interfaces](https://interfaces.rauno.me/), and [Motion Primitives](https://motion-primitives.com/).
