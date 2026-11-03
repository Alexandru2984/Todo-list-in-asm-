'use strict';
document.querySelectorAll('[data-edit]').forEach(button => button.addEventListener('click', () => {
  const row = button.closest('li');
  const dialog = document.querySelector('#edit-dialog');
  dialog.querySelector('[name=id]').value = row.dataset.id;
  dialog.querySelector('[name=title]').value = row.querySelector('.task-title').textContent;
  dialog.showModal();
}));
document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
