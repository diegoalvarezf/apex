import type { FastifyInstance } from "fastify";
import { canjear, esProVigente, normalizar } from "../services/pro.js";
import { notificarCanje } from "../services/notify.js";

export function registerProRoutes(app: FastifyInstance): void {
  // Canjear un código de Apex Pro.
  app.post<{ Body: { code?: string } }>("/v1/pro/redeem", async (request, reply) => {
    const device = request.device!;
    const code = request.body?.code;

    if (typeof code !== "string" || code.trim() === "") {
      return reply.code(400).send({ error: "missing_code" });
    }

    const resultado = await canjear(code, device.id);

    if (!resultado.ok) {
      if (resultado.motivo === "demasiados_intentos") {
        request.log.warn({ deviceId: device.id }, "canje bloqueado por exceso de intentos");
        return reply.code(429).send({ error: "too_many_attempts" });
      }
      // 404 y 409 se distinguen a propósito: "ese código no existe" y "ese código
      // ya lo usó otro" son problemas distintos para quien lo teclea.
      return resultado.motivo === "no_existe"
        ? reply.code(404).send({ error: "invalid_code" })
        : reply.code(409).send({ error: "code_already_used" });
    }

    request.log.info({ deviceId: device.id }, "Apex Pro activado con código");

    // Solo en el canje NUEVO: reinstalar la app o repetir el gesto no debe
    // mandar un correo cada vez. No se espera (`await`) porque un aviso lento o
    // caído no puede retrasar ni tumbar la respuesta al usuario.
    if (resultado.nuevo) {
      void notificarCanje(
        { code: normalizar(code), issuedTo: resultado.issuedTo, deviceId: device.id, platform: device.platform },
        request.log,
      );
    }

    return reply.send({ isPro: true, expiresAt: resultado.expiresAt });
  });

  // Estado de la suscripción.
  app.get("/v1/pro/status", async (request, reply) => {
    const device = request.device!;
    return reply.send({
      isPro: esProVigente(device),
      expiresAt: device.proUntil,
    });
  });
}
