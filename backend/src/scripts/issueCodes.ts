import { db } from "../db/index.js";
import { proCodes } from "../db/schema.js";
import { generarCodigo, normalizar } from "../services/pro.js";

// Emite códigos de Apex Pro.
//
//   npm run pro:issue -- --para "Tribunal TFM" --usos 10
//   npm run pro:issue -- --para "Diego" --code APEX-PRO-DIEGO
//   npm run pro:issue -- --para "Beta" --cuantos 5 --dias 90
//
//   --para     para quién es, en texto libre (solo para saber qué es cada uno)
//   --code     código concreto en vez de uno aleatorio (implica --cuantos 1)
//   --cuantos  cuántos generar (por defecto 1)
//   --usos     cuántos dispositivos pueden canjearlo (por defecto 1, 0 = sin límite)
//   --dias     cuánto dura el Pro que concede (por defecto 0 = sin caducidad)
//
// Los códigos se guardan normalizados —sin guiones, que son solo para leerlos—
// porque así es como se comparan al canjear.

function flag(nombre: string): string | undefined {
  const i = process.argv.indexOf(`--${nombre}`);
  return i === -1 ? undefined : process.argv[i + 1];
}

const paraQuien = flag("para") ?? "sin asignar";
const codigoFijo = flag("code");
const cuantos = codigoFijo ? 1 : Number(flag("cuantos") ?? 1);
const usos = Number(flag("usos") ?? 1);
const dias = Number(flag("dias") ?? 0);

function salir(mensaje: string): never {
  console.error(mensaje);
  process.exit(1);
}

if (!Number.isInteger(cuantos) || cuantos < 1 || cuantos > 100) {
  salir("--cuantos debe ser un entero entre 1 y 100.");
}
if (!Number.isInteger(usos) || usos < 0) {
  salir("--usos debe ser un entero: 1 o más, o 0 para sin límite.");
}
if (!Number.isInteger(dias) || dias < 0) {
  salir("--dias debe ser un entero de 0 en adelante.");
}
if (codigoFijo && normalizar(codigoFijo).length < 6) {
  salir("Un código a medida debe tener al menos 6 caracteres alfanuméricos.");
}

const expiresAt = dias > 0 ? new Date(Date.now() + dias * 24 * 60 * 60 * 1000) : null;
const maxRedemptions = usos === 0 ? null : usos;
const generados = codigoFijo
  ? [codigoFijo]
  : Array.from({ length: cuantos }, () => generarCodigo());

await db.insert(proCodes).values(
  generados.map((code) => ({
    code: normalizar(code),
    issuedTo: paraQuien,
    maxRedemptions,
    expiresAt,
  })),
);

console.log(`\n${generados.length} código(s) para "${paraQuien}"`);
console.log(maxRedemptions === null ? "Usos: sin límite" : `Usos: ${maxRedemptions}`);
console.log(expiresAt ? `Caducan el ${expiresAt.toLocaleDateString("es-ES")}` : "Sin caducidad");
console.log();
for (const code of generados) console.log("  " + code);
console.log("\nApúntalos: no se pueden volver a consultar.\n");

process.exit(0);
