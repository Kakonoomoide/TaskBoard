# database - Praktikum Minggu 1

| File | Fungsi | Dijalankan oleh |
|------|--------|-----------------|
| `01_create_user_db.sql` | Membuat user + database (opsional, alternatif cara manual di modul) | superuser `postgres` |
| `02_schema.sql` | Membuat tabel `tasks` | `praktikum_user` |
| `03_seed.sql` | Mengisi data awal | `praktikum_user` |

Contoh:
```bash
psql -h 127.0.0.1 -U praktikum_user -d praktikum_db -f 02_schema.sql
psql -h 127.0.0.1 -U praktikum_user -d praktikum_db -f 03_seed.sql
```
