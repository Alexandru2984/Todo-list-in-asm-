'use strict';

(() => {
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const storage = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* Optional preferences. */ } },
    remove(key) { try { localStorage.removeItem(key); } catch { /* Optional migration. */ } }
  };

  function theme(value) {
    document.documentElement.dataset.theme = value;
    $$('.theme-toggle').forEach(button => {
      button.setAttribute('aria-pressed', String(value === 'dark'));
      button.setAttribute('aria-label', `Switch to ${value === 'dark' ? 'light' : 'dark'} theme`);
    });
  }
  theme(storage.get('asm_theme') === 'dark' ? 'dark' : 'light');
  $$('.theme-toggle').forEach(button => button.addEventListener('click', () => {
    const value = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    storage.set('asm_theme', value);
    theme(value);
  }));

  // Migrate earlier localStorage capabilities through a POST, never a new URL.
  if (document.body.dataset.page === 'home') {
    const oldKey = storage.get('asm_uid');
    if (oldKey && /^[a-f0-9]{32}$/.test(oldKey)) {
      const status = $('#migration-status');
      status.hidden = false;
      status.textContent = 'Restoring your existing workspace…';
      fetch('/restore', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: oldKey })
      }).then(response => {
        if (!response.ok) throw new Error('Migration failed');
        storage.remove('asm_uid');
        location.replace('/app');
      }).catch(() => { status.textContent = 'Automatic restore is unavailable. Your old key is still saved in this browser; use the restore form below.'; });
    }
    return;
  }
  if (document.body.dataset.page !== 'app') return;

  let filter = ['all', 'active', 'done'].includes(storage.get('asm_filter')) ? storage.get('asm_filter') : 'all';
  let toastTimeout;
  let busy = false;
  const addInput = $('#new-title');
  const encoder = new TextEncoder();
  const viewNames = { all: 'All tasks', active: 'In progress', done: 'Completed' };
  const tasks = () => $$('#task-list > li');

  function announce(message, error = false) {
    const feedback = $('#feedback');
    clearTimeout(toastTimeout);
    feedback.hidden = false;
    feedback.classList.toggle('error', error);
    feedback.textContent = message;
    toastTimeout = setTimeout(() => { feedback.hidden = true; }, error ? 10000 : 4500);
  }

  function validTitle(input) {
    const bytes = encoder.encode(input.value.trim()).length;
    input.setCustomValidity(!bytes ? 'Give this task a short title.' : bytes > 110 ? `This title uses ${bytes} bytes. Please keep it to 110 or fewer.` : '');
    if (input === addInput) $('#title-bytes').textContent = `${bytes} / 110 bytes`;
    return bytes > 0 && bytes <= 110;
  }
  [addInput, $('#edit-title')].forEach(input => input.addEventListener('input', () => validTitle(input)));

  function update() {
    const rows = tasks();
    const done = rows.filter(row => row.dataset.done === '1').length;
    const counts = { total: rows.length, active: rows.length - done, done };
    for (const [name, count] of Object.entries(counts)) $$(`[data-count="${name}"]`).forEach(el => { el.textContent = count; });
    $$('[data-filter]').forEach(button => {
      const selected = button.dataset.filter === filter;
      button.classList.toggle('selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
    $('#breadcrumb-view').textContent = viewNames[filter];
    const query = $('#search-tasks').value.trim().toLocaleLowerCase();
    const sort = $('#sort-tasks').value;
    rows.sort((a, b) => {
      if (sort === 'az') return a.querySelector('.task-title').textContent.localeCompare(b.querySelector('.task-title').textContent);
      if (sort === 'active' && a.dataset.done !== b.dataset.done) return a.dataset.done.localeCompare(b.dataset.done);
      // Compare decimal IDs without losing precision for legacy 64-bit values.
      const cmp = a.dataset.id.length - b.dataset.id.length || a.dataset.id.localeCompare(b.dataset.id);
      return sort === 'oldest' ? cmp : -cmp;
    });
    const list = $('#task-list');
    let visible = 0;
    rows.forEach(row => {
      const title = row.querySelector('.task-title').textContent;
      row.hidden = !((filter === 'all' || row.dataset.done === (filter === 'done' ? '1' : '0')) && title.toLocaleLowerCase().includes(query));
      if (!row.hidden) visible++;
      list.append(row);
      const date = new Date(Number(row.dataset.ts) * 1000);
      const time = row.querySelector('.task-date');
      if (!Number.isNaN(date.getTime())) {
        time.dateTime = date.toISOString();
        time.textContent = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
        time.title = date.toLocaleString();
      } else { time.textContent = 'Created earlier'; }
      row.querySelector('[data-edit]').setAttribute('aria-label', `Edit task: ${title}`);
      const toggle = row.querySelector('form[action="/complete"] button, form[action="/reopen"] button');
      toggle.setAttribute('aria-label', `${row.dataset.done === '1' ? 'Reopen' : 'Complete'} task: ${title}`);
      row.querySelector('.delete-button').setAttribute('aria-label', `Delete task: ${title}`);
    });
    $('#visible-count').textContent = visible;
    $('#stats').textContent = rows.length ? `${counts.active} task${counts.active === 1 ? '' : 's'} left · ${done} completed${visible !== rows.length ? ` · ${visible} shown` : ''}` : 'A fresh start. Make it a good one.';
    $('#clear-trigger').disabled = done === 0;
    $$('[data-export]').forEach(button => { button.disabled = rows.length === 0; });
    const percent = rows.length ? Math.round(done / rows.length * 100) : 0;
    $('#task-progress').value = percent;
    $('#task-progress').textContent = `${percent}%`;
    $('#progress-percent').textContent = `${percent}%`;
    $('#progress-heading').textContent = percent === 100 ? 'Look at you. Every task, done.' : 'A little progress goes a long way.';
    $('#progress-description').textContent = done ? `${done} small win${done === 1 ? '' : 's'} worth celebrating. Keep going at your own pace.` : 'Your next small win is waiting.';
    const empty = $('#empty-state');
    empty.hidden = visible > 0;
    $('#empty-title').textContent = rows.length ? 'A little breathing room.' : 'A little space for your next big thing.';
    $('#empty-description').textContent = rows.length ? 'No tasks match this view. Try another filter or a different search.' : 'Add your first task above. Every good day starts with one small step.';
    $('#empty-action').textContent = rows.length ? 'Show all tasks →' : 'Add your first task →';
  }

  document.addEventListener('click', event => {
    const button = event.target.closest('[data-filter]');
    if (button) {
      filter = button.dataset.filter;
      storage.set('asm_filter', filter);
      update();
    }
    if (event.target.closest('[data-close]')) event.target.closest('dialog').close();
    const edit = event.target.closest('[data-edit]');
    if (edit) {
      const row = edit.closest('li');
      const dialog = $('#edit-dialog');
      dialog.querySelector('[name=id]').value = row.dataset.id;
      $('#edit-title').value = row.querySelector('.task-title').textContent;
      $('#edit-title').setCustomValidity('');
      dialog.showModal();
      $('#edit-title').select();
    }
  });
  $('#search-tasks').addEventListener('input', update);
  $('#sort-tasks').addEventListener('change', () => { storage.set('asm_sort', $('#sort-tasks').value); update(); });
  const savedSort = storage.get('asm_sort');
  if (['newest', 'oldest', 'az', 'active'].includes(savedSort)) $('#sort-tasks').value = savedSort;
  $('#empty-action').addEventListener('click', () => {
    if (tasks().length) { filter = 'all'; $('#search-tasks').value = ''; storage.set('asm_filter', filter); update(); }
    else addInput.focus();
  });
  $('#today-date').textContent = new Date().toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });

  function confirmAction(heading, description, label) {
    const dialog = $('#confirm-dialog');
    $('#confirm-heading').textContent = heading;
    $('#confirm-description').textContent = description;
    $('#confirm-action').textContent = label;
    dialog.returnValue = 'cancel';
    return new Promise(resolve => {
      dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
      dialog.showModal();
      dialog.querySelector('button[value=cancel]').focus();
    });
  }

  async function mutate(action, body, sourceForm) {
    if (busy) { announce('A change is still being saved. One moment.'); return; }
    busy = true;
    const submit = sourceForm?.querySelector('button[type=submit], button:not([type])');
    if (submit) submit.disabled = true;
    try {
      const response = await fetch(action, {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body
      });
      if (!response.ok) throw new Error((await response.text()).trim() || 'The change could not be saved.');
      if (action === '/forget') { location.assign('/'); return; }
      const html = await response.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const freshList = doc.querySelector('#task-list');
      if (!freshList) throw new Error('Your session may have expired. Reload to open or restore your workspace.');
      $('#task-list').replaceChildren(...freshList.children);
      if (action === '/add') { addInput.value = ''; validTitle(addInput); addInput.focus({ preventScroll: true }); }
      if (action === '/edit') $('#edit-dialog').close();
      update();
      const messages = { '/add': 'One small step, added.', '/complete': 'A small win. Nicely done.', '/reopen': 'Back on your list.', '/delete': 'Task deleted.', '/edit': 'A little clearer. Changes saved.', '/clear-done': 'A little more breathing room.' };
      announce(messages[action] || 'Changes saved.');
    } catch (error) {
      announce(error instanceof TypeError ? 'Connection interrupted. Your change may have been saved. Reload before retrying.' : error.message, true);
    } finally {
      busy = false;
      if (submit?.isConnected) submit.disabled = false;
    }
  }

  document.addEventListener('submit', async event => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.method.toLowerCase() !== 'post') return;
    event.preventDefault();
    const action = new URL(form.action).pathname;
    const titleInput = form.querySelector('[name=title]');
    if (titleInput && !validTitle(titleInput)) { titleInput.reportValidity(); return; }
    // Capture values before awaiting a confirmation or network response.
    const body = new URLSearchParams(new FormData(form));
    if (action === '/delete' && !await confirmAction('Let this one go?', 'This task will be permanently deleted. This action cannot be undone.', 'Delete task')) return;
    if (action === '/forget' && !await confirmAction('Leave this workspace?', 'Save your recovery key first. Without it, you cannot return to these tasks after this browser forgets them.', 'Forget workspace')) return;
    await mutate(action, body, form);
  });

  $('#clear-trigger').addEventListener('click', async () => {
    const done = tasks().filter(row => row.dataset.done === '1').length;
    if (!done) return;
    if (await confirmAction('Make room for what’s next?', `${done} completed task${done === 1 ? '' : 's'} will be permanently deleted. Active tasks stay on your list.`, 'Clear completed')) {
      await mutate('/clear-done', new URLSearchParams());
    }
  });

  function openSettings() { $('#settings-dialog').showModal(); }
  $('#workspace-settings').addEventListener('click', openSettings);
  $('#export-menu').addEventListener('click', openSettings);


  document.addEventListener('keydown', event => {
    if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing || $('dialog[open]')) return;
    if (event.target.closest('input, textarea, select, [contenteditable=true]')) return;
    if (event.key === '/') { event.preventDefault(); $('#search-tasks').focus(); }
    if (event.key.toLowerCase() === 'n') { event.preventDefault(); addInput.focus(); }
  });

  let remaining = 25 * 60;
  let deadline = 0;
  let timer = null;
  function paintTimer() {
    $('#timer-display').textContent = `${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`;
  }
  function stopTimer() {
    clearInterval(timer);
    timer = null;
    $('#timer-toggle').textContent = remaining ? 'Resume focus' : 'Start focus';
  }
  $('#timer-toggle').addEventListener('click', () => {
    if (timer) { remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000)); stopTimer(); paintTimer(); return; }
    if (!remaining) remaining = 25 * 60;
    deadline = Date.now() + remaining * 1000;
    $('#timer-toggle').textContent = 'Pause focus';
    timer = setInterval(() => {
      remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      paintTimer();
      if (!remaining) { stopTimer(); announce('Focus session complete. Take a little breather.'); }
    }, 250);
  });
  $('#timer-reset').addEventListener('click', () => { remaining = 25 * 60; stopTimer(); $('#timer-toggle').textContent = 'Start focus'; paintTimer(); });
  update();
})();
