import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const primaryRoutes = ['/', '/git-workflow/', '/git-workflow/review-watch/'];
const repositoryApi = 'https://api.github.com/repos/rlajous/claude-code-commands';
const contributorsApi = `${repositoryApi}/contributors?per_page=100`;
const communityCacheKey = 'agent-tooling:github-community:v1';

/** Return one complete human contributor fixture using the production GitHub origins. */
function contributor(login: string, contributions: number) {
  return {
    type: 'User',
    login,
    contributions,
    html_url: `https://github.com/${login}`,
    avatar_url: `https://avatars.githubusercontent.com/u/${contributions + 1000}?v=4`,
  };
}

/** Fulfill the two public GitHub endpoints with deterministic community data. */
async function mockCommunityApi(page: Page, options: {
  stars?: number;
  forks?: number;
  contributors?: unknown[];
  status?: number;
} = {}) {
  const requests: string[] = [];
  await page.route(`${repositoryApi}**`, async (route) => {
    const url = route.request().url();
    requests.push(url);
    const body = url === contributorsApi
      ? (options.contributors ?? [contributor('rlajous', 26)])
      : { stargazers_count: options.stars ?? 42, forks_count: options.forks ?? 3 };
    await route.fulfill({
      status: options.status ?? 200,
      headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  });
  await page.route('https://avatars.githubusercontent.com/**', (route) => route.abort());
  return requests;
}

/** Calculate the WCAG contrast ratio for two computed RGB colors. */
function contrastRatio(foreground: string, background: string) {
  /** Convert a computed RGB color to relative luminance. */
  const luminance = (color: string) => {
    const [red, green, blue] = color.match(/[\d.]+/g)!.slice(0, 3).map(Number).map((channel) => {
      const value = channel / 255;
      return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  };
  const values = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

for (const route of primaryRoutes) {
  test(`${route} has no horizontal overflow`, async ({ page }) => {
    await page.goto(route);
    await expect(page.locator('main[data-pagefind-body]')).toBeVisible();
    const dimensions = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
    }));
    expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
  });
}

test('landing hero wraps without overflow below the supported mobile viewport', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'One Chromium project covers the narrow viewport regression.');
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto('/');
  await expect(page.locator('.hero-line').first()).toHaveCSS('white-space', 'normal');
  const dimensions = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
});

test('landing page presents both hosts and real evidence', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: /Ship software with agents/ })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Claude Code' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Codex' })).toBeVisible();
  await expect(page.getByLabel('Claude Code and Codex use one shared workflow')).toContainText('One shared workflow');
  await expect(page.getByRole('heading', { name: 'Ready for review' })).toBeVisible();
  await expect(page.getByText('20 shared skills', { exact: true }).first()).toBeVisible();
  const notificationImages = page.locator('[data-notification-image]');
  await expect(notificationImages).toHaveCount(3);
  await notificationImages.last().scrollIntoViewIfNeeded();
  await expect.poll(async () => notificationImages.evaluateAll((images) => (
    images.every((image) => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0)
  ))).toBe(true);
  await expect(page.locator('.brief-preview')).toHaveAttribute('href', '/git-workflow/examples/pr-23/');
});

test('community data is deferred, validated, sorted, and limited to twelve humans', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers the shared data contract.');
  const humans = [
    contributor('rlajous', 50),
    ...Array.from({ length: 13 }, (_, index) => contributor(`contributor-${String(index + 1).padStart(2, '0')}`, 40 - index)),
  ];
  const requests = await mockCommunityApi(page, {
    stars: 128,
    forks: 17,
    contributors: [
      ...humans.reverse(),
      { ...contributor('release-bot', 999), type: 'Bot' },
      { type: 'User', login: '', contributions: 12 },
    ],
  });

  await page.goto('/');
  await expect(page.locator('[data-community-source]')).toHaveText('GitHub snapshot');
  expect(requests).toEqual([]);

  await page.locator('#community').scrollIntoViewIfNeeded();
  await expect(page.locator('[data-community-source]')).toHaveText('Live from GitHub');
  expect(requests.sort()).toEqual([contributorsApi, repositoryApi].sort());
  await expect(page.locator('[data-community-stars]').first()).toHaveText('128');
  await expect(page.locator('[data-community-forks]')).toHaveText('17');
  await expect(page.locator('[data-community-total]')).toHaveText('14');
  await expect(page.locator('[data-community-contributors] li')).toHaveCount(12);
  await expect(page.locator('[data-community-contributors] li').first()).toContainText('@rlajous');
  await expect(page.locator('[data-community-contributors]')).not.toContainText('release-bot');
  await expect(page.locator('[data-community-overflow]')).toHaveText('+2 more human contributors on GitHub');
  await expect(page.locator('.hero-github-action')).toHaveAttribute('aria-label', 'View Git Workflow on GitHub. 128 stars');
  await expect(page.getByRole('link', { name: '128 GitHub stars. View stargazers' })).toHaveAttribute('href', 'https://github.com/rlajous/claude-code-commands/stargazers');
});

