import { describe, it, expect } from "vitest";
import { FREE, PRO, limitsFor, todayKey, monthKey } from "./quotas.js";

// Las cuotas son lo que acota el gasto por usuario. La app lleva su propio
// contador, pero es solo de interfaz: el cliente es manipulable y estos límites
// son la autoridad real.
describe("límites por plan", () => {
  it("Pro da más que gratis en todo", () => {
    expect(PRO.dailyStandard).toBeGreaterThan(FREE.dailyStandard);
    expect(PRO.monthlyRoutine).toBeGreaterThan(FREE.monthlyRoutine);
    expect(PRO.monthlySwap).toBeGreaterThan(FREE.monthlySwap);
  });

  it("elige el plan según el dispositivo", () => {
    expect(limitsFor(false)).toBe(FREE);
    expect(limitsFor(true)).toBe(PRO);
  });

  // Aunque un usuario Pro agotara todos sus topes cada mes, el gasto sigue
  // acotado. Con las tarifas actuales son unos 0,80 $ en rutinas y cambios.
  it("el peor caso de un Pro sigue siendo asumible", () => {
    const microsRutina = 2500 * 5 + 6000 * 25;   // ~0,1625 $
    const microsCambio = 500 * 5 + 150 * 25;     // ~0,006 $
    const peorCaso = PRO.monthlyRoutine * microsRutina + PRO.monthlySwap * microsCambio;

    // En dólares, por debajo de 1 $/mes en las llamadas caras.
    expect(peorCaso / 1_000_000).toBeLessThan(1);
  });
});

// Las claves van en UTC a propósito: si el corte siguiera la zona del móvil,
// cambiar la hora del dispositivo renovaría la cuota gratis.
describe("claves de periodo", () => {
  it("la clave diaria es la fecha UTC", () => {
    const d = new Date("2026-08-13T22:30:00Z");
    expect(todayKey(d)).toBe("2026-08-13");
  });

  it("la clave mensual es el mes UTC", () => {
    expect(monthKey(new Date("2026-08-13T22:30:00Z"))).toBe("2026-08");
  });

  // El caso que delata una implementación en hora local: a las 23:30 en España
  // (UTC+2) ya es el día siguiente, así que una clave local daría el día de mañana
  // y regalaría una cuota.
  it("no se deja llevar por la hora local", () => {
    const nocheEnEspana = new Date("2026-08-13T21:30:00Z"); // 23:30 en Madrid
    expect(todayKey(nocheEnEspana)).toBe("2026-08-13");
  });

  it("cambia de mes en el instante correcto", () => {
    expect(monthKey(new Date("2026-08-31T23:59:59Z"))).toBe("2026-08");
    expect(monthKey(new Date("2026-09-01T00:00:00Z"))).toBe("2026-09");
  });
});
