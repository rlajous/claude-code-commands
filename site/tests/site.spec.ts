import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const primaryRoutes = ['/', '/git-workflow/', '/git-workflow/review-watch/'];

function contrastRatio(foreground: string, background: string) {
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

test('landing page presents both hosts and real evidence', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1, name: /Ship software with agents/ })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Claude Code' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Codex' })).toBeVisible();
  await expect(page.getByLabel('Claude Code and Codex use one shared workflow')).toContainText('One shared workflow');
  await expect(page.getByRole('heading', { name: 'Ready for review' })).toBeVisible();
  await expect(page.getByText('20 shared skills', { exact: true }).first()).toBeVisible();
  const notificationImages = page.locator('.notification-stack img');
  await expect(notificationImages).toHaveCount(3);
  await notificationImages.last().scrollIntoViewIfNeeded();
  await expect.poll(async () => notificationImages.evaluateAll((images) => (
    images.every((image) => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0)
  ))).toBe(true);
  await expect(page.locator('.brief-preview')).toHaveAttribute('href', '/git-workflow/examples/pr-23/');
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
  await expect(page.getByRole('tabpanel', { name: 'Codex' })).toBeVisible();

  const copy = page.getByRole('button', { name: 'Copy Codex setup commands' });
  await copy.click();
  await expect(copy).toContainText('Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain('$setup');
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
