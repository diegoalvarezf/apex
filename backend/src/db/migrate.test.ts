import { describe, it, expect } from "vitest";
import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";

// Las migraciones se aplican al arrancar cada despliegue, antes de que el servidor
// escuche. Si fallan, el contenedor no llega a levantar y se queda en pie la
// versión anterior: un fallo silencioso desde fuera.
//
// Ningún otro test las tocaba —los de integración crean las tablas con DDL a mano,
// para ser rápidos— así que el camino que de verdad corre en producción era el
// único sin cubrir. Se notó al actualizar Drizzle por un aviso de seguridad: el
// build y los 96 tests pasaban, y aun así nada garantizaba que el arranque fuera a
// sobrevivir a la nueva versión.
describe("migraciones sobre una base de datos limpia", () => {
  it("crean el esquema entero", async () => {
    const client = await PGlite.create();
    await migrate(drizzle(client), { migrationsFolder: "./drizzle" });

    const res = await client.query<{ table_name: string }>(
      `select table_name from information_schema.tables
       where table_schema = 'public' order by table_name`,
    );
    const tablas = res.rows.map((r) => r.table_name);

    expect(tablas).toEqual(
      expect.arrayContaining([
        "ai_calls", "devices", "pro_codes", "pro_redemptions", "usage_daily", "usage_monthly",
      ]),
    );
  });

  // Cada despliegue las vuelve a ejecutar sobre una base que ya está migrada: si no
  // fueran idempotentes, el segundo arranque reventaría.
  it("se pueden aplicar dos veces seguidas", async () => {
    const client = await PGlite.create();
    const db = drizzle(client);
    await migrate(db, { migrationsFolder: "./drizzle" });
    await expect(migrate(db, { migrationsFolder: "./drizzle" })).resolves.not.toThrow();
  });
});
