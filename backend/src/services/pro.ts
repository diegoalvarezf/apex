import { randomBytes } from "node:crypto";
import { eq, and, count, isNull } from "drizzle-orm";
import { db } from "../db/index.js";
import { devices, proCodes, proRedemptions } from "../db/schema.js";

// Apex Pro.
//
// La suscripción de verdad pasa por In-App Purchase, y eso exige cuenta de
// desarrollador de pago. Mientras no la haya, Pro se concede canjeando un código:
// permite usar el plan de verdad y que el tribunal lo pruebe, sin simular una
// compra inexistente. Cuando llegue el IAP, la validación del recibo llamará a la
// misma función que concede Pro y el resto no cambia.

// Alfabeto sin caracteres que se confunden al leer o dictar un código: nada de
// 0/O ni 1/I/L. Los códigos se van a teclear a mano.
const ALFABETO = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const LONGITUD = 12; // en tres grupos de cuatro

export function generarCodigo(): string {
  const bytes = randomBytes(LONGITUD);
  let salida = "";
  for (let i = 0; i < LONGITUD; i++) {
    salida += ALFABETO[bytes[i]! % ALFABETO.length];
    if (i % 4 === 3 && i < LONGITUD - 1) salida += "-";
  }
  return salida; // XXXX-XXXX-XXXX
}

// Se normaliza antes de comparar: quien lo teclea puede poner minúsculas, olvidar
// los guiones o colar un espacio, y nada de eso debería hacer fallar un canje.
export function normalizar(code: string): string {
  return code.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export type ResultadoCanje =
  | { ok: true; expiresAt: Date | null }
  | { ok: false; motivo: "no_existe" | "ya_usado" };

export async function canjear(code: string, deviceId: string): Promise<ResultadoCanje> {
  const normalizado = normalizar(code);

  // Todo va en una transacción con el código bloqueado (`for update`): entre
  // contar los canjes y apuntar el nuevo cabe otro canje simultáneo, y sin el
  // bloqueo un código de N usos podría gastarse N+1 veces. Que lo resuelva la
  // base de datos y no un `if` optimista.
  return await db.transaction(async (tx) => {
    const [encontrado] = await tx
      .select()
      .from(proCodes)
      .where(eq(proCodes.code, normalizado))
      .for("update")
      .limit(1);

    // Un código rotado sigue en la tabla para que no lo resucite la siembra, pero
    // ya no vale: se responde igual que si no existiera.
    if (!encontrado || encontrado.revokedAt) return { ok: false, motivo: "no_existe" };

    const [yaCanjeado] = await tx
      .select()
      .from(proRedemptions)
      .where(and(eq(proRedemptions.code, normalizado), eq(proRedemptions.deviceId, deviceId)))
      .limit(1);

    // Si ya lo canjeó ESTE mismo dispositivo, se deja pasar sin gastar otro uso:
    // reinstalar la app o repetir el gesto no debería castigarse con un error.
    if (!yaCanjeado) {
      const [recuento] = await tx
        .select({ usados: count() })
        .from(proRedemptions)
        .where(eq(proRedemptions.code, normalizado));

      const usados = recuento?.usados ?? 0;
      const tope = encontrado.maxRedemptions;
      if (tope !== null && usados >= tope) return { ok: false, motivo: "ya_usado" };

      await tx.insert(proRedemptions).values({ code: normalizado, deviceId });
    }

    await tx
      .update(devices)
      .set({ isPro: true, proUntil: encontrado.expiresAt })
      .where(eq(devices.id, deviceId));

    return { ok: true, expiresAt: encontrado.expiresAt };
  });
}

// Rotar un código: deja de poder canjearse y quienes entraron por él pierden Pro.
//
// Es lo que convierte un código compartido en algo reversible: si acaba donde no
// debía, se retira sin tocar a quien tenga Pro por otra vía —un código personal
// sigue intacto, porque el Pro se retira por dispositivo y no en bloque—.
export async function revocar(code: string): Promise<{ existia: boolean; dispositivos: number }> {
  const normalizado = normalizar(code);

  return await db.transaction(async (tx) => {
    const [encontrado] = await tx
      .select()
      .from(proCodes)
      .where(eq(proCodes.code, normalizado))
      .limit(1);

    if (!encontrado || encontrado.revokedAt) return { existia: false, dispositivos: 0 };

    const canjes = await tx
      .select({ deviceId: proRedemptions.deviceId })
      .from(proRedemptions)
      .where(eq(proRedemptions.code, normalizado));

    // Se marca antes de mirar quién más tiene Pro, para que el propio código ya no
    // cuente como vivo al hacer esa comprobación.
    await tx
      .update(proCodes)
      .set({ revokedAt: new Date() })
      .where(eq(proCodes.code, normalizado));

    for (const { deviceId } of canjes) {
      // Solo pierde Pro quien no tenga otro código vivo: quitárselo a quien también
      // canjeó el suyo personal sería un daño colateral que nadie ha pedido.
      const vivos = await tx
        .select({ code: proRedemptions.code })
        .from(proRedemptions)
        .innerJoin(proCodes, eq(proCodes.code, proRedemptions.code))
        .where(and(eq(proRedemptions.deviceId, deviceId), isNull(proCodes.revokedAt)));

      if (vivos.length === 0) {
        await tx
          .update(devices)
          .set({ isPro: false, proUntil: null })
          .where(eq(devices.id, deviceId));
      }
    }

    return { existia: true, dispositivos: canjes.length };
  });
}

// Pro con caducidad ya pasada deja de ser Pro. Se comprueba al vuelo en vez de con
// una tarea programada: son dos comparaciones y evita depender de que algo corra a
// su hora.
export function esProVigente(device: { isPro: boolean; proUntil: Date | null }): boolean {
  if (!device.isPro) return false;
  if (!device.proUntil) return true;
  return device.proUntil > new Date();
}
