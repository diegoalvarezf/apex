import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { config } from "../config.js";
import * as schema from "./schema.js";

// Una sola conexión para todo el proceso. `max: 5` porque Railway limita las
// conexiones del Postgres compartido y este servicio no necesita más: las
// peticiones pasan casi todo su tiempo esperando a la API de Anthropic, no a la
// base de datos.
const client = postgres(config.databaseUrl, {
  max: 5,
  idle_timeout: 20,
  connect_timeout: 10,
});

export const db = drizzle(client, { schema });
export { schema };
