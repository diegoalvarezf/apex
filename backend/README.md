# Backend de APEX

Servidor intermedio entre la app y las APIs de terceros. Existe por dos motivos
concretos, no por gusto arquitectónico:

1. **El `client_secret` de Strava.** Su OAuth lo exige para canjear y refrescar
   tokens, y no admite PKCE. Dentro de la app viajaba en el binario y cualquiera
   podía sacarlo descomprimiendo el `.ipa`. Aquí vive solo en el servidor.
2. **La clave de Anthropic.** Antes la ponía cada usuario, de modo que no se podía
   cobrar por el servicio ni controlar el gasto. Ahora la custodia el servidor y se
   reparte con cuotas.

## Decisión central: el servidor es dueño de los prompts

El cliente **no** manda un prompt. Manda un `kind` de un catálogo cerrado
(`src/services/catalog.ts`) más los datos ya calculados; el servidor elige el
prompt, el modelo y el tope de tokens.

Sin esto, el proxy sería una API de Claude de uso general protegida por un token de
dispositivo: quien lo extrajera del móvil podría gastar la clave en cualquier cosa.
Con el catálogo, lo peor que puede hacer es pedir análisis deportivos hasta agotar
su cuota.

Como efecto secundario, los prompts se corrigen desplegando el servidor, sin
publicar una versión nueva de la app.

## Endpoints

| Método | Ruta | Auth | Qué hace |
|---|---|---|---|
| `GET` | `/v1/health` | — | Comprobación de vida |
| `POST` | `/v1/devices/register` | — | Registra el dispositivo y devuelve su token |
| `POST` | `/v1/ai/analyze` | Bearer | Ejecuta un análisis del catálogo |
| `GET` | `/v1/ai/quota` | Bearer | Cuotas restantes, sin gastar nada |
| `POST` | `/v1/strava/exchange` | Bearer | Canjea el `code` de OAuth |
| `POST` | `/v1/strava/refresh` | Bearer | Refresca el token de Strava |

## Cuotas

Los topes se agrupan por lo que cuesta cada llamada, no por análisis.

| | Gratis | Pro |
|---|---|---|
| Análisis diarios (Sonnet, cupo compartido) | 20/día | 100/día |
| Rutina completa (Opus, 8.000 tokens) | 1/mes | 4/mes |
| Cambio de ejercicio (Opus) | 5/mes | 30/mes |

La app lleva su propio contador, pero es solo de interfaz: el cliente es
manipulable y estos límites son la autoridad real. Se consumen **después** de que
la llamada salga bien, para que un fallo de la API no gaste cuota del usuario.

## Coste medido, no estimado

`ai_calls` guarda una fila por llamada con los tokens que informa la propia API.
Antes el coste por usuario era una estimación sacada de leer el código y suponer
el tamaño de los prompts; ahora es un dato. Es lo que permite decidir si el precio
de la suscripción se sostiene.

```sql
-- Coste real por dispositivo en el mes en curso, en dólares
SELECT device_id, SUM(cost_micros) / 1000000.0 AS dolares, COUNT(*) AS llamadas
FROM ai_calls
WHERE created_at >= date_trunc('month', now())
GROUP BY device_id
ORDER BY dolares DESC;
```

## Límite conocido de la autenticación

No hay cuentas: el dispositivo se registra y guarda un token en el Keychain. Para
saber a quién cobrarle la cuota es suficiente, pero **nada impide registrar
dispositivos nuevos en bucle para renovarla**. Lo que acota el gasto son los topes,
no la identidad.

Cerrarlo de verdad requiere **App Attest**, que exige cuenta de desarrollador de
pago. Queda como trabajo futuro y está declarado también en la memoria del TFM:
más vale un límite reconocido que uno escondido.

## Desarrollo

```bash
npm install
cp .env.example .env     # y rellenar
npm run dev              # tsx watch en :3000
npm test                 # 43 tests
```

Los tests no necesitan Postgres instalado: usan **PGlite**, que es Postgres
compilado a WASM y corre en el propio proceso. Así el SQL de las cuotas —un UPSERT
con clave primaria compuesta— se comprueba contra el motor de verdad y no contra
un doble.

## Despliegue en Railway

1. Nuevo proyecto → añadir **PostgreSQL** (inyecta `DATABASE_URL` solo).
2. Añadir el servicio desde este repositorio, con la raíz en `backend/`.
3. Poner las variables de `.env.example` en Settings → Variables.
4. **Ponerle límite de gasto al proyecto**: la facturación es por uso.

`railway.json` ya declara el build, el arranque (que migra antes) y el healthcheck
contra `/v1/health`.

## Estructura

```
src/
├── config.ts              Variables de entorno, validadas al arrancar
├── server.ts              Fastify, hook de autenticación
├── index.ts               Arranque y cierre ordenado
├── db/
│   ├── schema.ts          Tablas (Drizzle)
│   ├── index.ts           Conexión
│   └── migrate.ts         Migraciones, se ejecutan al desplegar
├── routes/
│   ├── devices.ts         Registro
│   ├── ai.ts              Análisis y cuota
│   └── strava.ts          Proxy del OAuth
└── services/
    ├── catalog.ts         Catálogo cerrado de análisis y precios
    ├── quotas.ts          Topes por dispositivo
    └── auth.ts            Tokens de dispositivo
```
