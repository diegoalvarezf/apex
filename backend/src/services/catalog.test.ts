import { describe, it, expect } from "vitest";
import { CATALOG, MODELS, isKnownKind, costMicros, type AnalysisKind } from "./catalog.js";

// El catálogo es la barrera que impide que el proxy sea una API de Claude abierta.
// Si aceptara un tipo desconocido, o si un análisis barato acabara apuntando al
// modelo caro, el coste se dispararía sin que nadie se enterara.
describe("catálogo de análisis", () => {
  it("acepta los tipos que conoce", () => {
    expect(isKnownKind("alerts")).toBe(true);
    expect(isKnownKind("routineCreate")).toBe(true);
    expect(isKnownKind("exerciseSwap")).toBe(true);
  });

  // Lo que de verdad protege: cualquier cosa fuera de la lista se rechaza antes
  // de gastar un token.
  it("rechaza lo que no está en la lista", () => {
    expect(isKnownKind("cualquier-cosa")).toBe(false);
    expect(isKnownKind("")).toBe(false);
    expect(isKnownKind("__proto__")).toBe(false);
    expect(isKnownKind("constructor")).toBe(false);
  });

  it("todos los análisis declaran prompt, modelo y tope", () => {
    for (const [kind, spec] of Object.entries(CATALOG)) {
      expect(spec.system.length, `${kind} sin prompt`).toBeGreaterThan(50);
      expect(spec.maxTokens, `${kind} sin tope`).toBeGreaterThan(0);
      expect([MODELS.standard, MODELS.advanced]).toContain(spec.model);
    }
  });

  // El modelo grande solo donde se justifica: diseñar una rutina y sustituir un
  // ejercicio. Si se colara en un análisis diario, multiplicaría el coste por 30.
  it("solo rutinas y cambios usan el modelo caro", () => {
    const conModeloCaro = (Object.keys(CATALOG) as AnalysisKind[]).filter(
      (k) => CATALOG[k].model === MODELS.advanced,
    );
    expect(conModeloCaro.sort()).toEqual(["exerciseSwap", "routineCreate"]);
  });

  // Y lo caro se cuenta por mes, no por día: un cupo diario de rutinas permitiría
  // 30 al mes, que es justo lo que se quiere evitar.
  it("lo que usa el modelo caro va con cuota mensual", () => {
    for (const kind of Object.keys(CATALOG) as AnalysisKind[]) {
      if (CATALOG[kind].model === MODELS.advanced) {
        expect(CATALOG[kind].quota, `${kind} debería ser mensual`).toBe("monthly");
      }
    }
  });
});

// El coste se calcula en enteros para poder sumarlo sin arrastrar errores. Los
// valores esperados salen de aplicar la tarifa a mano, no de ejecutar la función.
describe("coste por llamada", () => {
  it("cobra un análisis normal a la tarifa de Sonnet", () => {
    // 1.500 entrada × 3 + 500 salida × 15 = 4.500 + 7.500 = 12.000 millonésimas
    expect(costMicros(MODELS.standard, 1500, 500)).toBe(12_000);
  });

  it("cobra una rutina a la tarifa de Opus", () => {
    // 2.500 × 5 + 6.000 × 25 = 12.500 + 150.000 = 162.500 → 0,1625 $
    expect(costMicros(MODELS.advanced, 2500, 6000)).toBe(162_500);
  });

  // La comprobación que da sentido a la cuota: una rutina cuesta más de diez
  // análisis diarios, y por eso tiene un tope aparte.
  it("una rutina cuesta más que diez análisis", () => {
    const rutina = costMicros(MODELS.advanced, 2500, 6000);
    const diezAnalisis = 10 * costMicros(MODELS.standard, 1500, 500);
    expect(rutina).toBeGreaterThan(diezAnalisis);
  });

  it("un modelo desconocido no inventa un precio", () => {
    expect(costMicros("modelo-que-no-existe", 1000, 1000)).toBe(0);
  });
});
