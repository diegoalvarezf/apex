import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { config } from "./config.js";
import { bearerToken, deviceForToken } from "./services/auth.js";
import type { Device } from "./db/schema.js";
import { registerDeviceRoutes } from "./routes/devices.js";
import { registerAIRoutes } from "./routes/ai.js";
import { registerStravaRoutes } from "./routes/strava.js";

declare module "fastify" {
  interface FastifyRequest {
    device?: Device;
  }
}

export function buildServer(): FastifyInstance {
  const app = Fastify({
    logger: {
      level: config.isProduction ? "info" : "debug",
      // Nunca registrar cabeceras: ahí viaja el token del dispositivo, y unos logs
      // con tokens dentro son tan explotables como una base de datos filtrada.
      redact: ["req.headers.authorization"],
    },
    // La generación de rutina con el modelo grande puede tardar cerca de un
    // minuto. Con el valor por defecto, Fastify cortaría la petición antes de que
    // Anthropic respondiera.
    requestTimeout: 120_000,
    bodyLimit: 1_048_576, // 1 MB: el contexto más grande no llega ni de lejos
  });

  app.get("/v1/health", async () => ({
    status: "ok",
    time: new Date().toISOString(),
  }));

  registerDeviceRoutes(app);

  // Todo lo que gasta dinero va autenticado. Se registra dentro de un contexto
  // aparte para que el hook no alcance a /health ni al propio registro.
  app.register(async (protectedRoutes) => {
    protectedRoutes.addHook("preHandler", requireDevice);
    registerAIRoutes(protectedRoutes);
    registerStravaRoutes(protectedRoutes);
  });

  return app;
}

async function requireDevice(request: FastifyRequest, reply: { code: (n: number) => { send: (b: unknown) => unknown } }) {
  const token = bearerToken(request.headers.authorization);
  if (!token) {
    return reply.code(401).send({ error: "missing_token" });
  }

  const device = await deviceForToken(token);
  if (!device) {
    return reply.code(401).send({ error: "invalid_token" });
  }

  request.device = device;
}
