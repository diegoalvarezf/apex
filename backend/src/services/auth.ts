import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { eq, and, gte, count } from "drizzle-orm";
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

// Cuántos dispositivos puede registrar un mismo origen por hora.
//
// Sin tope, un bucle contra el registro da cuotas ilimitadas —cada alta estrena
// las suyas— y de paso llena la base de datos. No cierra el agujero de fondo
// (para eso hace falta App Attest, que exige cuenta de pago), pero convierte un
// abuso trivial en uno que hay que trabajarse.
//
// Diez es holgado para el uso legítimo: reinstalar la app, un par de dispositivos
// y varias personas tras el mismo router de casa caben de sobra.
const MAX_REGISTROS_POR_HORA = 10;

// Cada cuánto se refresca `lastSeenAt`. Ver el motivo en `deviceForToken`.
const REFRESCO_ULTIMA_VISITA_MS = 60 * 60 * 1000;

export interface RegisteredDevice {
  deviceId: string;
  token: string; // en claro, se devuelve UNA sola vez
}

export class DemasiadosRegistros extends Error {
  constructor() {
    super("demasiados registros desde este origen");
  }
}

export async function registerDevice(
  platform = "ios",
  ip?: string,
): Promise<RegisteredDevice> {
  const ipHash = ip ? hashToken(ip) : null;

  if (ipHash && (await registrosUltimaHora(ipHash)) >= MAX_REGISTROS_POR_HORA) {
    throw new DemasiadosRegistros();
  }

  const deviceId = randomBytes(16).toString("hex");
  const token = randomBytes(TOKEN_BYTES).toString("base64url");

  await db.insert(devices).values({
    id: deviceId,
    tokenHash: hashToken(token),
    platform,
    registrationIpHash: ipHash,
  });

  return { deviceId, token };
}

async function registrosUltimaHora(ipHash: string): Promise<number> {
  const desde = new Date(Date.now() - 60 * 60 * 1000);
  const [fila] = await db
    .select({ total: count() })
    .from(devices)
    .where(and(eq(devices.registrationIpHash, ipHash), gte(devices.createdAt, desde)));
  return fila?.total ?? 0;
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

  // `lastSeenAt` solo sirve para saber, mirando la base de datos, cuándo estuvo
  // activo un dispositivo. Nadie lo lee desde el código, así que refrescarlo en
  // CADA petición añadía una escritura y su latencia a todas las llamadas
  // —incluidas las de solo lectura, como consultar la cuota— para un dato que con
  // precisión de horas ya cumple. Se refresca como mucho una vez por hora.
  if (Date.now() - device.lastSeenAt.getTime() > REFRESCO_ULTIMA_VISITA_MS) {
    await db
      .update(devices)
      .set({ lastSeenAt: new Date() })
      .where(eq(devices.id, device.id));
  }

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
