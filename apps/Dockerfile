# syntax=docker/dockerfile:1
# =====================================================================
#  Dockerfile aplikasi Task Board (multi-stage build)
#  Build :  docker build -t praktikum-app:1.0 .
# =====================================================================

# ---------- Stage 1: build ----------
# Berisi semua dependency (termasuk Tailwind) hanya untuk membangun CSS.
# Stage ini TIDAK ikut ke image akhir, sehingga image akhir lebih kecil.
FROM node:26-alpine AS build
WORKDIR /app

# Salin package*.json lebih dulu agar layer "npm install" bisa di-cache
# selama package.json tidak berubah (build ulang jadi jauh lebih cepat).
COPY package*.json ./
# --ignore-scripts: postinstall (build:css) belum bisa jalan karena source belum disalin
RUN npm install --no-audit --no-fund --ignore-scripts

COPY . .
RUN npm run build:css

# ---------- Stage 2: runtime ----------
FROM node:26-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Hanya dependency produksi (tanpa Tailwind)
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund --ignore-scripts \
    && npm cache clean --force

# Salin hanya yang dibutuhkan untuk berjalan (public sudah berisi output.css hasil build)
COPY --from=build /app/server.js ./
COPY --from=build /app/src ./src
COPY --from=build /app/views ./views
COPY --from=build /app/public ./public

# Jangan jalan sebagai root di dalam container
USER node

# Dokumentasi port (tidak membuka port ke host; itu tugas -p / compose)
EXPOSE 3000

CMD ["node", "server.js"]
