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
    pro_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    registration_ip_hash TEXT);
  CREATE TABLE IF NOT EXISTS pro_codes (
    code TEXT PRIMARY KEY, issued_to TEXT, max_redemptions INTEGER,
    expires_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
  CREATE TABLE IF NOT EXISTS pro_redemptions (
    code TEXT NOT NULL, device_id TEXT NOT NULL,
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(code, device_id));
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

  // Sin esto no se puede saber desde fuera qué versión está desplegada, y un build
  // fallido deja el anterior en pie sin que se note.
  it("dice qué commit está corriendo", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/health" });
    expect(res.json().commit).toBeTruthy();
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

describe("Apex Pro por código", () => {
  async function emitir(code: string, expiresAt: Date | null = null, maxRedemptions: number | null = 1) {
    await (testDb.current as any).insert(schema.proCodes).values({
      code, issuedTo: "test", expiresAt, maxRedemptions,
    });
  }

  it("un código válido activa Pro y amplía la cuota", async () => {
    await emitir("ABCD2345EFGH");
    const token = await registrar();
    const auth = { authorization: `Bearer ${token}` };

    const antes = await app.inject({ method: "GET", url: "/v1/ai/quota", headers: auth });
    expect(antes.json().routine.remaining).toBe(1);

    const canje = await app.inject({
      method: "POST", url: "/v1/pro/redeem", headers: auth,
      payload: { code: "ABCD-2345-EFGH" },
    });
    expect(canje.statusCode).toBe(200);
    expect(canje.json().isPro).toBe(true);

    // Lo que importa: el plan cambia de verdad lo que puede hacer.
    const despues = await app.inject({ method: "GET", url: "/v1/ai/quota", headers: auth });
    expect(despues.json().isPro).toBe(true);
    expect(despues.json().routine.remaining).toBe(4);
  });

  // Se teclea a mano: minúsculas y sin guiones tienen que valer igual.
  it("acepta el código escrito de cualquier forma", async () => {
    await emitir("WXYZ6789MNPQ");
    const token = await registrar();
    const res = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${token}` },
      payload: { code: "  wxyz6789mnpq " },
    });
    expect(res.statusCode).toBe(200);
  });

  it("un código inventado no vale", async () => {
    const token = await registrar();
    const res = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${token}` },
      payload: { code: "NOEX-ISTE-AQUI" },
    });
    expect(res.statusCode).toBe(404);
  });

  // Es de un solo uso: si no, uno filtrado daría Pro a todo el mundo.
  it("no se puede canjear dos veces desde dispositivos distintos", async () => {
    await emitir("SOLO2345UNAV");
    const primero = await registrar();
    const segundo = await registrar();

    const a = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${primero}` }, payload: { code: "SOLO2345UNAV" },
    });
    expect(a.statusCode).toBe(200);

    const b = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${segundo}` }, payload: { code: "SOLO2345UNAV" },
    });
    expect(b.statusCode).toBe(409);
  });

  // Reinstalar la app o repetir el gesto no debería castigarse.
  it("el mismo dispositivo puede repetir su canje", async () => {
    await emitir("REPE2345TIRR");
    const token = await registrar();
    const auth = { authorization: `Bearer ${token}` };

    expect((await app.inject({ method: "POST", url: "/v1/pro/redeem", headers: auth, payload: { code: "REPE2345TIRR" } })).statusCode).toBe(200);
    expect((await app.inject({ method: "POST", url: "/v1/pro/redeem", headers: auth, payload: { code: "REPE2345TIRR" } })).statusCode).toBe(200);
  });

  // Un código caducado no debe seguir dando cuota ampliada.
  it("un código ya caducado no concede Pro vigente", async () => {
    await emitir("CADU2345CADO", new Date(Date.now() - 86_400_000));
    const token = await registrar();
    const auth = { authorization: `Bearer ${token}` };

    await app.inject({ method: "POST", url: "/v1/pro/redeem", headers: auth, payload: { code: "CADU2345CADO" } });

    const estado = await app.inject({ method: "GET", url: "/v1/pro/status", headers: auth });
    expect(estado.json().isPro).toBe(false);

    // Y la cuota sigue siendo la del plan gratis.
    const cuota = await app.inject({ method: "GET", url: "/v1/ai/quota", headers: auth });
    expect(cuota.json().routine.remaining).toBe(1);
  });

  // Un código para el tribunal: se reparte entre varios y todos tienen Pro.
  it("un código de varios usos vale para varios dispositivos", async () => {
    await emitir("TRIB2345UNAL", null, 3);
    for (const _ of [1, 2, 3]) {
      const token = await registrar();
      const res = await app.inject({
        method: "POST", url: "/v1/pro/redeem",
        headers: { authorization: `Bearer ${token}` }, payload: { code: "TRIB2345UNAL" },
      });
      expect(res.statusCode).toBe(200);
    }

    // Pero no para uno más: el tope se respeta.
    const cuarto = await registrar();
    const res = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${cuarto}` }, payload: { code: "TRIB2345UNAL" },
    });
    expect(res.statusCode).toBe(409);
  });

  // Repetir no debe gastar un uso ajeno: si lo gastara, reinstalar la app dejaría
  // sin sitio a otra persona del tribunal.
  it("repetir el canje no consume otro uso", async () => {
    await emitir("REUS2345ARLO", null, 2);
    const primero = await registrar();
    const auth = { authorization: `Bearer ${primero}` };

    for (const _ of [1, 2, 3]) {
      await app.inject({ method: "POST", url: "/v1/pro/redeem", headers: auth, payload: { code: "REUS2345ARLO" } });
    }

    const segundo = await registrar();
    const res = await app.inject({
      method: "POST", url: "/v1/pro/redeem",
      headers: { authorization: `Bearer ${segundo}` }, payload: { code: "REUS2345ARLO" },
    });
    expect(res.statusCode).toBe(200);
  });

  it("sin tope, un código vale para todos los que hagan falta", async () => {
    await emitir("SINT2345OPES", null, null);
    for (const _ of [1, 2, 3, 4, 5]) {
      const token = await registrar();
      const res = await app.inject({
        method: "POST", url: "/v1/pro/redeem",
        headers: { authorization: `Bearer ${token}` }, payload: { code: "SINT2345OPES" },
      });
      expect(res.statusCode).toBe(200);
    }
  });

  it("canjear exige estar autenticado", async () => {
    const res = await app.inject({
      method: "POST", url: "/v1/pro/redeem", payload: { code: "ABCD2345EFGH" },
    });
    expect(res.statusCode).toBe(401);
  });

  // Rotar el código compartido es la vuelta atrás que permite repartirlo: si acaba
  // donde no debía, se corta sin dañar a quien tiene Pro por su propio código.
  describe("rotación de un código", () => {
    async function canjearCon(token: string, code: string) {
      return app.inject({
        method: "POST", url: "/v1/pro/redeem",
        headers: { authorization: `Bearer ${token}` }, payload: { code },
      });
    }

    async function esPro(token: string) {
      const res = await app.inject({
        method: "GET", url: "/v1/pro/status", headers: { authorization: `Bearer ${token}` },
      });
      return res.json().isPro as boolean;
    }

    it("quien entró por él pierde Pro y el código deja de servir", async () => {
      const { revocar } = await import("./services/pro.js");
      await emitir("COMP2345ARTE", null, null);
      const token = await registrar();
      await canjearCon(token, "COMP2345ARTE");
      expect(await esPro(token)).toBe(true);

      const resultado = await revocar("COMP2345ARTE");
      expect(resultado.existia).toBe(true);
      expect(resultado.dispositivos).toBe(1);

      expect(await esPro(token)).toBe(false);
      expect((await canjearCon(await registrar(), "COMP2345ARTE")).statusCode).toBe(404);
    });

    // El caso que justifica tener dos códigos: rotar el compartido no puede
    // costarle el Pro a quien además tiene el suyo.
    it("no toca a quien tiene otro código propio", async () => {
      const { revocar } = await import("./services/pro.js");
      await emitir("MIOP2345ROPI", null, 1);
      await emitir("COMP6789ARTE", null, null);

      const token = await registrar();
      await canjearCon(token, "MIOP2345ROPI");
      await canjearCon(token, "COMP6789ARTE");

      await revocar("COMP6789ARTE");
      expect(await esPro(token)).toBe(true);
    });

    it("revocar algo que no existe se nota", async () => {
      const { revocar } = await import("./services/pro.js");
      expect((await revocar("NOEX2345ISTE")).existia).toBe(false);
    });
  });
});