test('community cache prevents repeat API calls until it expires', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers the shared cache contract.');
  await page.addInitScript(({ key }) => {
    localStorage.setItem(key, JSON.stringify({
      storedAt: Date.now(),
      stars: 77,
      forks: 8,
      contributors: [{
        type: 'User',
        login: 'cached-user',
        contributions: 5,
        htmlUrl: 'https://github.com/cached-user',
        avatarUrl: 'https://avatars.githubusercontent.com/u/1005?v=4',
      }],
    }));
  }, { key: communityCacheKey });
  let requestCount = 0;
  await page.route(`${repositoryApi}**`, (route) => {
    requestCount += 1;
    return route.abort();
  });
  await page.route('https://avatars.githubusercontent.com/**', (route) => route.abort());

  for (let visit = 0; visit < 2; visit += 1) {
    await page.goto('/');
    await page.locator('#community').scrollIntoViewIfNeeded();
    await expect(page.locator('[data-community-source]')).toHaveText('Live from GitHub');
    await expect(page.locator('[data-community-stars]').first()).toHaveText('77');
  }
  expect(requestCount).toBe(0);
});

test('expired community cache refetches GitHub and replaces stale values', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers cache expiry.');
  await page.addInitScript(({ key }) => {
    localStorage.setItem(key, JSON.stringify({
      storedAt: Date.now() - (16 * 60 * 1000),
      stars: 1,
      forks: 1,
      contributors: [{
        type: 'User', login: 'stale', contributions: 1,
        htmlUrl: 'https://github.com/stale', avatarUrl: 'https://avatars.githubusercontent.com/u/1001?v=4',
      }],
    }));
  }, { key: communityCacheKey });
  const requests = await mockCommunityApi(page, { stars: 91, forks: 11 });
  await page.goto('/');
  await page.locator('#community').scrollIntoViewIfNeeded();
  await expect(page.locator('[data-community-stars]').first()).toHaveText('91');
  expect(requests).toHaveLength(2);
});

test('GitHub errors and malformed data preserve the complete static snapshot', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers fallback behavior.');
  await mockCommunityApi(page, { status: 403 });
  await page.goto('/');
  await page.locator('#community').scrollIntoViewIfNeeded();
  await page.waitForTimeout(250);
  await expect(page.locator('[data-community-source]')).toHaveText('GitHub snapshot');
  await expect(page.locator('[data-community-stars]').first()).toHaveText('30');
  await expect(page.locator('[data-community-contributors] li')).toHaveCount(4);
  await expect(page.getByRole('link', { name: 'Contribute to Git Workflow' })).toHaveAttribute('href', '/git-workflow/contributing/');

  await page.unrouteAll({ behavior: 'wait' });
  await page.route(`${repositoryApi}**`, (route) => route.fulfill({
    status: 200,
    headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' },
    body: JSON.stringify(route.request().url() === contributorsApi ? [{ type: 'User', login: 'unsafe', contributions: 2, html_url: 'https://example.com/unsafe', avatar_url: 'https://example.com/avatar.png' }] : { stargazers_count: 'many', forks_count: -1 }),
  }));
  await page.reload();
  await page.locator('#community').scrollIntoViewIfNeeded();
  await page.waitForTimeout(250);
  await expect(page.locator('[data-community-source]')).toHaveText('GitHub snapshot');
  await expect(page.locator('[data-community-contributors]')).not.toContainText('unsafe');
});

