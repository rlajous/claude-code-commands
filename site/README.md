# Agent Tooling documentation site

This directory contains the static documentation site published at `https://agents.navarrolajous.com`. It is intentionally colocated with Git Workflow while the hub has one product.

The repository Markdown files remain canonical. `content-map.mjs` assigns public routes and metadata, while `scripts/sync-content.mjs` rewrites internal links, generates Starlight content, creates Markdown mirrors and `llms.txt` indexes, copies referenced assets, and produces responsive WebP derivatives. Generated files are gitignored.

## Local development

Node.js 22.12 or newer is required.

```bash
cd site
npm ci
npm run dev
```

Run the complete site validation before opening a pull request:

```bash
npm run check
npm run build
npx playwright install chromium
npm run test:site
npm run test:lighthouse
```

The Lighthouse runner stores reports locally under `.lighthouseci/`; it does not upload results. The site loads no analytics or remote fonts. The landing page makes two deferred, unauthenticated GitHub API requests for repository counters and contributors, and loads contributor avatars only from `avatars.githubusercontent.com`; a checked-in snapshot remains usable when those resources are unavailable.

## Content rules

- Edit the canonical repository Markdown, not `src/content/docs/generated/`.
- Add every published source to `content-map.mjs`; the sync fails on missing sources, duplicate slugs, and undeclared local links.
- Site-specific hub copy belongs in `src/components/HubLanding.astro`.
- Do not commit `dist/`, generated content, responsive derivatives, test results, or dependencies.
- Keep Claude invocation as `/skill-name` and Codex invocation as `$skill-name`.
- Keep runtime requests limited to the documented GitHub community endpoints. Validate all remote data and retain a complete static fallback.

## Deployment and custom domain

`.github/workflows/deploy-site.yml` builds and deploys from `main` through GitHub Pages Actions. The Astro `site` URL and `public/CNAME` both use `agents.navarrolajous.com`.

Launch sequence:

1. Merge only after package validation, site checks, Playwright, axe, and Lighthouse pass.
2. Set the Pages source to GitHub Actions and configure `agents.navarrolajous.com` as the custom domain.
3. Verify the domain in GitHub before changing DNS.
4. Add only the `agents` CNAME pointing to `rlajous.github.io`.
5. Enable HTTPS and verify `/`, `/git-workflow/`, both `llms.txt` files, `robots.txt`, and the sitemap.
6. Leave the apex and `www` Vercel records unchanged.

Rollback removes the `agents` CNAME and the Pages custom-domain association. It does not touch `navarrolajous.com` or `www.navarrolajous.com`.

After launch, submit `https://agents.navarrolajous.com/sitemap-index.xml` to Google Search Console and Bing Webmaster Tools, then update the GitHub repository homepage, description, and topics.

## Extraction threshold

Move the site to a separate repository before adding a second independently versioned product, a backend or CMS, a separate release team, or more than roughly 2 MiB of tracked site-only files excluding the lockfile. Until then, keep all site code isolated under this directory and never import it from plugin runtime resources.
