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

  // Apagado mientras no haya cuenta de desarrollador de pago: sin ella no hay
  // productos en App Store Connect ni recibos reales que validar.
  subscriptionsEnabled: process.env.SUBSCRIPTIONS_ENABLED === "true",
} as const;

export type Config = typeof config;
