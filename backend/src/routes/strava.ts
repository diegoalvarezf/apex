import type { FastifyInstance } from "fastify";
import { config } from "../config.js";

// Proxy del OAuth de Strava.
//
// Es la razón original de que exista este servidor. El flujo de Strava exige el
// `client_secret` para canjear y refrescar tokens, y no admite PKCE, así que en la
// app estaba condenado a viajar dentro del binario: cualquiera podía sacarlo
// descomprimiendo el .ipa. Aquí vive solo en el servidor.
//
// El servidor NO guarda los tokens de Strava del usuario: los devuelve y los
// custodia la app en su Keychain. Así este servicio no se convierte en un
// depósito de credenciales de terceros, que sería mucho más goloso de atacar.

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

interface ExchangeBody {
  code?: string;
}

interface RefreshBody {
  refreshToken?: string;
}

export function registerStravaRoutes(app: FastifyInstance): void {
  app.post<{ Body: ExchangeBody }>("/v1/strava/exchange", async (request, reply) => {
    const code = request.body?.code;
    if (!code) return reply.code(400).send({ error: "missing_code" });

    return forward(reply, request.log, {
      client_id: config.strava.clientId,
      client_secret: config.strava.clientSecret,
      code,
      grant_type: "authorization_code",
    });
  });

  app.post<{ Body: RefreshBody }>("/v1/strava/refresh", async (request, reply) => {
    const refreshToken = request.body?.refreshToken;
    if (!refreshToken) return reply.code(400).send({ error: "missing_refresh_token" });

    return forward(reply, request.log, {
      client_id: config.strava.clientId,
      client_secret: config.strava.clientSecret,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    });
  });
}

type Reply = { code: (n: number) => Reply; send: (body: unknown) => unknown };
type Logger = { error: (obj: unknown, msg: string) => void };

async function forward(reply: Reply, log: Logger, params: Record<string, string>) {
  let response: Response;
  try {
    response = await fetch(STRAVA_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });
  } catch (err) {
    log.error({ err }, "no se ha podido contactar con Strava");
    return reply.code(502).send({ error: "strava_unreachable" });
  }

  const body = (await response.json().catch(() => null)) as Record<string, unknown> | null;

  if (!response.ok || !body) {
    // Se devuelve el estado pero no el cuerpo de Strava: podría incluir de vuelta
    // parte de lo enviado, y ahí va el secreto.
    log.error({ status: response.status }, "Strava rechazó el canje");
    return reply.code(response.status === 400 ? 400 : 502).send({ error: "strava_rejected" });
  }

  // Se pasa a la app solo lo que necesita, no la respuesta entera.
  return reply.send({
    accessToken: body.access_token,
    refreshToken: body.refresh_token,
    expiresAt: body.expires_at,
    athlete: body.athlete ?? null,
  });
}
