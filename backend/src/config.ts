// Configuración del servidor, leída del entorno.
//
// Se valida al arrancar y no al usar cada valor: es preferible que el despliegue
// falle inmediatamente y de forma ruidosa a que arranque y reviente en la primera
// petición de un usuario. Las credenciales solo viven aquí; ningún otro módulo
// lee `process.env`.

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === "") {
    throw new Error(
      `Falta la variable de entorno ${name}. ` +
        `Revisa .env en local o las variables del servicio en Railway.`,
    );
  }
  return value.trim();
}

function optionalNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

// A diferencia de `required`, su ausencia no impide arrancar: el aviso por correo
// es una comodidad, no algo de lo que dependa el servicio. Sin la clave, se
// registra en el log y se sigue sin enviar nada.
function optionalString(name: string): string | undefined {
  const value = process.env[name];
  return value && value.trim() !== "" ? value.trim() : undefined;
}

export const config = {
  port: optionalNumber("PORT", 3000),
  // Railway inyecta NODE_ENV=production en el despliegue.
  isProduction: process.env.NODE_ENV === "production",

  databaseUrl: required("DATABASE_URL"),

  // Clave exclusiva del servidor, separada de la personal: se puede revocar sin
  // afectar a nada más y su consumo queda aislado en la consola de Anthropic.
  anthropicApiKey: required("ANTHROPIC_API_KEY"),

  strava: {
    clientId: required("STRAVA_CLIENT_ID"),
    // El motivo de que exista este servidor: el OAuth de Strava exige el secreto
    // y no admite PKCE, así que en la app era imposible de proteger.
    clientSecret: required("STRAVA_CLIENT_SECRET"),
  },

  // Techo de gasto diario de la clave del servidor, en dólares.
  //
  // Las cuotas por dispositivo no acotan el total: quien registre dispositivos
  // nuevos multiplica su cupo. Esto corta por arriba pase lo que pase, incluido
  // lo que no hayamos previsto. Cinco dólares dejan mucho margen sobre el uso
  // real —una defensa de TFM entera no llega ni de lejos— y ponen el peor mes en
  // 150 en vez de en sin límite.
  dailySpendLimitUsd: optionalNumber("DAILY_SPEND_LIMIT_USD", 5),

  // Apagado mientras no haya cuenta de desarrollador de pago: sin ella no hay
  // productos en App Store Connect ni recibos reales que validar.
  subscriptionsEnabled: process.env.SUBSCRIPTIONS_ENABLED === "true",

  // Aviso por correo cuando alguien canjea un código de Apex Pro por primera vez.
  // Sin `resendApiKey` o `notifyEmail`, el servicio sigue funcionando igual: el
  // canje no depende de que el correo se pueda enviar.
  email: {
    resendApiKey: optionalString("RESEND_API_KEY"),
    notifyEmail: optionalString("NOTIFY_EMAIL"),
  },
} as const;

export type Config = typeof config;
