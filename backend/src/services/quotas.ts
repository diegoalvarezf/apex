import { eq, and, sql } from "drizzle-orm";
import { db } from "../db/index.js";
import { usageDaily, usageMonthly } from "../db/schema.js";
import { CATALOG, type AnalysisKind } from "./catalog.js";

// Cuotas por dispositivo.
//
// La app ya lleva un contador (`RoutineQuota.swift`), pero es solo de interfaz: el
// cliente es manipulable y no puede ser la autoridad sobre cuánto se gasta de la
// clave del servidor. Aquí se repiten como límite real.
//
// Los topes se agrupan por lo que cuesta cada llamada, no por análisis: los de
// Sonnet comparten un cupo diario y los de Opus uno mensual por tipo.

export interface Limits {
  dailyStandard: number;
  monthlyRoutine: number;
  monthlySwap: number;
}

export const FREE: Limits = {
  dailyStandard: 20,
  monthlyRoutine: 1,
  monthlySwap: 5,
};

export const PRO: Limits = {
  dailyStandard: 100,
  monthlyRoutine: 4,
  monthlySwap: 30,
};

export function limitsFor(isPro: boolean): Limits {
  return isPro ? PRO : FREE;
}

// Se usa UTC a propósito: si el corte dependiera de la zona del móvil, cambiar la
// hora del dispositivo renovaría la cuota.
export function todayKey(now = new Date()): string {
  return now.toISOString().slice(0, 10); // YYYY-MM-DD
}

export function monthKey(now = new Date()): string {
  return now.toISOString().slice(0, 7); // YYYY-MM
}

function limitFor(kind: AnalysisKind, limits: Limits): number {
  if (kind === "routineCreate") return limits.monthlyRoutine;
  if (kind === "exerciseSwap") return limits.monthlySwap;
  return limits.dailyStandard;
}

// Los análisis diarios comparten cupo: se cuentan todos bajo la misma clave en
// vez de dar un tope a cada uno. Repartirlos por tipo sería más restrictivo sin
// controlar mejor el gasto, que es lo único que importa aquí.
const SHARED_DAILY_KEY = "standard";

export interface QuotaState {
  allowed: boolean;
  used: number;
  limit: number;
  remaining: number;
  resetsAt: string;
}

export async function checkQuota(
  deviceId: string,
  kind: AnalysisKind,
  isPro: boolean,
  now = new Date(),
): Promise<QuotaState> {
  const limits = limitsFor(isPro);
  const limit = limitFor(kind, limits);
  const spec = CATALOG[kind];

  const used =
    spec.quota === "monthly"
      ? await readMonthly(deviceId, kind, monthKey(now))
      : await readDaily(deviceId, SHARED_DAILY_KEY, todayKey(now));

  return {
    allowed: used < limit,
    used,
    limit,
    remaining: Math.max(0, limit - used),
    resetsAt: spec.quota === "monthly" ? nextMonth(now) : nextDay(now),
  };
}

// Se consume DESPUÉS de que la llamada a la IA haya salido bien: si Anthropic
// falla o devuelve un error, el usuario no debe perder cuota por algo que no ha
// llegado a recibir.
export async function consumeQuota(
  deviceId: string,
  kind: AnalysisKind,
  now = new Date(),
): Promise<void> {
  const spec = CATALOG[kind];
  if (spec.quota === "monthly") {
    await db
      .insert(usageMonthly)
      .values({ deviceId, month: monthKey(now), kind, count: 1 })
      .onConflictDoUpdate({
        target: [usageMonthly.deviceId, usageMonthly.month, usageMonthly.kind],
        set: { count: sql`${usageMonthly.count} + 1` },
      });
  } else {
    await db
      .insert(usageDaily)
      .values({ deviceId, day: todayKey(now), kind: SHARED_DAILY_KEY, count: 1 })
      .onConflictDoUpdate({
        target: [usageDaily.deviceId, usageDaily.day, usageDaily.kind],
        set: { count: sql`${usageDaily.count} + 1` },
      });
  }
}

// Contador diario de propósito general, sobre la misma tabla que las cuotas de
// IA. La tabla es (dispositivo, día, clave): sirve para contar cualquier cosa que
// se limite por día, no solo análisis. Lo usa el freno de intentos de canje, que
// necesita exactamente esto —contar por dispositivo y olvidarlo cada día— y no
// justifica una tabla ni una migración propias.
export async function contadorDiario(
  deviceId: string,
  clave: string,
  now = new Date(),
): Promise<number> {
  return readDaily(deviceId, clave, todayKey(now));
}

export async function incrementarDiario(
  deviceId: string,
  clave: string,
  now = new Date(),
): Promise<void> {
  await db
    .insert(usageDaily)
    .values({ deviceId, day: todayKey(now), kind: clave, count: 1 })
    .onConflictDoUpdate({
      target: [usageDaily.deviceId, usageDaily.day, usageDaily.kind],
      set: { count: sql`${usageDaily.count} + 1` },
    });
}

async function readDaily(deviceId: string, kind: string, day: string): Promise<number> {
  const [row] = await db
    .select({ count: usageDaily.count })
    .from(usageDaily)
    .where(
      and(eq(usageDaily.deviceId, deviceId), eq(usageDaily.day, day), eq(usageDaily.kind, kind)),
    )
    .limit(1);
  return row?.count ?? 0;
}

async function readMonthly(deviceId: string, kind: string, month: string): Promise<number> {
  const [row] = await db
    .select({ count: usageMonthly.count })
    .from(usageMonthly)
    .where(
      and(
        eq(usageMonthly.deviceId, deviceId),
        eq(usageMonthly.month, month),
        eq(usageMonthly.kind, kind),
      ),
    )
    .limit(1);
  return row?.count ?? 0;
}

function nextDay(now: Date): string {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  return d.toISOString();
}

function nextMonth(now: Date): string {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return d.toISOString();
}