test('community requests abort after the deadline without replacing the snapshot', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers the four-second request deadline.');
  await page.route(`${repositoryApi}**`, async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 5_000));
    await route.fulfill({ status: 200, body: '{}' }).catch(() => undefined);
  });
  await page.goto('/');
  await page.locator('#community').scrollIntoViewIfNeeded();
  await page.waitForTimeout(4_250);
  await expect(page.locator('[data-community-source]')).toHaveText('GitHub snapshot');
  await expect(page.locator('[data-community-stars]').first()).toHaveText('30');
});

test('community avatars fall back to initials and long contributor names do not overflow', async ({ page }) => {
  const longName = 'a-very-long-human-contributor-name-for-responsive-layouts';
  await mockCommunityApi(page, { contributors: [contributor(longName, 12), contributor('rlajous', 10)] });
  await page.goto('/');
  await page.locator('#community').scrollIntoViewIfNeeded();
  await expect(page.locator('[data-community-source]')).toHaveText('Live from GitHub');
  await expect(page.locator('[data-contributor-avatar][data-avatar-error="true"]').first()).toBeVisible();
  const dimensions = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
  }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth + 1);
});

test('community ledger is accessible in light and dark themes', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers both shared theme states.');
  await page.route(`${repositoryApi}**`, (route) => route.abort());
  await page.route('https://avatars.githubusercontent.com/**', (route) => route.abort());
  for (const theme of ['light', 'dark']) {
    await page.addInitScript((preference) => localStorage.setItem('starlight-theme', preference), theme);
    await page.goto('/');
    await page.locator('#community').scrollIntoViewIfNeeded();
    await expect(page.locator('#community')).toHaveAttribute('data-reveal-state', 'visible');
    await page.waitForTimeout(600);
    const results = await new AxeBuilder({ page })
      .include('#community')
      .exclude('astro-dev-toolbar')
      .analyze();
    expect(results.violations).toEqual([]);
  }
});

test('notification evidence plays once, pauses, replays, and supports direct selection', async ({ page }) => {
  await page.goto('/');
  const stage = page.locator('[data-notification-stage]');
  const agent = page.locator('[data-notification-image="agent-finished"]');
  const changes = page.locator('[data-notification-image="changes-requested"]');
  const approved = page.locator('[data-notification-image="approved"]');
  const playback = page.getByRole('button', { name: 'Pause notification sequence' });

  await expect(agent).toHaveAttribute('data-active', 'true');
  await expect(changes).toHaveAttribute('data-active', 'true', { timeout: 2_000 });
  await expect(approved).toHaveAttribute('data-active', 'true', { timeout: 2_000 });
  await expect(stage).toHaveAttribute('data-playback', 'complete', { timeout: 2_000 });

  await page.getByRole('button', { name: 'Changes requested' }).click();
  await expect(stage).toHaveAttribute('data-playback', 'paused');
  await expect(changes).toHaveAttribute('data-active', 'true');
  await page.waitForTimeout(1_300);
  await expect(changes).toHaveAttribute('data-active', 'true');

  await page.mouse.move(0, 0);
  await page.getByRole('button', { name: 'Play notification sequence' }).click();
  await page.mouse.move(0, 0);
  await expect(page.getByRole('button', { name: 'Pause notification sequence' })).toBeFocused();
  await expect(approved).toHaveAttribute('data-active', 'true', { timeout: 2_000 });

  await page.getByRole('button', { name: 'Replay notification sequence' }).click();
  await expect(agent).toHaveAttribute('data-active', 'true');
  await playback.click();
  await expect(stage).toHaveAttribute('data-playback', 'paused');
});

test('notification evidence respects reduced motion and document visibility', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  const stage = page.locator('[data-notification-stage]');
  const agent = page.locator('[data-notification-image="agent-finished"]');
  await expect(stage).toHaveAttribute('data-playback', 'paused');
  await expect(page.locator('[data-reveal][data-reveal-state="pending"]')).toHaveCount(0);
  await page.waitForTimeout(1_300);
  await expect(agent).toHaveAttribute('data-active', 'true');

  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect(stage).toHaveAttribute('data-blocked', 'true');
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect(stage).toHaveAttribute('data-blocked', 'false');
});

