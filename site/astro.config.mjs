import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { unified } from '@astrojs/markdown-remark';
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import starlight from '@astrojs/starlight';
import responsiveTables from './scripts/rehype-responsive-tables.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifest = JSON.parse(readFileSync(new URL('../.codex-plugin/plugin.json', import.meta.url), 'utf8'));
const skillCount = readdirSync(new URL('../skills/', import.meta.url), { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && existsSync(new URL(`../skills/${entry.name}/SKILL.md`, import.meta.url))).length;
const agentCount = readdirSync(new URL('../agents/', import.meta.url), { withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith('.md')).length;

export default defineConfig({
  site: 'https://agents.navarrolajous.com',
  output: 'static',
  markdown: {
    processor: unified({ rehypePlugins: [responsiveTables] }),
  },
  vite: {
    define: {
      'import.meta.env.PUBLIC_GIT_WORKFLOW_VERSION': JSON.stringify(manifest.version),
      'import.meta.env.PUBLIC_GIT_WORKFLOW_SKILL_COUNT': JSON.stringify(skillCount),
      'import.meta.env.PUBLIC_GIT_WORKFLOW_AGENT_COUNT': JSON.stringify(agentCount),
    },
    server: {
      fs: { allow: [root] },
    },
  },
  integrations: [
    starlight({
      title: 'Agent Tooling',
      description: 'Open-source workflows that help coding agents ship software with evidence and control.',
      favicon: '/favicon.svg',
      logo: {
        src: './src/assets/mark.svg',
        alt: 'Agent Tooling',
      },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/rlajous/claude-code-commands' },
      ],
      locales: { root: { label: 'English', lang: 'en' } },
      head: [
        {
          tag: 'meta',
          attrs: {
            name: 'viewport',
            content: 'width=device-width, initial-scale=1, viewport-fit=cover',
          },
        },
        {
          tag: 'meta',
          attrs: {
            property: 'og:image',
            content: 'https://agents.navarrolajous.com/assets/agent-tooling-site.png',
          },
        },
        {
          tag: 'meta',
          attrs: {
            property: 'og:image:alt',
            content: 'Agent Tooling documentation showing Git Workflow support for Claude Code and Codex.',
          },
        },
      ],
      editLink: { baseUrl: 'https://github.com/rlajous/claude-code-commands/edit/main/' },
      lastUpdated: true,
      pagefind: true,
      customCss: ['./src/styles/custom.css'],
      components: {
        Header: './src/components/Header.astro',
        Head: './src/components/Head.astro',
        PageTitle: './src/components/PageTitle.astro',
        Search: './src/components/Search.astro',
        SiteTitle: './src/components/SiteTitle.astro',
        ThemeSelect: './src/components/ThemeSelect.astro',
      },
      sidebar: [
        { label: 'Agent Tooling', link: '/' },
        {
          label: 'Start',
          items: [
            { label: 'Git Workflow', link: '/git-workflow/' },
            { label: 'Installation', link: '/git-workflow/installation/' },
            { label: 'Contributing', link: '/git-workflow/contributing/' },
          ],
        },
        {
          label: 'Operational workflows',
          items: [
            { label: 'Review Watch', link: '/git-workflow/review-watch/' },
            { label: 'Notifications', link: '/git-workflow/notifications/' },
            { label: 'Change Brief', link: '/git-workflow/change-brief/' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Commands', link: '/git-workflow/reference/commands/' },
            { label: 'Configuration', link: '/git-workflow/reference/configuration/' },
            { label: 'Hooks', link: '/git-workflow/reference/hooks/' },
            { label: 'Specialized agents', link: '/git-workflow/reference/subagents/' },
            { label: 'Runtime compatibility', link: '/git-workflow/reference/runtime-compatibility/' },
          ],
        },
        { label: 'PR #23 example', link: '/git-workflow/examples/pr-23/' },
      ],
    }),
    sitemap({
      customPages: [
        'https://agents.navarrolajous.com/git-workflow/examples/pr-23/',
      ],
    }),
  ],
});
