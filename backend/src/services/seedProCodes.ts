import { db } from "../db/index.js";
import { proCodes } from "../db/schema.js";
import { normalizar } from "./pro.js";

// Siembra códigos de Apex Pro desde una variable de entorno, al arrancar.
//
//   PRO_CODES="APEX-DESARROLLO:1,APEX-TRIBUNAL:0"
//
// Cada entrada es `código:usos`, con 0 = sin límite. Sin caducidad: los que se
// reparten a mano se retiran a mano, con `npm run pro:revoke`.
//
// Existe porque los scripts de emisión necesitan alcanzar la base de datos, y la de
// Railway solo es accesible desde dentro. La alternativa era abrirla a internet
// para emitir dos códigos: exponer Postgres de forma permanente para un gesto que
// se hace una vez es mal negocio.
//
// Es idempotente —un código ya existente no se toca— así que un reinicio no
// devuelve la vida a un código revocado ni reinicia los canjes ya hechos.
export function parsearCodigos(
  crudo: string,
): Array<{ code: string; maxRedemptions: number | null }> {
  const entradas: Array<{ code: string; maxRedemptions: number | null }> = [];

  for (const trozo of crudo.split(",")) {
    const limpio = trozo.trim();
    if (!limpio) continue;

    const [codigo, usos] = limpio.split(":");
    const normalizado = normalizar(codigo ?? "");
    if (normalizado.length < 6) continue;

    const n = Number(usos ?? 1);
    if (!Number.isInteger(n) || n < 0) continue;

    entradas.push({ code: normalizado, maxRedemptions: n === 0 ? null : n });
  }

  return entradas;
}

export async function seedProCodes(log: {
  info: (o: object, m: string) => void;
}): Promise<void> {
  const crudo = process.env.PRO_CODES;
  if (!crudo) return;

  const entradas = parsearCodigos(crudo);
  if (entradas.length === 0) return;

  await db
    .insert(proCodes)
    .values(entradas.map((e) => ({ ...e, issuedTo: "PRO_CODES" })))
    .onConflictDoNothing();

  log.info({ codigos: entradas.length }, "códigos de Apex Pro sembrados");
}
