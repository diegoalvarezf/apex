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
