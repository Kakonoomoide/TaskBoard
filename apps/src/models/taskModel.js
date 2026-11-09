const pool = require('../config/db');

async function findAll() {
  const { rows } = await pool.query(
    `SELECT id, title, description, assignee, status, created_at
       FROM tasks
      ORDER BY created_at DESC, id DESC`
  );
  return rows;
}

async function create({ title, description, assignee }) {
  const { rows } = await pool.query(
    `INSERT INTO tasks (title, description, assignee)
     VALUES ($1, $2, $3)
     RETURNING id, title, description, assignee, status, created_at`,
    [title, description, assignee]
  );
  return rows[0];
}

async function updateStatus(id, status) {
  const { rows } = await pool.query(
    `UPDATE tasks SET status = $1 WHERE id = $2
     RETURNING id, title, description, assignee, status, created_at`,
    [status, id]
  );
  return rows[0] || null;
}

async function remove(id) {
  const { rowCount } = await pool.query('DELETE FROM tasks WHERE id = $1', [id]);
  return rowCount > 0;
}

module.exports = { findAll, create, updateStatus, remove };
