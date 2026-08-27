import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const primaryRoutes = ['/', '/git-workflow/', '/git-workflow/review-watch/'];

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
  await expect(page.getByRole('heading', { level: 1, name: /Ship with an agent/ })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Claude Code' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Codex' })).toBeVisible();
  const fieldIndex = page.getByRole('navigation', { name: 'Landing page sections' });
  await expect(fieldIndex.getByRole('link')).toHaveCount(4);
  await expect(fieldIndex.getByRole('link', { name: /01\s*Install/i })).toHaveAttribute('href', '#install');
  await expect(fieldIndex.getByRole('link', { name: /03\s*Evidence/i })).toHaveAttribute('href', '#evidence');
  const notificationImages = page.locator('.notification-proof img');
  await expect(notificationImages).toHaveCount(3);
  await notificationImages.last().scrollIntoViewIfNeeded();
  await expect.poll(async () => notificationImages.evaluateAll((images) => (
    images.every((image) => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0)
  ))).toBe(true);
  await expect(page.getByRole('link', { name: /Open the real PR #23 brief/ })).toHaveAttribute('href', '/git-workflow/examples/pr-23/');
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
