import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { config } from "../config.js";

// Se ejecuta antes de arrancar en cada despliegue. Conexión propia con `max: 1` y
// cerrada al terminar: si se reutilizara el pool del servidor, quedaría abierto y
// el proceso no saldría.
const client = postgres(config.databaseUrl, { max: 1 });

try {
  await migrate(drizzle(client), { migrationsFolder: "./drizzle" });
  console.log("Migraciones aplicadas");
} catch (err) {
  console.error("Fallo al migrar:", err);
  process.exit(1);
} finally {
  await client.end();
}
