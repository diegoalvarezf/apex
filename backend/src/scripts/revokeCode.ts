import { revocar } from "../services/pro.js";

// Rota un código de Apex Pro.
//
//   npm run pro:revoke -- APEX-PRO-TRIBUNAL
//
// El código deja de poder canjearse y quienes entraron por él pierden Pro. A quien
// tenga además un código propio no se le toca: el Pro se retira por dispositivo.
//
// Es la vuelta atrás de un código compartido, que es lo que lo hace repartible sin
// riesgo: si acaba donde no debía, se corta.

const code = process.argv[2];

if (!code) {
  console.error("Uso: npm run pro:revoke -- CODIGO");
  process.exit(1);
}

const { existia, dispositivos } = await revocar(code);

if (!existia) {
  console.error(`\nNo hay ningún código "${code}".\n`);
  process.exit(1);
}

console.log(`\nCódigo "${code}" revocado.`);
console.log(`Lo habían canjeado ${dispositivos} dispositivo(s); han perdido Pro.\n`);

process.exit(0);
