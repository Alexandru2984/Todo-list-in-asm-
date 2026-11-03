const { test, expect } = require('@playwright/test');
const { AxeBuilder } = require('@axe-core/playwright');
const { spawn } = require('node:child_process');
const readline = require('node:readline');
const fs = require('node:fs/promises');
let server;
let base;
let dataDir;
let errors;

test.beforeAll(async () => {
  server = spawn('python3', ['tools/preview.py', '--json'], { stdio: ['ignore', 'pipe', 'inherit'] });
  base = await new Promise((resolve, reject) => {
    const lines = readline.createInterface({ input: server.stdout });
    const timeout = setTimeout(() => reject(new Error('Preview did not start')), 10000);
    lines.once('line', line => { clearTimeout(timeout); const info = JSON.parse(line); dataDir = info.data; resolve(info.url); lines.close(); });
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

async function menuAction(page, title, action) {
  const row = page.locator('#task-list > li').filter({ hasText: title });
  await row.locator('summary').click();
  await row.getByRole('link', { name: action, exact: true }).click();
}

test('native task lifecycle, server search, filters, sorting and progress', async ({ page }, info) => {
  await open(page);
  await add(page, 'Write the next chapter');
  await add(page, 'A little ședință 😀');
  await page.locator('#sort-tasks').selectOption('az');
  await expect(page.locator('.task-title').first()).toHaveText('A little ședință 😀');
  let row = page.locator('#task-list > li').filter({ hasText: 'Write the next chapter' });
  await row.getByRole('button', { name: 'Complete task', exact: true }).click();
  await expect(page.locator('#progress-percent')).toHaveText('50%');
  await page.locator('.filter-tabs [data-filter=done]').click();
  await expect(page.locator('#task-list > li')).toHaveCount(1);
  await page.getByRole('button', { name: 'Reopen task', exact: true }).click();
  await page.locator('.filter-tabs [data-filter=done]').click();
  await expect(page.locator('#task-list > li')).toHaveCount(0);
  await page.locator('.filter-tabs [data-filter=all]').click();
  await page.getByRole('searchbox', { name: 'Search tasks' }).fill('ȘEDINȚĂ');
  await page.getByRole('searchbox', { name: 'Search tasks' }).press('Enter');
  await expect(page.locator('#task-list > li')).toHaveCount(1);
  await page.getByRole('searchbox', { name: 'Search tasks' }).fill('');
  await page.getByRole('searchbox', { name: 'Search tasks' }).press('Enter');
  await menuAction(page, 'Write the next chapter', 'Edit');
  await page.getByRole('textbox', { name: 'Task title', exact: true }).fill('A clearer next step');
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.locator('.task-title').filter({ hasText: 'A clearer next step' })).toBeVisible();
  await menuAction(page, 'A clearer next step', 'Delete');
  await page.getByRole('link', { name: 'Keep it', exact: true }).click();
  await expect(page.locator('#task-list > li')).toHaveCount(2);
  await menuAction(page, 'A clearer next step', 'Delete');
  await page.getByRole('button', { name: 'Delete task', exact: true }).click();
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
  await page.getByRole('link', { name: 'Workspace & backups' }).click();
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
  const key = (await page.context().cookies()).find(cookie => cookie.name === 'asm_uid').value;
  const blocked = `${dataDir}/todos-${key}.txt.tmp`;
  await fs.mkdir(blocked);
  await page.getByRole('button', { name: 'Add task', exact: true }).click();
  await expect(page.locator('body')).toContainText('Saving failed');
  await expect(page.locator('#new-title')).toHaveValue('Do not lose this draft');
  await fs.rmdir(blocked);
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page.locator('.task-title')).toHaveText('Do not lose this draft');
  await page.screenshot({ path: info.outputPath('dark-workspace.png'), fullPage: true });
});

test('UTF-8 validation, XSS text and bulk clear confirmation', async ({ page }) => {
  await open(page);
  await page.locator('#new-title').fill('😀'.repeat(28));
  expect(await page.locator('#new-title').evaluate(input => input.checkValidity())).toBeFalsy();
  await add(page, '<img src=x onerror=alert(1)>');
  await expect(page.locator('.task-title img')).toHaveCount(0);
  await page.getByRole('button', { name: 'Complete task', exact: true }).click();
  await expect(page.locator('#progress-percent')).toHaveText('100%');
  await page.getByRole('link', { name: 'Clear completed', exact: true }).click();
  await page.getByRole('button', { name: 'Clear completed', exact: true }).click();
  await expect(page.locator('#task-list > li')).toHaveCount(0);
  await expect(page.locator('#empty-state')).toBeVisible();
});

test('public page and workspace meet automated WCAG A/AA checks', async ({ page }) => {
  let result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
  expect(result.violations).toEqual([]);
  await open(page);
  await page.locator('.task-properties > summary').click();
  await page.getByRole('combobox', { name: 'Priority', exact: true }).selectOption('urgent');
  await page.getByLabel('Due date (UTC)', { exact: true }).fill('2027-02-28');
  await add(page, 'An accessible next step');
  await page.locator('.task-properties > summary').click();
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


test('complete workspace works with JavaScript disabled', async ({ browser, page }) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: page.viewportSize() });
  const native = await context.newPage();
  try {
    await native.goto(base);
    await native.getByRole('button', { name: 'Find your focus' }).click();
    await native.getByRole('textbox', { name: 'New task', exact: true }).fill('Pure Assembly workspace');
    await native.getByRole('button', { name: 'Add task', exact: true }).click();
    await expect(native.locator('[data-count=total]').first()).toHaveText('1');
    await native.getByRole('searchbox', { name: 'Search tasks' }).fill('ASSEMBLY');
    await native.getByRole('searchbox', { name: 'Search tasks' }).press('Enter');
    await expect(native.locator('#task-list > li')).toHaveCount(1);
    await menuAction(native, 'Pure Assembly workspace', 'Edit');
    await native.getByRole('textbox', { name: 'Task title', exact: true }).fill('Native edit');
    await native.getByRole('button', { name: 'Save changes' }).click();
    await expect(native.locator('.task-title')).toHaveText('Native edit');
    await native.locator('#task-list summary').click();
    await native.getByRole('button', { name: 'Duplicate', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(2);
    await native.locator('#task-list > li').first().getByRole('button', { name: 'Complete task', exact: true }).click();
    await expect(native.locator('#progress-percent')).toHaveText('50%');
    await native.locator('.filter-tabs [data-filter=done]').click();
    await expect(native.locator('#task-list > li')).toHaveCount(1);
    await native.locator('#workspace-tools > summary').click();
    const event = native.waitForEvent('download');
    await native.getByRole('link', { name: 'JSON backup' }).click();
    const download = await event;
    const records = JSON.parse(await fs.readFile(await download.path(), 'utf8')).tasks;
    expect(records).toHaveLength(2); // Export includes all tasks, not just visible rows.
    await native.getByRole('link', { name: 'Clear completed', exact: true }).click();
    await native.getByRole('button', { name: 'Clear completed', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(1);
  } finally { await context.close(); }
});


test('planner priority, due dates and recurrence work without JavaScript on mobile and desktop', async ({ browser, page }, info) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: page.viewportSize() });
  const native = await context.newPage();
  try {
    await native.goto(base);
    await native.getByRole('button', { name: 'Find your focus' }).click();
    await native.locator('.task-properties > summary').click();
    await native.getByRole('combobox', { name: 'Priority', exact: true }).selectOption('urgent');
    await native.getByLabel('Due date (UTC)', { exact: true }).fill('2027-02-28');
    await native.getByRole('textbox', { name: 'Project', exact: true }).fill('Ședință');
    await native.getByRole('textbox', { name: 'Tags (comma separated)', exact: true }).fill('asm, mobile');
    await native.getByRole('textbox', { name: 'New task', exact: true }).fill('Native planner milestone');
    await native.getByRole('button', { name: 'Add task', exact: true }).click();
    await expect(native.locator('.priority-badge')).toHaveText('urgent priority');
    await expect(native.locator('.project-badge')).toHaveText('Project: Ședință');
    await expect(native.locator('.tags-badge')).toHaveText('Tags: asm,mobile');
    await native.locator('.filter-properties > summary').click();
    await native.getByRole('textbox', { name: 'Project filter', exact: true }).fill('șEDINȚĂ');
    await native.getByRole('textbox', { name: 'Tag filter', exact: true }).fill('MOBILE');
    await native.getByRole('button', { name: 'Apply project filters' }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(1);
    await native.getByRole('searchbox', { name: 'Search tasks' }).fill('priority:urgent project:"ședință" #mobile "Native planner"');
    await native.getByRole('searchbox', { name: 'Search tasks' }).press('Enter');
    await expect(native.locator('#task-list > li')).toHaveCount(1);
    await expect(native.locator('.due-badge')).toHaveText('Due 2027-02-28');
    await menuAction(native, 'Native planner milestone', 'Edit');
    const edit = native.locator('#action-form');
    await expect(edit.getByRole('combobox', { name: 'Priority', exact: true })).toHaveValue('urgent');
    await expect(edit.getByLabel('Due date (UTC)', { exact: true })).toHaveValue('2027-02-28');
    await edit.getByRole('combobox', { name: 'Priority', exact: true }).selectOption('low');
    await edit.getByLabel('Due date (UTC)', { exact: true }).fill('');
    await edit.getByRole('button', { name: 'Save changes' }).click();
    await expect(native.locator('.priority-badge')).toHaveText('low priority');
    await expect(native.locator('.due-badge')).toHaveCount(0);
    await menuAction(native, 'Native planner milestone', 'Edit');
    const recurrenceForm = native.locator('#action-form');
    await recurrenceForm.getByLabel('Due date (UTC)', { exact: true }).fill('2031-01-31');
    await recurrenceForm.getByRole('combobox', { name: 'Repeat', exact: true }).selectOption('monthly');
    await recurrenceForm.getByRole('button', { name: 'Save changes' }).click();
    await native.getByRole('button', { name: 'Complete task', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(2);
    const nextOccurrence = native.locator('#task-list > li[data-done="0"]');
    await expect(nextOccurrence.locator('.due-badge')).toHaveText('Due 2031-02-28');
    await expect(nextOccurrence.locator('.repeat-badge')).toHaveText('Repeats monthly');
    await native.locator('.task-properties > summary').click();
    for (const width of [320, 390, 768, 1440]) {
      await native.setViewportSize({ width, height: 1000 });
      expect(await native.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
    }
    await native.setViewportSize(page.viewportSize());
    await native.screenshot({ path: info.outputPath('planner.png'), fullPage: true });
  } finally { await context.close(); }
});


test('native subtasks and prerequisites prevent blocked completion without JavaScript', async ({ browser, page }, info) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: page.viewportSize() });
  const native = await context.newPage();
  try {
    await native.goto(base);
    await native.getByRole('button', { name: 'Find your focus' }).click();
    await add(native, 'Parent milestone');
    await add(native, 'Independent prerequisite');
    await menuAction(native, 'Parent milestone', 'Add subtask');
    const details = native.locator('.task-properties');
    await details.locator('summary').click();
    await expect(details.getByLabel('Parent task ID (0 for none)', { exact: true })).toHaveValue('1');
    await details.getByLabel('Prerequisite IDs (comma separated)', { exact: true }).fill('2');
    await add(native, 'Child milestone');
    const child = native.locator('#task-list > li').filter({ hasText: 'Child milestone' });
    await expect(child.getByRole('button', { name: 'Complete task', exact: true })).toBeDisabled();
    await native.getByRole('link', { name: 'Blocked', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(2);
    await native.screenshot({ path: info.outputPath('relations.png'), fullPage: true });
    await native.locator('.filter-tabs [data-filter=all]').click();
    await native.locator('#task-list > li').filter({ hasText: 'Independent prerequisite' }).getByRole('button', { name: 'Complete task', exact: true }).click();
    await native.locator('#task-list > li').filter({ hasText: 'Child milestone' }).getByRole('button', { name: 'Complete task', exact: true }).click();
    await native.locator('#task-list > li').filter({ hasText: 'Parent milestone' }).getByRole('button', { name: 'Complete task', exact: true }).click();
    await expect(native.locator('#progress-percent')).toHaveText('100%');
  } finally { await context.close(); }
});


test('native undo, redo, trash restore and permanent removal work without JavaScript', async ({ browser, page }, info) => {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: page.viewportSize() });
  const native = await context.newPage();
  try {
    await native.goto(base);
    await native.getByRole('button', { name: 'Find your focus' }).click();
    await add(native, 'Undo and restore milestone');
    await native.getByRole('button', { name: 'Undo last change', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(0);
    await native.getByRole('button', { name: 'Redo last change', exact: true }).click();
    await expect(native.locator('.task-title')).toHaveText('Undo and restore milestone');
    await menuAction(native, 'Undo and restore milestone', 'Delete');
    await native.getByRole('button', { name: 'Delete task', exact: true }).click();
    await native.getByRole('link', { name: /^Trash \(/ }).click();
    await expect(native.locator('.task-title')).toHaveText('Undo and restore milestone');
    await native.getByRole('button', { name: 'Restore', exact: true }).click();
    await expect(native.locator('.task-title')).toHaveText('Undo and restore milestone');
    await menuAction(native, 'Undo and restore milestone', 'Delete');
    await native.getByRole('button', { name: 'Delete task', exact: true }).click();
    await native.getByRole('link', { name: /^Trash \(/ }).click();
    await native.getByRole('link', { name: 'Purge', exact: true }).click();
    await expect(native.getByRole('button', { name: 'Permanently remove', exact: true })).toBeVisible();
    await native.screenshot({ path: info.outputPath('trash-confirmation.png'), fullPage: true });
    await native.getByRole('button', { name: 'Permanently remove', exact: true }).click();
    await expect(native.locator('#task-list > li')).toHaveCount(0);
    await expect(native.getByRole('button', { name: 'Undo last change', exact: true })).toBeDisabled();
    await expect(native.getByRole('button', { name: 'Redo last change', exact: true })).toBeDisabled();
  } finally { await context.close(); }
});
