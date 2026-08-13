import type { FastifyInstance } from "fastify";
import { registerDevice } from "../services/auth.js";

export function registerDeviceRoutes(app: FastifyInstance): void {
  // Sin autenticar: es el punto de entrada de una app recién instalada.
  app.post<{ Body: { platform?: string } }>("/v1/devices/register", async (request, reply) => {
    const platform = request.body?.platform === "watchos" ? "watchos" : "ios";
    const { deviceId, token } = await registerDevice(platform);

    // El token se devuelve aquí y nunca más: la base de datos solo guarda su hash.
    return reply.code(201).send({ deviceId, token });
  });
}
