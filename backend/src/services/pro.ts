import { randomBytes } from "node:crypto";
import { eq, and, isNull } from "drizzle-orm";
import { db } from "../db/index.js";
import { devices, proCodes } from "../db/schema.js";

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

  const [encontrado] = await db
    .select()
    .from(proCodes)
    .where(eq(proCodes.code, normalizado))
    .limit(1);

  if (!encontrado) return { ok: false, motivo: "no_existe" };

  // Si ya lo canjeó ESTE mismo dispositivo, se deja pasar: reinstalar la app o
  // repetir el gesto no debería castigarse con un error.
  if (encontrado.redeemedByDeviceId && encontrado.redeemedByDeviceId !== deviceId) {
    return { ok: false, motivo: "ya_usado" };
  }

  // Marcar el código solo si sigue libre (o es de este dispositivo). La condición
  // va en el UPDATE y no en un `if` previo: entre la lectura y la escritura cabe
  // otro canje, y así lo resuelve la base de datos en vez de una carrera.
  await db
    .update(proCodes)
    .set({ redeemedByDeviceId: deviceId, redeemedAt: new Date() })
    .where(and(eq(proCodes.code, normalizado), isNull(proCodes.redeemedByDeviceId)));

  await db
    .update(devices)
    .set({ isPro: true, proUntil: encontrado.expiresAt })
    .where(eq(devices.id, deviceId));

  return { ok: true, expiresAt: encontrado.expiresAt };
}

// Pro con caducidad ya pasada deja de ser Pro. Se comprueba al vuelo en vez de con
// una tarea programada: son dos comparaciones y evita depender de que algo corra a
// su hora.
export function esProVigente(device: { isPro: boolean; proUntil: Date | null }): boolean {
  if (!device.isPro) return false;
  if (!device.proUntil) return true;
  return device.proUntil > new Date();
}
