const { test, expect } = require('@playwright/test');
const { AxeBuilder } = require('@axe-core/playwright');
const { spawn } = require('node:child_process');
const readline = require('node:readline');
const fs = require('node:fs/promises');
let server;
let base;
let errors;

test.beforeAll(async () => {
  server = spawn('python3', ['tools/preview.py'], { stdio: ['ignore', 'pipe', 'inherit'] });
  base = await new Promise((resolve, reject) => {
    const lines = readline.createInterface({ input: server.stdout });
    const timeout = setTimeout(() => reject(new Error('Preview did not start')), 10000);
    lines.once('line', line => { clearTimeout(timeout); resolve(line); lines.close(); });
    server.once('exit', code => { clearTimeout(timeout); reject(new Error(`Preview exited: ${code}`)); });
  });
});
test.afterAll(async () => {
  if (server && server.exitCode === null) {
    await new Promise(resolve => { server.once('exit', resolve); server.kill('SIGTERM'); });
  }
});
test.beforeEach(async ({ page }) => {
  errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error' && message.text().includes('Content Security Policy')) errors.push(message.text()); });
  await page.goto(base);
});
test.afterEach(() => { expect(errors).toEqual([]); });
async function open(page) {
  await page.getByRole('button', { name: 'Find your focus' }).click();
  await expect(page).toHaveURL(`${base}/app`);
  await expect(page.locator('#empty-state')).toBeVisible();
}
async function add(page, title) {
  await page.getByRole('textbox', { name: 'New task', exact: true }).fill(title);
  await page.getByRole('button', { name: 'Add task', exact: true }).click();
  await expect(page.locator('.task-title').filter({ hasText: title })).toBeVisible();
}

test('public content, metadata and mobile layout', async ({ page }, info) => {
  await expect(page.getByRole('heading', { level: 1 })).toContainText('A clearer mind.');
  await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', 'https://asm.micutu.com/');
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  }
  await page.screenshot({ path: info.outputPath('landing.png'), fullPage: true });
});

test('task lifecycle, search, filters, sorting and progress', async ({ page }, info) => {
  await open(page);
  await add(page, 'Write the next chapter');
  await add(page, 'A little ședință 😀');
  await page.locator('#sort-tasks').selectOption('az');
  await expect(page.locator('.task-title').first()).toHaveText('A little ședință 😀');
  await page.getByRole('button', { name: 'Complete task: Write the next chapter', exact: true }).click();
  await expect(page.locator('#progress-percent')).toHaveText('50%');
  await page.locator('.filter-tabs [data-filter=done]').click();
  await expect(page.locator('#task-list > li:visible')).toHaveCount(1);
  await page.getByRole('button', { name: 'Reopen task: Write the next chapter', exact: true }).click();
  await expect(page.locator('#task-list > li:visible')).toHaveCount(0);
  await page.locator('.filter-tabs [data-filter=all]').click();
  await page.getByRole('searchbox', { name: 'Search tasks' }).fill('ședință');
  await expect(page.locator('#task-list > li:visible')).toHaveCount(1);
  await page.getByRole('searchbox', { name: 'Search tasks' }).fill('');
  await page.getByRole('button', { name: 'Edit task: Write the next chapter', exact: true }).click();
  await page.getByRole('textbox', { name: 'Task title', exact: true }).fill('A clearer next step');
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.locator('#edit-dialog')).not.toBeVisible();
  await expect(page.locator('.task-title').filter({ hasText: 'A clearer next step' })).toBeVisible();
  await page.getByRole('button', { name: 'Delete task: A clearer next step', exact: true }).click();
  await page.getByRole('button', { name: 'Keep it', exact: true }).click();
  await expect(page.locator('#task-list > li')).toHaveCount(2);
  await page.getByRole('button', { name: 'Delete task: A clearer next step', exact: true }).click();
  await page.locator('#confirm-action').click();
  await expect(page.locator('#task-list > li')).toHaveCount(1);
  await page.reload();
  await expect(page.locator('.task-title')).toHaveText('A little ședință 😀');
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  }
  await page.screenshot({ path: info.outputPath('workspace.png'), fullPage: true });
});

