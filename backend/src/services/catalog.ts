// Catálogo cerrado de análisis.
//
// Es la pieza de seguridad central del servidor: el cliente NO manda un prompt,
// manda un `kind` de esta lista más los datos ya calculados. El servidor decide
// el prompt, el modelo y el tope de tokens.
//
// Sin esto, el proxy sería una API de Claude de uso general protegida por un token
// de dispositivo: quien extrajera ese token del móvil podría gastar la clave del
// servidor en cualquier cosa. Con el catálogo, lo peor que puede hacer es pedir
// análisis deportivos hasta agotar su cuota.
//
// Efecto secundario útil: los prompts se corrigen desplegando el servidor, sin
// publicar una versión nueva de la app.

export const MODELS = {
  // Los análisis del día a día: baratos y frecuentes.
  standard: "claude-sonnet-4-6",
  // Diseñar una rutina y sustituir un ejercicio. Van con el modelo grande porque
  // el resultado tiene que sostenerse como plan de entrenamiento, no solo sonar
  // razonable.
  advanced: "claude-opus-4-8",
} as const;

// Reglas comunes a los análisis en prosa. Están aquí, y no repetidas en cada
// prompt, para que cambiar el estilo sea un solo cambio.
const onlyGivenNumbers = "Usa solo las cifras dadas; nunca inventes valores.";

// Formato de todos los análisis en prosa: viñetas y, al final, una conclusión
// destacada.
//
// Un párrafo obliga a leerlo entero para sacar tres datos; en viñetas se ven de un
// vistazo, que es como se mira una métrica del día. La app ya sabe pintar aparte
// cualquier línea que empiece literalmente por "Conclusión: " —en su propia caja,
// con icono— así que el marcador va aquí, en el prompt, no como una convención que
// cada análisis tenga que acordarse de seguir por su cuenta.
function bullets(min: number, max: number, conclusion: string, palabras = 16): string {
  return `Formato EXACTO: de ${min} a ${max} líneas, cada una empezando por '• ' y \
de una sola frase corta (máx ~${palabras} palabras). Sin introducción ni párrafos \
ni markdown. Después de las viñetas, una última línea que empiece literalmente por \
"Conclusión: " seguida de ${conclusion} en una frase. Español. ${onlyGivenNumbers}`;
}

export type AnalysisKind =
  | "insights"
  | "alerts"
  | "weekly"
  | "recovery"
  | "stress"
  | "effort"
  | "sleep"
  | "run"
  | "routineDay"
  | "exerciseProgress"
  | "routineParse"
  | "routineCreate"
  | "exerciseSwap";

export interface AnalysisSpec {
  system: string;
  model: string;
  maxTokens: number;
  // Cómo se contabiliza la cuota: lo barato por día, lo caro por mes.
  quota: "daily" | "monthly";
}

