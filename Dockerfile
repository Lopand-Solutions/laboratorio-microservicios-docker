# Etapa 1: solo instala dependencias de producción.
FROM node:22-alpine AS dependencias
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Etapa 2: lo que comparten los dos servicios.
FROM node:22-alpine AS base
WORKDIR /app
ENV NODE_ENV=production
COPY --from=dependencias /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
USER node

# Imagen del worker: sano si su latido tiene menos de 30 segundos.
FROM base AS worker
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "const t = require('fs').statSync('/tmp/latido').mtimeMs; process.exit(Date.now() - t < 30000 ? 0 : 1)"
CMD ["node", "src/worker.js"]

# Imagen de la api. Va al final: un docker build sin --target da la api.
FROM base AS api
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["node", "src/api.js"]
