import { gte, sum } from "drizzle-orm";
import { db } from "../db/index.js";
import { aiCalls } from "../db/schema.js";
import { config } from "../config.js";

// Techo de gasto diario, para toda la instalación.
//
// Las cuotas por dispositivo acotan lo que gasta CADA UNO, no lo que se gasta en
// total: quien pueda registrar dispositivos nuevos multiplica su cupo por cuantos
// registre. Cerrar eso de verdad exige App Attest, que necesita cuenta de
// desarrollador de pago; mientras tanto, esto pone el suelo bajo el peor caso.
//
// Es un límite de otra naturaleza que los demás. No pregunta quién eres ni qué
// pides: mira lo que ya se ha gastado hoy y corta. Eso lo hace el único que
// también protege de lo que no hemos previsto —un fallo nuestro, un bucle en el
// cliente, un abuso que no se parezca a los que imaginamos—, porque no depende de
// reconocer el ataque.
//
// Se apoya en `ai_calls`, que ya registra el coste REAL que informa la API en cada
// llamada. No es una estimación.

// En millonésimas de dólar, como el resto de costes: enteros para poder sumarlos
// sin arrastrar error de coma flotante.
export function limiteDiarioMicros(): number {
  return Math.round(config.dailySpendLimitUsd * 1_000_000);
}

function inicioDeHoyUTC(now = new Date()): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

export async function gastoHoyMicros(now = new Date()): Promise<number> {
  const [fila] = await db
    .select({ total: sum(aiCalls.costMicros) })
    .from(aiCalls)
    .where(gte(aiCalls.createdAt, inicioDeHoyUTC(now)));

  // `sum` devuelve null cuando no hay filas, y texto cuando las hay: Postgres
  // devuelve los agregados de enteros como numeric para no desbordar.
  return Number(fila?.total ?? 0);
}

export interface EstadoGasto {
  dentro: boolean;
  gastadoMicros: number;
  limiteMicros: number;
}

export async function comprobarPresupuesto(now = new Date()): Promise<EstadoGasto> {
  const limiteMicros = limiteDiarioMicros();
  const gastadoMicros = await gastoHoyMicros(now);
  return { dentro: gastadoMicros < limiteMicros, gastadoMicros, limiteMicros };
}