test('notification evidence applies the initial hidden-document blocker', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'One Chromium project covers initialization visibility.');
  await page.addInitScript(() => {
    Object.defineProperty(Document.prototype, 'hidden', { configurable: true, get: () => true });
  });
  await page.goto('/');
  const stage = page.locator('[data-notification-stage]');
  const agent = page.locator('[data-notification-image="agent-finished"]');
  await expect(stage).toHaveAttribute('data-blocked', 'true');
  await page.waitForTimeout(1_300);
  await expect(agent).toHaveAttribute('data-active', 'true');

  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await expect(stage).toHaveAttribute('data-blocked', 'false');
  await expect(page.locator('[data-notification-image="changes-requested"]')).toHaveAttribute('data-active', 'true', { timeout: 2_000 });
});

test('landing hero starts directly below the header without a duplicate navigation band', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The two-column hero is visible at this breakpoint.');
  await page.goto('/');

  const header = await page.locator('header.header').boundingBox();
  const message = await page.locator('.hero-message').boundingBox();
  const visual = await page.locator('.hero-visual').boundingBox();
  expect(header).not.toBeNull();
  expect(message).not.toBeNull();
  expect(visual).not.toBeNull();
  expect(message!.y - (header!.y + header!.height)).toBeLessThan(96);
  expect(Math.abs(message!.y - visual!.y)).toBeLessThan(2);
  await expect(page.locator('.product-hero > .runtime-intake')).toHaveCount(0);
  await expect(page.locator('.playground-toolbar .runtime-intake')).toBeVisible();
});

test('primary call to action maintains AA contrast in every theme and hover state', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers the shared button tokens.');

  for (const theme of ['light', 'dark']) {
    await page.addInitScript((preference) => localStorage.setItem('starlight-theme', preference), theme);
    await page.goto('/');
    const button = page.getByRole('link', { name: 'Install Git Workflow' }).first();

    for (const hovered of [false, true]) {
      if (hovered) await button.hover();
      const colors = await button.evaluate((element) => {
        const style = getComputedStyle(element);
        return { foreground: style.color, background: style.backgroundColor };
      });
      expect(contrastRatio(colors.foreground, colors.background)).toBeGreaterThanOrEqual(4.5);
      if (hovered) await page.mouse.move(0, 0);
    }
  }
});

test('host quick start supports mouse, keyboard, and copy feedback', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');

  const claude = page.getByRole('tab', { name: 'Claude Code' });
  const codex = page.getByRole('tab', { name: 'Codex' });
  await expect(claude).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByRole('tabpanel', { name: 'Claude Code' })).toBeVisible();

  await claude.focus();
  await page.keyboard.press('ArrowRight');
  await expect(codex).toBeFocused();
  await expect(codex).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('[data-tabs-id="host-install"]')).toHaveAttribute('data-active-index', '1');
  await expect(page.getByRole('tabpanel', { name: 'Codex' })).toBeVisible();

  const copy = page.getByRole('button', { name: 'Copy Codex setup commands' });
  await page.keyboard.press('Tab');
  await expect(copy).toBeFocused();
  await copy.click();
  await expect(copy).toContainText('Copied');
  await expect(copy).toHaveAttribute('aria-label', 'Copy Codex setup commands. Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain('$setup');
});

test('landing sections reveal once with tokenized compositor-only motion', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'One desktop project covers the shared motion system.');
  await page.goto('/');

  const workflow = page.locator('.workflow-track');
  await expect(workflow).toHaveAttribute('data-reveal-state', 'pending');
  await workflow.scrollIntoViewIfNeeded();
  await expect(workflow).toHaveAttribute('data-reveal-state', 'visible');
  await expect.poll(() => workflow.evaluate((element) => getComputedStyle(element).opacity)).toBe('1');

  const values = await workflow.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      duration: style.transitionDuration,
      token: getComputedStyle(document.documentElement).getPropertyValue('--duration-layout').trim(),
    };
  });
  expect(['420ms', '.42s', '0.42s']).toContain(values.token);
  expect(values.duration).toContain('0.42s');
});

