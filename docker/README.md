# docker - Praktikum Minggu 3

Stack Docker Compose: `db` (PostgreSQL) + `app` (Express/EJS) + `nginx`.

```bash
cp .env.example .env        # isi DB_PASSWORD
docker compose up -d --build
docker compose ps
```

- `compose.yaml`            : definisi service, network, dan volume
- `nginx/praktikum.conf`    : reverse proxy + rate limiter (nama upstream = service `app`)
- `../apps/Dockerfile`      : image aplikasi (multi-stage)

Pengelolaan lewat script: `../scripts/docker-manage.sh`.
