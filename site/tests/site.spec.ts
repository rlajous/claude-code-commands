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

test('dark theme preserves content and navigation', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  await expect(page.getByRole('heading', { level: 1, name: /Ship with an agent/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /Install Git Workflow/ }).first()).toBeVisible();
});