test('documentation shell exposes navigation, command search, and active sidebar state', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The full command shell is visible on desktop.');
  await page.goto('/git-workflow/notifications/');
  await expect(page.getByRole('navigation', { name: 'Primary navigation' })).toBeVisible();
  await expect(page.locator('.sidebar-content a[aria-current="page"]')).toContainText('Notifications');

  await page.getByRole('button', { name: 'Search' }).click();
  await expect(page.getByRole('dialog', { name: 'Search' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog', { name: 'Search' })).not.toBeVisible();
});

test('mobile documentation navigation opens without hiding core controls', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'The menu trigger is only visible on mobile.');
  await page.goto('/git-workflow/notifications/');
  await page.getByRole('button', { name: 'Menu' }).click();
  await expect(page.locator('.sidebar-pane')).toBeVisible();
  await expect(page.locator('.mobile-preferences .theme-trigger')).toBeVisible();
  await expect(page.locator('.sidebar-content a[aria-current="page"]')).toContainText('Notifications');
});

test('documentation exposes canonical, Markdown, llms, and structured data', async ({ page }) => {
  await page.goto('/git-workflow/notifications/');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://agents.navarrolajous.com/git-workflow/notifications/');
  await expect(page.locator('link[rel="alternate"][type="text/markdown"]')).toHaveAttribute('href', 'https://agents.navarrolajous.com/git-workflow/notifications/index.md');
  await expect(page.locator('link[rel="describedby"]')).toHaveAttribute('href', 'https://agents.navarrolajous.com/git-workflow/llms.txt');
  const structuredData = await page.locator('script[type="application/ld+json"]').textContent();
  expect(structuredData).toContain('SoftwareSourceCode');
});

test('contributing guide is published with canonical and agent-readable alternatives', async ({ page }) => {
  await page.goto('/git-workflow/contributing/');
  await expect(page.getByRole('heading', { level: 1, name: 'Contributing' })).toBeVisible();
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://agents.navarrolajous.com/git-workflow/contributing/');
  await expect(page.locator('link[rel="alternate"][type="text/markdown"]')).toHaveAttribute('href', 'https://agents.navarrolajous.com/git-workflow/contributing/index.md');
  await expect(page.locator('.sidebar-content a[aria-current="page"]')).toContainText('Contributing');
});

test('product documentation prioritizes its above-the-fold evidence image', async ({ page }) => {
  await page.goto('/git-workflow/');
  const evidence = page.getByRole('img', { name: /Agent Tooling documentation showing Git Workflow/ });
  await expect(evidence).toHaveAttribute('loading', 'eager');
  await expect(evidence).toHaveAttribute('fetchpriority', 'high');
});

test('standalone decision brief remains available', async ({ page }) => {
  const response = await page.goto('/git-workflow/examples/pr-23/');
  expect(response?.status()).toBe(200);
  await expect(page.locator('h1').first()).toBeVisible();
});

test('primary pages have no automatically detectable accessibility violations', async ({ page }, testInfo) => {
  const route = testInfo.project.name === 'desktop' ? '/' : '/git-workflow/';
  await page.goto(route);
  await page.waitForTimeout(600);
  const results = await new AxeBuilder({ page })
    .exclude('astro-dev-toolbar')
    .exclude('.sl-skip-link')
    .analyze();
  expect(results.violations).toEqual([]);
});

test('theme menu changes, synchronizes, and persists the explicit preference', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The desktop header control is visible at this breakpoint.');

  await page.goto('/git-workflow/notifications/');
  const trigger = page.locator('header.header starlight-theme-select .theme-trigger');
  await expect(trigger).toHaveAttribute('aria-label', 'Theme: System. Change appearance');

  await trigger.click();
  await expect(page.getByRole('menu', { name: 'Appearance' })).toBeVisible();
  await page.getByRole('menuitemradio', { name: 'Dark' }).click();

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(trigger).toHaveAttribute('aria-label', 'Theme: Dark. Change appearance');
  await expect(page.locator('starlight-theme-select .current-label')).toHaveText(['Dark', 'Dark']);
  expect(await page.evaluate(() => localStorage.getItem('starlight-theme'))).toBe('dark');

  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(trigger).toHaveAttribute('aria-label', 'Theme: Dark. Change appearance');

  await trigger.click();
  await page.getByRole('menuitemradio', { name: 'System' }).click();
  expect(await page.evaluate(() => localStorage.getItem('starlight-theme'))).toBe('');
});