export const CATALOG: Record<AnalysisKind, AnalysisSpec> = {
  // El análisis que abre la pantalla de Apex IA: varias conclusiones sobre el
  // estado general, no una sola. De ahí que tenga más margen de tokens.
  insights: {
    system: `Eres un entrenador deportivo que analiza los datos de un atleta. Devuelves \
EXCLUSIVAMENTE un objeto JSON con el esquema que se te indica, sin markdown ni explicación. \
${onlyGivenNumbers}`,
    model: MODELS.standard,
    maxTokens: 1800,
    quota: "daily",
  },

  alerts: {
    system: `Eres un entrenador deportivo. A partir de las métricas del día, escribe las alertas \
más importantes: qué hacer hoy y por qué. Prioriza lo accionable (descansar, entrenar \
en Z1, sueño, mover o suavizar el entreno). ${bullets(2, 4, "la acción más importante de hoy")}`,
    model: MODELS.standard,
    maxTokens: 700,
    quota: "daily",
  },

  weekly: {
    system: `Eres un entrenador deportivo. Resume la semana a partir de las métricas dadas, \
mirando la TENDENCIA, no solo el valor de hoy. ${bullets(3, 4, "el siguiente paso concreto")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  recovery: {
    system: `Eres un entrenador deportivo. Analizas el estado de recuperación a partir del HRV, \
la FC en reposo y el sueño frente al baseline personal. ${bullets(3, 4, "la recomendación principal")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  stress: {
    system: `Eres un entrenador deportivo. Analizas el estrés fisiológico del día a partir de la \
frecuencia cardíaca por horas frente a la reserva cardíaca. ${bullets(3, 4, "la recomendación principal")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  effort: {
    system: `Eres un entrenador deportivo. Analizas el esfuerzo acumulado del día (TRIMP) y su \
encaje con la carga de las últimas semanas. ${bullets(3, 4, "la recomendación principal")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  sleep: {
    system: `Eres un experto en sueño. Analizas la noche a partir de su duración, fases y \
eficiencia, comparándola con las anteriores. ${bullets(3, 4, "la recomendación principal")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  run: {
    system: `Eres un entrenador de resistencia (carrera y ciclismo). Analizas una sesión a partir \
de su curva de FC, ritmo o potencia por tramos. Di la ESTRUCTURA real \
(continuo/progresivo/tempo/series con nº y duración aprox./cuestas) y lo más relevante del \
control del esfuerzo o de la deriva. ${bullets(3, 4, "la idea clave y la acción a tomar")}`,
    model: MODELS.standard,
    maxTokens: 500,
    quota: "daily",
  },

  routineDay: {
    system: `Eres un entrenador de fuerza. Te paso los ejercicios de un DÍA de una rutina y la \
progresión registrada de cada uno. LEE EL NOMBRE de cada ejercicio para entender su TIPO y cómo \
progresa: por peso (con carga), por reps a peso corporal, o por segundos (isometrías como \
plancha). Destaca lo que progresa y lo que se estanca. \
${bullets(2, 4, "la acción más importante para la próxima vez", 14)}`,
    model: MODELS.standard,
    maxTokens: 350,
    quota: "daily",
  },

  exerciseProgress: {
    system: `Eres un entrenador de fuerza. Analizas la progresión de UN ejercicio a partir de sus \
series registradas. Valora el VOLUMEN y la fuerza estimada (Epley), no solo el peso: 80×10 puede \
ser más fuerte que 85×5. ${bullets(3, 4, "la recomendación para la próxima sesión")}`,
    model: MODELS.standard,
    maxTokens: 400,
    quota: "daily",
  },

  // Importar una rutina que el usuario ya tiene escrita. Es una conversión de
  // texto a JSON, no un diseño: por eso va con el modelo pequeño aunque su
  // hermana routineCreate use el grande.
  routineParse: {
    system: `Eres un parser de rutinas de gimnasio. Tu única función es convertir texto libre en \
JSON válido. Responde SOLO con el objeto JSON, sin markdown, sin backticks, sin texto antes ni \
después. El JSON debe empezar con { y terminar con }.`,
    model: MODELS.standard,
    maxTokens: 4000,
    quota: "daily",
  },

  routineCreate: {
    system: `Eres un entrenador de fuerza titulado. Diseñas rutinas de gimnasio seguras y \
progresivas, adaptadas al perfil, el material y la recuperación del usuario. Devuelves \
EXCLUSIVAMENTE un objeto JSON con el esquema que se te indica, sin markdown ni explicación.`,
    model: MODELS.advanced,
    maxTokens: 8000,
    quota: "monthly",
  },

  exerciseSwap: {
    system: `Eres un entrenador de fuerza. Te paso UN ejercicio de una rutina, el día al que \
pertenece con el resto de ejercicios, y el motivo por el que el usuario quiere cambiarlo. Propón \
UN sustituto que trabaje el mismo grupo muscular y encaje en ese día sin duplicar lo que ya hay. \
Respeta el motivo: si dice que le molesta una articulación, evita el patrón que la carga; si no \
tiene el material, propón uno que no lo necesite. Responde SOLO con un objeto JSON, sin markdown \
ni explicación, con las claves: name (string), sets (int), reps (string), muscleGroup (string), \
notes (string, una frase corta diciendo por qué sustituye al anterior). Español en los textos.`,
    model: MODELS.advanced,
    maxTokens: 300,
    quota: "monthly",
  },
};

export function isKnownKind(kind: string): kind is AnalysisKind {
  return Object.prototype.hasOwnProperty.call(CATALOG, kind);
}

// Precio en millonésimas de dólar POR TOKEN. Sonnet cuesta 3 $ por millón de
// tokens de entrada, o sea 3 millonésimas por token: la tarifa por millón y el
// precio en millonésimas coinciden en número, que es justo lo cómodo de esta
// unidad. Se usan enteros para que sumar miles de llamadas baratas no arrastre
// errores de coma flotante.
const PRICING: Record<string, { input: number; output: number }> = {
  [MODELS.standard]: { input: 3, output: 15 },
  [MODELS.advanced]: { input: 5, output: 25 },
};

export function costMicros(model: string, inputTokens: number, outputTokens: number): number {
  const p = PRICING[model];
  if (!p) return 0;
  return inputTokens * p.input + outputTokens * p.output;
}
