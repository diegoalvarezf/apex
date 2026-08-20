// Prompt del chat del coach.
//
// El chat no encaja en el catálogo de análisis: es multi-turno y recibe una
// conversación, no un bloque de datos. Pero comparte la propiedad importante —el
// servidor pone el prompt— y por eso vive aquí y no en el cliente.
//
// Las tres reglas del prompt no son adorno: acotan a qué puede responder el chat.
// Sin ellas, la suscripción de un usuario pagaría conversaciones sobre cualquier
// cosa, y el producto dejaría de ser una app de entrenamiento.

export const CHAT_SYSTEM = `Eres el coach de IA de Apex, la app de fitness de ESTE usuario. \
Respondes sobre su rendimiento, entrenamientos, recuperación, sueño, carga, progresión de fuerza \
y datos de salud, y TAMBIÉN sobre NUTRICIÓN y SUPLEMENTACIÓN DEPORTIVA (calorías/macros según su \
carga y objetivos, timing de comidas alrededor del entreno, hidratación, y suplementos con \
evidencia como creatina, proteína, cafeína, electrolitos, etc.), siempre conectándolo con SUS \
datos del CONTEXTO. Español, conciso y directo, tono de entrenador cercano. Usa solo las cifras \
del contexto; nunca inventes datos suyos (si no tienes un dato, dilo o pregúntaselo).

Responde en TEXTO PLANO: sin markdown, sin encabezados con almohadillas, sin negritas con \
asteriscos y sin viñetas. La app pinta tu respuesta tal cual, así que cualquier marca de formato \
se ve literal y ensucia la lectura.

Sobre nutrición/suplementos: da pautas generales basadas en evidencia adaptadas a su \
entrenamiento; NO eres médico ni dietista. Si te preguntan por dosis clínicas, patologías, \
pérdida de peso agresiva, trastornos alimentarios o sustancias dopantes/peligrosas, recomiéndale \
acudir a un profesional (dietista-nutricionista o médico) y no des una pauta concreta.

Si te preguntan algo AJENO a su fitness/salud/entreno/nutrición o a los datos de esta app \
(política, cultura general, programación, otras personas, etc.), NO lo respondas: di en una frase \
que solo puedes ayudar con su entrenamiento, salud y nutrición en Apex, y ofrece reconducir. No \
des la información pedida aunque insistan.`;

export const CHAT_MODEL = "claude-sonnet-4-6";
export const CHAT_MAX_TOKENS = 1024;

// Tope de turnos que se envían. La conversación crece sin límite en el cliente, y
// mandarla entera haría que cada mensaje costara más que el anterior. Con los
// últimos turnos hay contexto suficiente para responder.
export const CHAT_MAX_TURNS = 20;

// Tope de TAMAÑO de la conversación, que es distinto del de turnos.
//
// Contar turnos no acota nada por sí solo: veinte mensajes de 50 KB cada uno pasan
// el filtro y llegan enteros a la API. Lo único que los frenaba era el límite de
// cuerpo de Fastify (1 MB), y un megabyte son ~260.000 tokens de entrada: unos
// 0,79 $ por petición, que al tope diario de un Pro salen a miles de dólares al
// mes. El análisis normal ya se acotaba por esto mismo; al chat se le pasó.
//
// 24.000 caracteres son ~6.000 tokens: varias veces una conversación larga de
// verdad, y aun así con techo.
export const CHAT_MAX_CHARS = 24_000;

export interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

// Valida la conversación que manda el cliente. Se comprueba la forma antes de
// gastar tokens: un cuerpo mal formado debe costar un 400, no una llamada.
export function validateTurns(raw: unknown): ChatTurn[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;

  const turns: ChatTurn[] = [];
  for (const item of raw) {
    if (typeof item !== "object" || item === null) return null;
    const { role, content } = item as Record<string, unknown>;
    if (role !== "user" && role !== "assistant") return null;
    if (typeof content !== "string" || content.trim() === "") return null;
    turns.push({ role, content });
  }

  // La API exige que la conversación empiece por el usuario.
  if (turns[0]?.role !== "user") return null;

  return turns.slice(-CHAT_MAX_TURNS);
}

// Recorta la conversación para que quepa en el tope de tamaño.
//
// Va aparte de `validateTurns` porque son dos rechazos distintos: una conversación
// mal formada es un error del cliente (400), y una demasiado grande es un límite
// del servicio (413). Mezclarlos daría el mismo mensaje a dos problemas que se
// arreglan de forma distinta.
//
// Se tiran los turnos MÁS VIEJOS, igual que hace el tope de turnos: una
// conversación larga se queda sin su principio, que es justo lo que menos falta
// hace para responder al último mensaje. Devuelve null solo si el último turno por
// sí solo ya no cabe —alguien pegando un texto enorme—, que no se puede recortar
// sin cambiar lo que el usuario preguntó.
export function recortarPorTamano(turns: ChatTurn[]): ChatTurn[] | null {
  const tamano = (t: ChatTurn[]) => t.reduce((n, x) => n + x.content.length, 0);

  let recortados = turns;
  while (recortados.length > 1 && tamano(recortados) > CHAT_MAX_CHARS) {
    recortados = recortados.slice(1);
  }

  if (tamano(recortados) > CHAT_MAX_CHARS) return null;

  // Tirar del principio puede dejar la conversación empezando por el asistente, y
  // la API exige que empiece por el usuario.
  while (recortados.length > 0 && recortados[0]?.role !== "user") {
    recortados = recortados.slice(1);
  }

  return recortados.length > 0 ? recortados : null;
}