test('System theme follows operating-system color scheme changes', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The desktop header control is visible at this breakpoint.');

  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/');
  const trigger = page.locator('header.header starlight-theme-select .theme-trigger');
  await expect(trigger).toHaveAttribute('aria-label', 'Theme: System. Change appearance');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

  await page.emulateMedia({ colorScheme: 'light' });
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await expect(trigger).toHaveAttribute('aria-label', 'Theme: System. Change appearance');
});

test('theme menu supports keyboard navigation and focus restoration', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The desktop header control is visible at this breakpoint.');

  await page.goto('/');
  const trigger = page.locator('header.header starlight-theme-select .theme-trigger');
  await trigger.focus();
  await trigger.press('ArrowDown');
  await expect(page.getByRole('menuitemradio', { name: 'Light' })).toBeFocused();
  await page.keyboard.press('End');
  await expect(page.getByRole('menuitemradio', { name: 'System' })).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await expect(page.getByRole('menuitemradio', { name: 'Dark' })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(trigger).toBeFocused();
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');

  await trigger.press('Space');
  await expect(page.getByRole('menu', { name: 'Appearance' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(trigger).toBeFocused();
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');

  await trigger.click();
  await trigger.click();
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');

  await trigger.click();
  await page.locator('main[data-pagefind-body]').click({ position: { x: 20, y: 200 } });
  await expect(trigger).toHaveAttribute('aria-expanded', 'false');
});

test('mobile theme control has a visible label and keeps its menu inside the viewport', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'The labeled theme control lives in the mobile menu.');

  await page.goto('/git-workflow/notifications/');
  await page.getByRole('button', { name: 'Menu' }).click();
  const trigger = page.locator('.mobile-preferences .theme-trigger');
  await expect(trigger).toBeVisible();
  await expect(trigger.locator('.current-label')).toHaveText('System');
  await trigger.click();

  const menu = page.getByRole('menu', { name: 'Appearance' });
  await expect(menu).toBeVisible();
  const bounds = await menu.boundingBox();
  expect(bounds).not.toBeNull();
  expect(bounds!.x).toBeGreaterThanOrEqual(11);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(349);
  expect(bounds!.y).toBeGreaterThanOrEqual(11);
  expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(789);
});

test('open theme menu has no automatically detectable accessibility violations', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'The desktop header control is visible at this breakpoint.');

  await page.goto('/');
  const trigger = page.locator('header.header starlight-theme-select .theme-trigger');
  await trigger.click();
  await page.waitForTimeout(600);
  let results = await new AxeBuilder({ page })
    .exclude('astro-dev-toolbar')
    .exclude('.sl-skip-link')
    .analyze();
  expect(results.violations).toEqual([]);

  await page.getByRole('menuitemradio', { name: 'Dark' }).click();
  await trigger.click();
  await page.waitForTimeout(200);
  results = await new AxeBuilder({ page })
    .exclude('astro-dev-toolbar')
    .exclude('.sl-skip-link')
    .analyze();
  expect(results.violations).toEqual([]);
});

test('open search and mobile navigation have no detectable accessibility violations', async ({ page }, testInfo) => {
  await page.goto('/git-workflow/notifications/');
  if (testInfo.project.name === 'desktop') {
    await page.getByRole('button', { name: 'Search' }).click();
  } else if (testInfo.project.name === 'mobile') {
    await page.getByRole('button', { name: 'Menu' }).click();
  } else {
    test.skip();
  }
  await page.waitForTimeout(300);
  const results = await new AxeBuilder({ page })
    .exclude('astro-dev-toolbar')
    .exclude('.sl-skip-link')
    .analyze();
  expect(results.violations).toEqual([]);
});
