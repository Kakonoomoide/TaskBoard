-- Jalankan sebagai praktikum_user:
--   psql -h 127.0.0.1 -U praktikum_user -d praktikum_db -f 02_schema.sql

CREATE TABLE IF NOT EXISTS tasks (
  id          SERIAL PRIMARY KEY,
  title       VARCHAR(150) NOT NULL,
  description TEXT,
  assignee    VARCHAR(80),
  status      VARCHAR(10) NOT NULL DEFAULT 'todo'
              CHECK (status IN ('todo', 'doing', 'done')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status);
