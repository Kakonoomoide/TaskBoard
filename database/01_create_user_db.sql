-- Jalankan sebagai superuser postgres:
--   sudo -u postgres psql < 01_create_user_db.sql
-- GANTI password sebelum dijalankan!

CREATE USER praktikum_user WITH PASSWORD 'GantiPasswordKuat_123';
CREATE DATABASE praktikum_db OWNER praktikum_user;
