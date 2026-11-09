-- Data awal (hanya diisi jika tabel masih kosong)
--   psql -h 127.0.0.1 -U praktikum_user -d praktikum_db -f 03_seed.sql

INSERT INTO tasks (title, description, assignee, status)
SELECT v.title, v.description, v.assignee, v.status
FROM (VALUES
  ('Install PostgreSQL',        'Buat user dan database untuk aplikasi.',          'Anggota 1', 'done'),
  ('Install NVM dan Node.js',   'Pasang Node.js lewat NVM dan cek versinya.',      'Anggota 2', 'done'),
  ('Konfigurasi file .env',     'Isi kredensial database dengan benar.',           'Anggota 2', 'doing'),
  ('Jalankan aplikasi di PM2',  'Pastikan auto-restart dan startup saat boot.',    'Anggota 4', 'todo'),
  ('Konfigurasi Nginx',         'Reverse proxy port 80 ke 3000 + rate limiter.',   'Anggota 3', 'todo')
) AS v(title, description, assignee, status)
WHERE NOT EXISTS (SELECT 1 FROM tasks);
