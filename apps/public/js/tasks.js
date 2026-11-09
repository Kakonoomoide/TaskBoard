// Logika halaman Task Board (views/index.ejs)
(function () {
  'use strict';

  const { api, showToast, formatDate } = window.App;

  const STATUS = {
    todo: { label: 'To Do', badge: 'bg-slate-100 text-slate-700' },
    doing: { label: 'Doing', badge: 'bg-amber-100 text-amber-800' },
    done: { label: 'Done', badge: 'bg-emerald-100 text-emerald-800' },
  };
  const FILTER_ACTIVE = ['bg-indigo-600', 'text-white', 'border-indigo-600'];
  const FILTER_IDLE = ['bg-white', 'text-slate-600', 'hover:bg-slate-100'];

  const form = document.getElementById('task-form');
  const list = document.getElementById('task-list');
  const emptyMsg = document.getElementById('task-empty');
  const template = document.getElementById('task-template');
  const filterButtons = document.querySelectorAll('[data-filter]');

  let tasks = [];
  let currentFilter = 'all';

  async function loadTasks() {
    try {
      const body = await api('/api/tasks');
      tasks = body.data;
      render();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  function buildItem(task) {
    const li = template.content.firstElementChild.cloneNode(true);
    const info = STATUS[task.status] || STATUS.todo;
    const field = function (name) { return li.querySelector('[data-field="' + name + '"]'); };

    li.dataset.id = task.id;
    field('title').textContent = task.title;
    field('badge').textContent = info.label;
    field('badge').classList.add(...info.badge.split(' '));
    field('description').textContent = task.description || '';
    field('description').classList.toggle('hidden', !task.description);
    field('assignee').textContent = task.assignee || 'Tanpa penanggung jawab';
    field('date').textContent = formatDate(task.created_at);
    field('status').value = task.status;
    return li;
  }

  function updateStats() {
    document.getElementById('stat-all').textContent = tasks.length;
    Object.keys(STATUS).forEach(function (key) {
      document.getElementById('stat-' + key).textContent = tasks.filter(function (t) { return t.status === key; }).length;
    });
  }

  function updateFilterButtons() {
    filterButtons.forEach(function (btn) {
      const active = btn.dataset.filter === currentFilter;
      btn.classList.remove(...FILTER_ACTIVE, ...FILTER_IDLE);
      btn.classList.add(...(active ? FILTER_ACTIVE : FILTER_IDLE));
    });
  }

  function render() {
    const visible = currentFilter === 'all' ? tasks : tasks.filter(function (t) { return t.status === currentFilter; });
    list.replaceChildren(...visible.map(buildItem));
    emptyMsg.classList.toggle('hidden', visible.length > 0);
    updateStats();
    updateFilterButtons();
  }

  async function handleCreate(event) {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(form));
    try {
      await api('/api/tasks', { method: 'POST', body: JSON.stringify(data) });
      form.reset();
      showToast('Task berhasil ditambahkan.', 'success');
      await loadTasks();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  async function handleStatusChange(id, status) {
    try {
      await api('/api/tasks/' + id, { method: 'PATCH', body: JSON.stringify({ status: status }) });
      showToast('Status diperbarui.', 'success');
    } catch (err) {
      showToast(err.message, 'error');
    }
    await loadTasks();
  }

  async function handleDelete(id) {
    if (!window.confirm('Hapus task ini?')) return;
    try {
      await api('/api/tasks/' + id, { method: 'DELETE' });
      showToast('Task dihapus.', 'success');
      await loadTasks();
    } catch (err) {
      showToast(err.message, 'error');
    }
  }

  form.addEventListener('submit', handleCreate);

  filterButtons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      currentFilter = btn.dataset.filter;
      render();
    });
  });

  list.addEventListener('change', function (event) {
    const select = event.target.closest('select[data-field="status"]');
    if (!select) return;
    handleStatusChange(select.closest('li').dataset.id, select.value);
  });

  list.addEventListener('click', function (event) {
    const btn = event.target.closest('[data-action="delete"]');
    if (!btn) return;
    handleDelete(btn.closest('li').dataset.id);
  });

  loadTasks();
})();
