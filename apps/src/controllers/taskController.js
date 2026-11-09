const Task = require('../models/taskModel');
const asyncHandler = require('../middlewares/asyncHandler');

const VALID_STATUS = ['todo', 'doing', 'done'];
const clean = (v) => (typeof v === 'string' ? v.trim() : '');

function parseId(raw) {
  const id = Number.parseInt(raw, 10);
  return Number.isInteger(id) && id > 0 ? id : null;
}

exports.list = asyncHandler(async (req, res) => {
  res.json({ data: await Task.findAll() });
});

exports.create = asyncHandler(async (req, res) => {
  const title = clean(req.body.title);
  const description = clean(req.body.description);
  const assignee = clean(req.body.assignee);

  if (title.length < 3 || title.length > 150) {
    return res.status(400).json({ error: 'Judul wajib diisi (3-150 karakter).' });
  }
  if (description.length > 500) {
    return res.status(400).json({ error: 'Deskripsi maksimal 500 karakter.' });
  }
  if (assignee.length > 80) {
    return res.status(400).json({ error: 'Nama penanggung jawab maksimal 80 karakter.' });
  }

  const task = await Task.create({
    title,
    description: description || null,
    assignee: assignee || null,
  });
  return res.status(201).json({ data: task });
});

exports.updateStatus = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  const status = clean(req.body.status);

  if (!id) return res.status(400).json({ error: 'ID tidak valid.' });
  if (!VALID_STATUS.includes(status)) {
    return res.status(400).json({ error: 'Status harus todo, doing, atau done.' });
  }

  const task = await Task.updateStatus(id, status);
  if (!task) return res.status(404).json({ error: 'Task tidak ditemukan.' });
  return res.json({ data: task });
});

exports.remove = asyncHandler(async (req, res) => {
  const id = parseId(req.params.id);
  if (!id) return res.status(400).json({ error: 'ID tidak valid.' });

  const deleted = await Task.remove(id);
  if (!deleted) return res.status(404).json({ error: 'Task tidak ditemukan.' });
  return res.json({ message: 'Task dihapus.' });
});
