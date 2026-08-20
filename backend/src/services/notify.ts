import { config } from "../config.js";

// Aviso por correo cuando alguien canjea un código de Apex Pro.
//
// Solo existe para que Diego sepa, sin entrar a mirar la base de datos, cuándo el
// tribunal ha activado su código. Usa Resend porque no exige verificar un dominio
// para mandarse correo A UNO MISMO —basta la clave de API—, que es justo lo que
// hace falta aquí y nada más.
//
// Nunca debe poder tumbar un canje: si el correo falla, se registra en el log y
// el canje sigue habiendo funcionado.

const RESEND_URL = "https://api.resend.com/emails";
// Remitente de pruebas de Resend: envía sin verificar dominio propio, pero SOLO
// entrega a la dirección con la que se creó la cuenta de Resend. Como el único
// destinatario es `notifyEmail` —normalmente esa misma cuenta—, no hace falta más.
const REMITENTE = "Apex <onboarding@resend.dev>";

export interface CanjeParaNotificar {
  code: string;
  issuedTo: string | null;
  deviceId: string;
  platform: string;
}

// Pura y testeable: separada de `fetch` para poder fijar el contenido exacto sin
// mockear red.
export function construirCorreo(canje: CanjeParaNotificar): { subject: string; text: string } {
  const quien = canje.issuedTo?.trim() || "sin asignar";
  return {
    subject: `Apex Pro activado: ${quien}`,
    text: [
      `Se ha canjeado un código de Apex Pro.`,
      ``,
      `Código: ${canje.code}`,
      `Emitido para: ${quien}`,
      `Dispositivo: ${canje.deviceId} (${canje.platform})`,
      `Fecha: ${new Date().toLocaleString("es-ES")}`,
    ].join("\n"),
  };
}

export async function notificarCanje(
  canje: CanjeParaNotificar,
  log: { warn: (o: object, m: string) => void; error: (o: object, m: string) => void },
): Promise<void> {
  const { resendApiKey, notifyEmail } = config.email;
  if (!resendApiKey || !notifyEmail) {
    log.warn({ code: canje.code }, "aviso de canje omitido: falta RESEND_API_KEY o NOTIFY_EMAIL");
    return;
  }

  const { subject, text } = construirCorreo(canje);

  try {
    const res = await fetch(RESEND_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: REMITENTE, to: notifyEmail, subject, text }),
    });
    if (!res.ok) {
      log.error({ status: res.status }, "Resend rechazó el aviso de canje");
    }
  } catch (err) {
    // Sin red o Resend caído: no debe tumbar el canje, que ya se hizo.
    log.error({ err }, "no se ha podido avisar del canje por correo");
  }
}
