'use strict';

// Optional browser conveniences. Task selection, ordering, counts, progress,
// editing, mutations, confirmation pages and downloads are implemented in ASM.
(() => {
  const $ = selector => document.querySelector(selector);
  document.querySelectorAll('[data-browser-only]').forEach(element => { element.hidden = false; });
  const storage = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* Optional. */ } },
    remove(key) { try { localStorage.removeItem(key); } catch { /* Optional. */ } }
  };
  function theme(value) {
    document.documentElement.dataset.theme = value;
    document.querySelectorAll('.theme-toggle').forEach(button => {
      button.setAttribute('aria-pressed', String(value === 'dark'));
      button.setAttribute('aria-label', `Switch to ${value === 'dark' ? 'light' : 'dark'} theme`);
    });
  }
  theme(storage.get('asm_theme') === 'dark' ? 'dark' : 'light');
  document.querySelectorAll('.theme-toggle').forEach(button => button.addEventListener('click', () => {
    const value = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    storage.set('asm_theme', value);
    theme(value);
  }));
  // One-time migration for browsers that used the earlier localStorage key.
  if (document.body.dataset.page === 'home') {
    const token = storage.get('asm_uid');
    if (token && /^[a-f0-9]{32}$/.test(token)) {
      const status = $('#migration-status');
      status.hidden = false;
      status.textContent = 'Restoring your existing workspace…';
      fetch('/restore', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token })
      }).then(response => {
        if (!response.ok) throw Error('Restore failed');
        storage.remove('asm_uid');
        location.replace('/app');
      }).catch(() => { status.textContent = 'Automatic restore is unavailable. Your old key is still saved; use the restore form below.'; });
    }
    return;
  }
  if (document.body.dataset.page !== 'app') return;
  // Only immediate input feedback is duplicated; the server validates every title.
  document.querySelectorAll('input[name=title]').forEach(input => input.addEventListener('input', () => {
    const bytes = new TextEncoder().encode(input.value.trim()).length;
    input.setCustomValidity(!bytes ? 'Give this task a short title.' : bytes > 110 ? 'Keep this title to 110 UTF-8 bytes or fewer.' : '');
    if (input.id === 'new-title') $('#title-bytes').textContent = `${bytes} / 110 bytes`;
  }));
  $('#sort-tasks').addEventListener('change', () => $('#view-form').requestSubmit());
  document.querySelectorAll('a[href="#workspace-tools"]').forEach(link => link.addEventListener('click', () => { $('#workspace-tools').open = true; }));
  document.addEventListener('keydown', event => {
    if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing || event.target.closest('input, textarea, select, [contenteditable=true]')) return;
    if (event.key === '/') { event.preventDefault(); $('#search-tasks').focus(); }
    if (event.key.toLowerCase() === 'n') { event.preventDefault(); $('#new-title').focus(); }
  });
  // The countdown is a local visual aid, with no task or persistence logic.
  let remaining = 25 * 60, deadline = 0, timer = null;
  const paint = () => { $('#timer-display').textContent = `${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`; };
  function stop() { clearInterval(timer); timer = null; $('#timer-toggle').textContent = remaining ? 'Resume focus' : 'Start focus'; }
  $('#timer-toggle').addEventListener('click', () => {
    if (timer) { remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000)); stop(); paint(); return; }
    if (!remaining) remaining = 25 * 60;
    deadline = Date.now() + remaining * 1000;
    $('#timer-toggle').textContent = 'Pause focus';
    timer = setInterval(() => {
      remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
      paint();
      if (!remaining) { stop(); const feedback = $('#feedback'); feedback.textContent = 'Focus session complete. Take a little breather.'; feedback.hidden = false; }
    }, 250);
  });
  $('#timer-reset').addEventListener('click', () => { remaining = 25 * 60; stop(); $('#timer-toggle').textContent = 'Start focus'; paint(); });
})();
