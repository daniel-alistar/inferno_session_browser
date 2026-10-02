const { test, expect } = require('playwright/test');

test('lists sessions, paginates, filters, bookmarks, and opens existing session links', async ({ page }) => {
  await page.goto('/sessions');
  await expect(page.locator('#status')).toHaveText('Showing 1–25 of 30 sessions');
  await expect(page.locator('[name=from]')).toHaveValue('');
  await expect(page.locator('#session-rows > tr[data-session-id]')).toHaveCount(25);
  await expect(page.locator('#session-rows')).not.toContainText('password');
  await expect(page.locator('#session-rows')).not.toContainText('never_show');
  await page.getByRole('button', { name: 'Next', exact: true }).click();
  await expect(page.locator('#status')).toHaveText('Showing 26–30 of 30 sessions');
  await expect(page).toHaveURL(/page=2/);
  await page.getByRole('button', { name: 'Previous', exact: true }).click();
  await page.locator('[name=state]').selectOption('running');
  await page.getByRole('button', { name: 'Apply filters' }).click();
  await expect(page.locator('#status')).toHaveText('Showing 1–1 of 1 sessions');
  await expect(page.locator('#session-rows')).toContainText('session29');
  await expect(page.getByRole('link', { name: 'Open session' })).toHaveAttribute('href', '/demo/session29');
  await page.reload();
  await expect(page.locator('[name=state]')).toHaveValue('running');
  await expect(page.locator('#status')).toHaveText('Showing 1–1 of 1 sessions');
  await page.getByRole('button', { name: 'Clear filters' }).click();
  await page.locator('[name=fhir_url]').fill('never_show');
  await page.getByRole('button', { name: 'Apply filters' }).click();
  await expect(page.locator('#status')).toHaveText('Showing 0–0 of 0 sessions');
});

test('expands history and paginates runs while keeping execution state separate from outcome', async ({ page }) => {
  await page.goto('/sessions?q=session29');
  await expect(page.locator('#status')).toHaveText('Showing 1–1 of 1 sessions');
  await page.getByRole('button', { name: 'Run history', exact: true }).click();
  await expect(page.locator('.history-table tbody tr')).toHaveCount(25);
  await expect(page.getByRole('button', { name: 'Hide history' })).toHaveAttribute('aria-expanded', 'true');
  await page.getByRole('button', { name: 'Next runs' }).click();
  await expect(page.locator('.history-table tbody tr')).toHaveCount(6);
  await expect(page.locator('.history-pagination')).toContainText('Page 2 · 31 runs');
  await page.getByRole('button', { name: 'Hide history' }).click();
  await expect(page.locator('.history-table')).toHaveCount(0);
});

test('retains successful rows on refresh failure and recovers', async ({ page }) => {
  await page.goto('/sessions');
  await expect(page.locator('#status')).toContainText('30 sessions');
  await page.route('**/sessions/api/sessions?*', route => route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: 'Temporary test failure' }) }));
  await page.getByRole('button', { name: 'Refresh now' }).click();
  await expect(page.locator('#error')).toHaveText('Temporary test failure');
  await expect(page.locator('#session-rows > tr[data-session-id]')).toHaveCount(25);
  await page.unroute('**/sessions/api/sessions?*');
  await page.getByRole('button', { name: 'Refresh now' }).click();
  await expect(page.locator('#error')).toBeHidden();
});

test('polls every ten seconds, honors the refresh toggle, and prevents overlapping refreshes', async ({ page }) => {
  await page.clock.install();
  let requests = 0;
  await page.route('**/sessions/api/sessions?*', async route => { requests++; await route.continue(); });
  await page.goto('/sessions');
  await expect(page.locator('#status')).toContainText('30 sessions');
  const initial = requests;
  await page.clock.fastForward(10000);
  await expect.poll(() => requests).toBe(initial + 1);
  await expect(page.locator('#sessions-table')).toHaveAttribute('aria-busy', 'false');
  await page.locator('#auto-refresh').uncheck();
  await page.clock.fastForward(20000);
  expect(requests).toBe(initial + 1);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  await page.unroute('**/sessions/api/sessions?*');
  let outstanding = 0;
  let maximum = 0;
  await page.route('**/sessions/api/sessions?*', async route => {
    outstanding++; maximum = Math.max(maximum, outstanding);
    await gate; await route.continue(); outstanding--;
  });
  await page.getByRole('button', { name: 'Refresh now' }).click();
  await expect.poll(() => outstanding).toBe(1);
  await page.getByRole('button', { name: 'Refresh now' }).click();
  release();
  await expect(page.locator('#sessions-table')).toHaveAttribute('aria-busy', 'false');
  expect(maximum).toBe(1);
});

test('applies option filters and changes page size without losing filter values', async ({ page }) => {
  await page.goto('/sessions');
  const option = page.locator('[name="suite_options[us_core_version]"]');
  await expect(option).toBeVisible();
  await option.selectOption('6');
  await page.locator('[name=fhir_url]').fill('example.org');
  await page.getByRole('button', { name: 'Apply filters' }).click();
  await expect(page.locator('#status')).toContainText('30 sessions');
  await page.locator('#page-size').selectOption('50');
  await expect(page.locator('#session-rows > tr[data-session-id]')).toHaveCount(30);
  await expect(option).toHaveValue('6');
  await expect(page.locator('[name=fhir_url]')).toHaveValue('example.org');
});

test('pauses polling while hidden and refreshes when visible again', async ({ page }) => {
  await page.clock.install();
  await page.addInitScript(() => {
    window.browserTestHidden = false;
    Object.defineProperty(document, 'hidden', { get: () => window.browserTestHidden, configurable: true });
  });
  let requests = 0;
  await page.route('**/sessions/api/sessions?*', async route => { requests++; await route.continue(); });
  await page.goto('/sessions');
  await expect(page.locator('#status')).toContainText('30 sessions');
  const initial = requests;
  await page.evaluate(() => { window.browserTestHidden = true; document.dispatchEvent(new Event('visibilitychange')); });
  await page.clock.fastForward(20000);
  expect(requests).toBe(initial);
  await page.evaluate(() => { window.browserTestHidden = false; document.dispatchEvent(new Event('visibilitychange')); });
  await expect.poll(() => requests).toBe(initial + 1);
});

test('renders a reviewable desktop layout', async ({ page }) => {
  await page.goto('/sessions');
  await expect(page.locator('#status')).toContainText('30 sessions');
  await expect(page.getByRole('heading', { name: 'Session Browser' })).toBeVisible();
  await page.screenshot({ path: 'output/playwright/session-browser.png', fullPage: true });
});
