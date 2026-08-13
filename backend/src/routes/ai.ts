import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import Anthropic from "@anthropic-ai/sdk";
import { config } from "../config.js";
import { db } from "../db/index.js";
import { aiCalls } from "../db/schema.js";
import { CATALOG, isKnownKind, costMicros } from "../services/catalog.js";
import { checkQuota, consumeQuota } from "../services/quotas.js";

const anthropic = new Anthropic({ apiKey: config.anthropicApiKey });

// Tope del texto que manda el cliente. El contexto más grande —una rutina con su
// historial— se queda muy por debajo; el límite existe para que nadie pueda
// inflar el coste de entrada mandando megas de relleno.
const MAX_INPUT_CHARS = 60_000;

interface AnalyzeBody {
  kind?: string;
  input?: string;
}

export function registerAIRoutes(app: FastifyInstance): void {
  app.post<{ Body: AnalyzeBody }>("/v1/ai/analyze", async (request, reply) => {
    const device = request.device!;
    const { kind, input } = request.body ?? {};

    // El cliente elige de un catálogo cerrado; el prompt lo pone el servidor.
    // Cualquier otra cosa se rechaza antes de gastar un solo token.
    if (!kind || !isKnownKind(kind)) {
      return reply.code(400).send({ error: "unknown_kind" });
    }
    if (typeof input !== "string" || input.trim() === "") {
      return reply.code(400).send({ error: "missing_input" });
    }
    if (input.length > MAX_INPUT_CHARS) {
      return reply.code(413).send({ error: "input_too_large", maxChars: MAX_INPUT_CHARS });
    }

    const spec = CATALOG[kind];

    const quota = await checkQuota(device.id, kind, device.isPro);
    if (!quota.allowed) {
      return reply.code(429).send({
        error: "quota_exceeded",
        kind,
        used: quota.used,
        limit: quota.limit,
        resetsAt: quota.resetsAt,
        isPro: device.isPro,
      });
    }

    let response;
    try {
      response = await anthropic.messages.create({
        model: spec.model,
        max_tokens: spec.maxTokens,
        system: spec.system,
        messages: [{ role: "user", content: input }],
      });
    } catch (err) {
      request.log.error({ err, kind }, "fallo al llamar a Anthropic");
      // No se consume cuota: el usuario no ha recibido nada.
      return reply.code(502).send({ error: "upstream_failed" });
    }

    const text = response.content
      .filter((b): b is Anthropic.TextBlock => b.type === "text")
      .map((b) => b.text)
      .join("");

    // Se registra el consumo REAL que informa la API, no una estimación. Es lo que
    // permite saber cuánto cuesta de verdad un usuario y si el precio se sostiene.
    const inputTokens = response.usage.input_tokens;
    const outputTokens = response.usage.output_tokens;

    await Promise.all([
      consumeQuota(device.id, kind),
      db.insert(aiCalls).values({
        id: randomUUID(),
        deviceId: device.id,
        kind,
        model: spec.model,
        inputTokens,
        outputTokens,
        costMicros: costMicros(spec.model, inputTokens, outputTokens),
      }),
    ]);

    const after = await checkQuota(device.id, kind, device.isPro);

    return reply.send({
      text,
      usage: { inputTokens, outputTokens },
      quota: { remaining: after.remaining, limit: after.limit, resetsAt: after.resetsAt },
    });
  });

  // Cuotas restantes sin gastar nada: la app la usa para enseñar "te quedan N
  // rutinas" antes de que el usuario pulse el botón.
  app.get("/v1/ai/quota", async (request, reply) => {
    const device = request.device!;
    const [standard, routine, swap] = await Promise.all([
      checkQuota(device.id, "alerts", device.isPro),
      checkQuota(device.id, "routineCreate", device.isPro),
      checkQuota(device.id, "exerciseSwap", device.isPro),
    ]);

    return reply.send({
      isPro: device.isPro,
      standard: { remaining: standard.remaining, limit: standard.limit, resetsAt: standard.resetsAt },
      routine: { remaining: routine.remaining, limit: routine.limit, resetsAt: routine.resetsAt },
      swap: { remaining: swap.remaining, limit: swap.limit, resetsAt: swap.resetsAt },
    });
  });
}
