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

  // El acoplamiento más frágil del sistema: la app tiene su propio enum
  // (`AnalysisKind` en BackendClient.swift) y pide análisis por nombre. Si aquí se
  // renombra o se borra uno, las llamadas de esa versión de la app empiezan a
  // recibir 400 sin que nada avise en tiempo de compilación. Esta lista fija el
  // contrato: tocarla obliga a mirar también el lado Swift.
  it("expone exactamente los análisis que la app conoce", () => {
    expect(Object.keys(CATALOG).sort()).toEqual([
      "alerts",
      "effort",
      "exerciseProgress",
      "exerciseSwap",
      "insights",
      "recovery",
      "routineCreate",
      "routineDay",
      "routineParse",
      "run",
      "sleep",
      "stress",
      "weekly",
    ]);
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

  // Los que el cliente pinta como un bloque de texto (AITextCard/AIAnalysisBody)
  // tienen que venir en viñetas y terminar en una línea "Conclusión: " literal:
  // es lo que separa la caja destacada del resto. Los demás devuelven JSON que la
  // app ya trocea en tarjetas por su cuenta, así que no aplica.
  const kindsEnProsa: AnalysisKind[] = [
    "weekly", "recovery", "stress", "effort", "run", "sleep", "exerciseProgress", "routineDay",
  ];

  it("todo lo que se enseña como texto pide viñetas", () => {
    for (const kind of kindsEnProsa) {
      expect(CATALOG[kind].system, `${kind} sin viñetas`).toContain("empezando por '• '");
    }
  });

  // La cadena exacta que el cliente busca para separar la conclusión del resto
  // (`AIAnalysisBody` en Swift). Si el prompt la pide con otras palabras, la app
  // no encuentra la caja y el texto entero se ve como un párrafo suelto.
  it("todo lo que se enseña como texto pide la conclusión con el marcador exacto", () => {
    for (const kind of kindsEnProsa) {
      expect(CATALOG[kind].system, `${kind} sin "Conclusión: "`).toContain('"Conclusión: "');
    }
  });

  // Los que devuelven JSON llevan su esquema completo en el propio prompt de
  // sistema: es "el servidor es dueño de los prompts" tomado en serio. Antes,
  // insights/alerts/routineParse/routineCreate solo decían "responde con el
  // esquema que se te indica" y el esquema de verdad vivía en el texto que
  // montaba el cliente —viajaba como DATO, no como instrucción, desde que el
  // texto del cliente se envuelve con wrapAsData()—. Corregir un campo exigía
  // publicar una versión nueva de la app, justo lo que este catálogo dice evitar.
  const kindsJSON: AnalysisKind[] = ["insights", "alerts", "routineParse", "routineCreate"];

  it("los análisis en JSON llevan su propio esquema en el prompt de sistema", () => {
    for (const kind of kindsJSON) {
      const system = CATALOG[kind].system;
      expect(system, `${kind} sin llaves de esquema`).toContain("{");
      // Nada de "el esquema que se te indica": eso delega en un esquema que no
      // está aquí.
      expect(system, `${kind} delega el esquema en otro sitio`).not.toContain(
        "esquema que se te indica",
      );
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
