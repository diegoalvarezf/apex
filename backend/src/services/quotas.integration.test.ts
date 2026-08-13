import { describe, it, expect, beforeEach, vi } from "vitest";

// Las cuotas se apoyan en un UPSERT con clave primaria compuesta, y eso no se
// puede comprobar con lógica pura: hay que ejecutarlo contra Postgres. PGlite lo
// hace en el propio proceso (Postgres compilado a WASM), así que estos tests
// corren sin instalar ni levantar nada.
//
// Se sustituye el módulo de base de datos, no las funciones de cuota: lo que se
// quiere verificar es precisamente el SQL que generan.

const { testDb } = vi.hoisted(() => {
  return { testDb: { current: null as unknown } };
});

vi.mock("../db/index.js", () => ({
  get db() {
    return testDb.current;
  },
}));

const { drizzle } = await import("drizzle-orm/pglite");
const { PGlite } = await import("@electric-sql/pglite");
const schema = await import("../db/schema.js");
const { checkQuota, consumeQuota, FREE, PRO } = await import("./quotas.js");

const DDL = `
  CREATE TABLE IF NOT EXISTS usage_daily (
    device_id TEXT NOT NULL,
    day TEXT NOT NULL,
    kind TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, day, kind)
  );
  CREATE TABLE IF NOT EXISTS usage_monthly (
    device_id TEXT NOT NULL,
    month TEXT NOT NULL,
    kind TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, month, kind)
  );
`;

beforeEach(async () => {
  const client = await PGlite.create();
  await client.exec(DDL);
  testDb.current = drizzle(client, { schema });
});

const DEVICE = "dispositivo-de-prueba";

describe("cuota diaria", () => {
  it("empieza entera y va bajando", async () => {
    const inicial = await checkQuota(DEVICE, "alerts", false);
    expect(inicial.remaining).toBe(FREE.dailyStandard);
    expect(inicial.allowed).toBe(true);

    await consumeQuota(DEVICE, "alerts");

    const despues = await checkQuota(DEVICE, "alerts", false);
    expect(despues.used).toBe(1);
    expect(despues.remaining).toBe(FREE.dailyStandard - 1);
  });

  // Los análisis baratos comparten cupo. Si cada uno tuviera el suyo, el gasto
  // real sería el número de tipos multiplicado por el tope, no el tope.
  it("todos los análisis baratos comparten el mismo cupo", async () => {
    await consumeQuota(DEVICE, "alerts");
    await consumeQuota(DEVICE, "sleep");
    await consumeQuota(DEVICE, "stress");

    // Consumidos con tres tipos distintos, pero cuentan contra el mismo total.
    const estado = await checkQuota(DEVICE, "recovery", false);
    expect(estado.used).toBe(3);
  });

  it("al llegar al tope deja de permitir", async () => {
    for (let i = 0; i < FREE.dailyStandard; i++) {
      await consumeQuota(DEVICE, "alerts");
    }
    const estado = await checkQuota(DEVICE, "alerts", false);
    expect(estado.allowed).toBe(false);
    expect(estado.remaining).toBe(0);
  });

  it("cada dispositivo tiene la suya", async () => {
    await consumeQuota("dispositivo-a", "alerts");

    const otro = await checkQuota("dispositivo-b", "alerts", false);
    expect(otro.used).toBe(0);
  });
});

describe("cuota mensual", () => {
  // Lo caro va aparte y por tipo: gastar los cambios de ejercicio no debe dejar
  // sin rutinas, y al revés.
  it("rutinas y cambios no comparten cupo", async () => {
    await consumeQuota(DEVICE, "exerciseSwap");

    const rutinas = await checkQuota(DEVICE, "routineCreate", false);
    expect(rutinas.used).toBe(0);
    expect(rutinas.remaining).toBe(FREE.monthlyRoutine);
  });

  it("un usuario gratis agota su rutina con una sola", async () => {
    await consumeQuota(DEVICE, "routineCreate");

    const estado = await checkQuota(DEVICE, "routineCreate", false);
    expect(estado.allowed).toBe(false);
  });

  // El mismo consumo, con el plan de pago, sigue permitiendo.
  it("el plan Pro amplía el tope sobre el mismo consumo", async () => {
    await consumeQuota(DEVICE, "routineCreate");

    const pro = await checkQuota(DEVICE, "routineCreate", true);
    expect(pro.allowed).toBe(true);
    expect(pro.limit).toBe(PRO.monthlyRoutine);
    expect(pro.remaining).toBe(PRO.monthlyRoutine - 1);
  });

  it("lo mensual no se mezcla con lo diario", async () => {
    for (let i = 0; i < FREE.dailyStandard; i++) {
      await consumeQuota(DEVICE, "alerts");
    }
    // Agotado lo diario, la rutina sigue disponible.
    const rutina = await checkQuota(DEVICE, "routineCreate", false);
    expect(rutina.allowed).toBe(true);
  });
});
