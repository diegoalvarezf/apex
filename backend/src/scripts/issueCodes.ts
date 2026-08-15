import { db } from "../db/index.js";
import { proCodes } from "../db/schema.js";
import { generarCodigo, normalizar } from "../services/pro.js";

// Emite códigos de Apex Pro.
//
//   npm run pro:issue -- "Tribunal TFM" 5 90
//
// Argumentos: para quién, cuántos, y cuántos días dura el Pro (0 = sin caducidad).
//
// Los códigos se imprimen una sola vez. Se guardan normalizados —sin guiones, que
// son solo para leerlos— porque así se comparan al canjear.

const paraQuien = process.argv[2] ?? "sin asignar";
const cuantos = Number(process.argv[3] ?? 1);
const dias = Number(process.argv[4] ?? 0);

if (!Number.isInteger(cuantos) || cuantos < 1 || cuantos > 100) {
  console.error("El número de códigos debe estar entre 1 y 100.");
  process.exit(1);
}

const expiresAt = dias > 0 ? new Date(Date.now() + dias * 24 * 60 * 60 * 1000) : null;
const generados = Array.from({ length: cuantos }, () => generarCodigo());

await db.insert(proCodes).values(
  generados.map((code) => ({
    code: normalizar(code),
    issuedTo: paraQuien,
    expiresAt,
  })),
);

console.log(`\n${cuantos} código(s) para "${paraQuien}"`);
console.log(expiresAt ? `Caducan el ${expiresAt.toLocaleDateString("es-ES")}\n` : "Sin caducidad\n");
for (const code of generados) console.log("  " + code);
console.log("\nApúntalos: no se pueden volver a consultar.\n");

process.exit(0);
