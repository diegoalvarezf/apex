import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "../db/index.js";
import { devices, type Device } from "../db/schema.js";

// Identidad de dispositivo.
//
// En el primer arranque la app se registra y recibe un token que guarda en el
// Keychain. No hay cuentas ni contraseñas: para lo que necesita el servidor
// —saber a quién cobrarle la cuota— basta con distinguir dispositivos.
//
// LÍMITE CONOCIDO, declarado también en la memoria: sin App Attest (que exige
// cuenta de desarrollador de pago) nada impide registrar dispositivos nuevos en
// bucle para renovar la cuota. Lo que acota el gasto son los topes por
// dispositivo, no la identidad. Cerrarlo de verdad requiere App Attest.

const TOKEN_BYTES = 32;

export interface RegisteredDevice {
  deviceId: string;
  token: string; // en claro, se devuelve UNA sola vez
}

export async function registerDevice(platform = "ios"): Promise<RegisteredDevice> {
  const deviceId = randomBytes(16).toString("hex");
  const token = randomBytes(TOKEN_BYTES).toString("base64url");

  await db.insert(devices).values({
    id: deviceId,
    tokenHash: hashToken(token),
    platform,
  });

  return { deviceId, token };
}

// Busca por el hash, nunca por el token: la base de datos no guarda el original,
// así que un volcado no permite suplantar a nadie.
export async function deviceForToken(token: string): Promise<Device | null> {
  if (!token) return null;

  const [device] = await db
    .select()
    .from(devices)
    .where(eq(devices.tokenHash, hashToken(token)))
    .limit(1);

  if (!device) return null;

  // Comparación en tiempo constante: aunque aquí el riesgo es teórico —el índice
  // ya ha hecho la búsqueda—, deja explícito que un token no se compara con ==.
  if (!sameHash(device.tokenHash, hashToken(token))) return null;

  await db
    .update(devices)
    .set({ lastSeenAt: new Date() })
    .where(eq(devices.id, device.id));

  return device;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function sameHash(a: string, b: string): boolean {
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

// Extrae el token de "Authorization: Bearer <token>".
export function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const [scheme, value] = header.split(" ");
  if (!scheme || scheme.toLowerCase() !== "bearer" || !value) return null;
  return value.trim();
}
