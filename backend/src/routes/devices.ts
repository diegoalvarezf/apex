import type { FastifyInstance } from "fastify";
import { registerDevice, DemasiadosRegistros } from "../services/auth.js";

export function registerDeviceRoutes(app: FastifyInstance): void {
  // Sin autenticar: es el punto de entrada de una app recién instalada.
  app.post<{ Body: { platform?: string } }>("/v1/devices/register", async (request, reply) => {
    const platform = request.body?.platform === "watchos" ? "watchos" : "ios";

    try {
      const { deviceId, token } = await registerDevice(platform, request.ip);
      // El token se devuelve aquí y nunca más: la base de datos solo guarda su hash.
      return reply.code(201).send({ deviceId, token });
    } catch (err) {
      if (err instanceof DemasiadosRegistros) {
        request.log.warn("registro rechazado por exceso desde un mismo origen");
        return reply.code(429).send({ error: "too_many_registrations" });
      }
      throw err;
    }
  });
}
