import { describe, it, expect, beforeEach, vi } from "vitest";

// Prueba la superficie HTTP completa —enrutado, autenticación, validación y
// cuotas— contra Postgres de verdad (PGlite, en el propio proceso).
//
// Se cubre todo menos la llamada a Anthropic: los casos que se comprueban aquí
// son justo los que deben cortarse ANTES de gastar un token, que es lo que
// protege la clave del servidor.

const { testDb } = vi.hoisted(() => ({ testDb: { current: null as unknown } }));

vi.mock("./db/index.js", () => ({
  get db() {
    return testDb.current;
  },
}));

const { drizzle } = await import("drizzle-orm/pglite");
const { PGlite } = await import("@electric-sql/pglite");
const schema = await import("./db/schema.js");
const { buildServer } = await import("./server.js");

const DDL = `
  CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY, token_hash TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios', is_pro BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now());
  CREATE TABLE IF NOT EXISTS usage_daily (
    device_id TEXT, day TEXT, kind TEXT, count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(device_id, day, kind));
  CREATE TABLE IF NOT EXISTS usage_monthly (
    device_id TEXT, month TEXT, kind TEXT, count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(device_id, month, kind));
  CREATE TABLE IF NOT EXISTS ai_calls (
    id TEXT PRIMARY KEY, device_id TEXT, kind TEXT, model TEXT,
    input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_micros INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
`;

let app: ReturnType<typeof buildServer>;

beforeEach(async () => {
  const client = await PGlite.create();
  await client.exec(DDL);
  testDb.current = drizzle(client, { schema });
  app = buildServer();
  await app.ready();
});

async function registrar(): Promise<string> {
  const res = await app.inject({
    method: "POST",
    url: "/v1/devices/register",
    payload: { platform: "ios" },
  });
  return res.json().token as string;
}

describe("salud", () => {
  it("responde sin autenticación", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json().status).toBe("ok");
  });
});

describe("registro de dispositivo", () => {
  it("devuelve un token una sola vez", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/devices/register",
      payload: { platform: "ios" },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.token).toBeTruthy();
    expect(body.deviceId).toBeTruthy();
  });

  it("cada registro da un token distinto", async () => {
    expect(await registrar()).not.toBe(await registrar());
  });
});

describe("autenticación", () => {
  it("sin token no se puede analizar", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/ai/analyze",
      payload: { kind: "alerts", input: "hola" },
    });
    expect(res.statusCode).toBe(401);
  });

  // El caso que importa: un token inventado no vale. Si esto fallara, la clave
  // del servidor quedaría abierta a cualquiera.
  it("un token inventado no vale", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/ai/analyze",
      headers: { authorization: "Bearer me-lo-acabo-de-inventar" },
      payload: { kind: "alerts", input: "hola" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("el registro y la salud no piden token", async () => {
    expect((await app.inject({ method: "GET", url: "/v1/health" })).statusCode).toBe(200);
    expect(
      (await app.inject({ method: "POST", url: "/v1/devices/register", payload: {} })).statusCode,
    ).toBe(201);
  });
});

describe("validación de la petición", () => {
  // La barrera que impide que el proxy sea una API de Claude de uso general.
  it("rechaza un tipo que no está en el catálogo", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "POST",
      url: "/v1/ai/analyze",
      headers: { authorization: `Bearer ${token}` },
      payload: { kind: "escribeme-una-novela", input: "hola" },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe("unknown_kind");
  });

  // Sin esto, `hasOwnProperty` sobre un objeto plano dejaría pasar las propiedades
  // heredadas de Object y el catálogo tendría un agujero.
  it("no se cuela por propiedades heredadas", async () => {
    const token = await registrar();
    for (const kind of ["__proto__", "constructor", "toString"]) {
      const res = await app.inject({
        method: "POST",
        url: "/v1/ai/analyze",
        headers: { authorization: `Bearer ${token}` },
        payload: { kind, input: "hola" },
      });
      expect(res.statusCode, `${kind} debería rechazarse`).toBe(400);
    }
  });

  it("exige texto de entrada", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "POST",
      url: "/v1/ai/analyze",
      headers: { authorization: `Bearer ${token}` },
      payload: { kind: "alerts" },
    });
    expect(res.statusCode).toBe(400);
  });

  // Acota el coste de entrada: nadie puede inflar la factura mandando relleno.
  it("rechaza una entrada desproporcionada", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "POST",
      url: "/v1/ai/analyze",
      headers: { authorization: `Bearer ${token}` },
      payload: { kind: "alerts", input: "x".repeat(70_000) },
    });
    expect(res.statusCode).toBe(413);
  });
});

describe("consulta de cuota", () => {
  it("un dispositivo nuevo empieza en el plan gratis", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "GET",
      url: "/v1/ai/quota",
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.isPro).toBe(false);
    expect(body.routine.remaining).toBe(1);
    expect(body.standard.remaining).toBe(20);
  });
});

describe("proxy de Strava", () => {
  it("pide el código para canjear", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "POST",
      url: "/v1/strava/exchange",
      headers: { authorization: `Bearer ${token}` },
      payload: {},
    });
    expect(res.statusCode).toBe(400);
  });

  it("también va autenticado", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/v1/strava/refresh",
      payload: { refreshToken: "x" },
    });
    expect(res.statusCode).toBe(401);
  });
});
