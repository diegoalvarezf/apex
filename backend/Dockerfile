# Imagen del backend, en dos etapas.
#
# El motivo no es el tamaño sino los secretos: Railway inyecta todas las variables
# del servicio como ARG/ENV en el build, y lo que entra en ENV queda grabado en las
# capas de la imagen, legible con `docker history`. Compilar no necesita ninguna
# credencial —`tsc` solo traduce TypeScript, y la configuración se valida al
# arrancar—, así que las variables se quedan en la etapa de construcción y la
# imagen final no las hereda.
#
# De paso la imagen adelgaza bastante: la final no lleva ni el código fuente, ni
# TypeScript, ni las dependencias de desarrollo.
#
# OJO con las rutas: el contexto del build es la RAÍZ del repositorio (ahí está el
# .git que Railway clona), no esta carpeta. Por eso todo va con el prefijo backend/.

# ---------- Etapa 1: compilar ----------
FROM node:22-alpine AS build

WORKDIR /app

# Se copian primero los manifiestos: mientras no cambien, Docker reutiliza la capa
# de dependencias y no reinstala en cada despliegue.
COPY backend/package.json backend/package-lock.json ./
RUN npm ci

COPY backend/tsconfig.json ./
COPY backend/src ./src
RUN npm run build

# Se rehace el árbol dejando solo dependencias de producción. Vitest, tsx,
# drizzle-kit y PGlite no pintan nada en la imagen que se despliega.
RUN npm ci --omit=dev

# ---------- Etapa 2: ejecutar ----------
FROM node:22-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production

# Solo lo imprescindible para arrancar. Nada de código fuente ni herramientas.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY backend/package.json ./
# Las migraciones se aplican al arrancar, así que el SQL viaja con la imagen.
COPY backend/drizzle ./drizzle

# Node no debe correr como root: si alguien lograra ejecutar algo dentro del
# contenedor, no lo haría con todos los permisos. La imagen base ya trae `node`.
USER node

EXPOSE 3000

# Migrar y arrancar. Se usa el JavaScript ya compilado, no tsx, que es una
# dependencia de desarrollo y no está en esta imagen.
CMD ["sh", "-c", "node dist/db/migrate.js && node dist/index.js"]