test('JSON/CSV exports and protected recovery download', async ({ page }) => {
  await open(page);
  await add(page, '=HYPERLINK("evil")');
  await page.getByRole('button', { name: 'Workspace & backups' }).click();
  let downloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'JSON backup' }).click();
  let download = await downloadEvent;
  const jsonText = await fs.readFile(await download.path(), 'utf8');
  const json = JSON.parse(jsonText);
  expect(json.tasks[0].title).toBe('=HYPERLINK("evil")');
  expect(jsonText).not.toContain('asm_uid');
  downloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'CSV spreadsheet' }).click();
  download = await downloadEvent;
  const csv = await fs.readFile(await download.path(), 'utf8');
  expect(csv).toContain('"\'=HYPERLINK(""evil"")"');
  downloadEvent = page.waitForEvent('download');
  await page.getByRole('link', { name: 'Save recovery key' }).click();
  download = await downloadEvent;
  const key = (await fs.readFile(await download.path(), 'utf8')).trim();
  expect(key).toMatch(/^[a-f0-9]{32}$/);
  expect(await page.evaluate(() => document.cookie)).not.toContain('asm_uid');
  expect(new URL(page.url()).search).toBe('');
});

test('theme, keyboard controls and failure feedback preserve unsaved input', async ({ page }, info) => {
  await open(page);
  await page.getByRole('button', { name: 'Switch to dark theme' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.locator('body').click({ position: { x: 1, y: 1 } });
  await page.keyboard.press('n');
  await expect(page.locator('#new-title')).toBeFocused();
  await page.locator('#new-title').fill('Do not lose this draft');
  await page.route('**/add', route => route.fulfill({ status: 507, body: 'Saving failed. Please retry later.' }));
  await page.getByRole('button', { name: 'Add task', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Saving failed');
  await expect(page.locator('#new-title')).toHaveValue('Do not lose this draft');
  await page.screenshot({ path: info.outputPath('dark-workspace.png'), fullPage: true });
});

test('UTF-8 validation, XSS text and bulk clear confirmation', async ({ page }) => {
  await open(page);
  await page.locator('#new-title').fill('😀'.repeat(28));
  expect(await page.locator('#new-title').evaluate(input => input.checkValidity())).toBeFalsy();
  await add(page, '<img src=x onerror=alert(1)>');
  await expect(page.locator('.task-title img')).toHaveCount(0);
  await page.getByRole('button', { name: 'Complete task: <img src=x onerror=alert(1)>', exact: true }).click();
  await expect(page.locator('#progress-percent')).toHaveText('100%');
  await page.getByRole('button', { name: 'Clear completed', exact: true }).click();
  await page.locator('#confirm-action').click();
  await expect(page.locator('#task-list > li')).toHaveCount(0);
  await expect(page.locator('#empty-state')).toBeVisible();
});

test('public page and workspace meet automated WCAG A/AA checks', async ({ page }) => {
  let result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(result.violations).toEqual([]);
  await open(page);
  await add(page, 'An accessible next step');
  result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(result.violations).toEqual([]);
  await page.getByRole('button', { name: 'Switch to dark theme' }).click();
  result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(result.violations).toEqual([]);
});

test('legacy browser migration avoids capability URLs', async ({ page }) => {
  await page.evaluate(() => localStorage.setItem('asm_uid', '1234567890abcdef1234567890abcdef'));
  const urls = [];
  page.on('request', request => urls.push(request.url()));
  await page.reload();
  await expect(page).toHaveURL(`${base}/app`);
  expect(urls.some(url => url.includes('uid='))).toBeFalsy();
  expect(await page.evaluate(() => localStorage.getItem('asm_uid'))).toBeNull();
});
