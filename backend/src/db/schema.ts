import {
  pgTable,
  text,
  integer,
  boolean,
  timestamp,
  primaryKey,
  index,
} from "drizzle-orm/pg-core";

// Un dispositivo con la app instalada.
//
// Se guarda el HASH del token, nunca el token: si alguien se hiciera con un volcado
// de la base de datos, no podría suplantar a ningún dispositivo con lo que hay ahí.
// El token en claro solo existe en el Keychain del móvil y en la respuesta al
// registro, que se emite una única vez.
export const devices = pgTable(
  "devices",
  {
    id: text("id").primaryKey(),
    tokenHash: text("token_hash").notNull(),
    platform: text("platform").notNull().default("ios"),
    isPro: boolean("is_pro").notNull().default(false),
    // Cuándo deja de ser Pro. Nulo con isPro=true significa sin caducidad.
    proUntil: timestamp("pro_until", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }).notNull().defaultNow(),
    // HASH de la IP desde la que se registró, nunca la IP. Sirve para limitar
    // cuántos dispositivos puede dar de alta un mismo origen; guardarla en claro
    // sería recoger un dato personal que no hace falta para eso.
    registrationIpHash: text("registration_ip_hash"),
  },
  (t) => [
    index("devices_token_hash_idx").on(t.tokenHash),
    index("devices_reg_ip_idx").on(t.registrationIpHash, t.createdAt),
  ],
);

// Consumo diario, para los análisis baratos (alertas, resumen, métricas).
// La clave primaria compuesta hace que un UPSERT baste para contar.
export const usageDaily = pgTable(
  "usage_daily",
  {
    deviceId: text("device_id").notNull(),
    day: text("day").notNull(), // YYYY-MM-DD en UTC
    kind: text("kind").notNull(),
    count: integer("count").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.deviceId, t.day, t.kind] })],
);

// Consumo mensual, para lo caro: rutinas y cambios de ejercicio.
export const usageMonthly = pgTable(
  "usage_monthly",
  {
    deviceId: text("device_id").notNull(),
    month: text("month").notNull(), // YYYY-MM en UTC
    kind: text("kind").notNull(),
    count: integer("count").notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.deviceId, t.month, t.kind] })],
);

// Una fila por llamada a la IA, con los tokens que informa la propia API.
//
// Es lo que convierte el coste por usuario en un dato medido en vez de una
// estimación: hasta ahora se calculaba leyendo el código y suponiendo el tamaño
// de los prompts. Con esto se sabe lo que cuesta de verdad, que es lo que decide
// si el precio de la suscripción se sostiene.
export const aiCalls = pgTable(
  "ai_calls",
  {
    id: text("id").primaryKey(),
    deviceId: text("device_id").notNull(),
    kind: text("kind").notNull(),
    model: text("model").notNull(),
    inputTokens: integer("input_tokens").notNull().default(0),
    outputTokens: integer("output_tokens").notNull().default(0),
    // En millonésimas de dólar: los enteros evitan los errores de redondeo de
    // coma flotante al sumar miles de llamadas baratas.
    costMicros: integer("cost_micros").notNull().default(0),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("ai_calls_device_idx").on(t.deviceId),
    index("ai_calls_created_idx").on(t.createdAt),
  ],
);

// Códigos de activación de Apex Pro.
//
// La suscripción de verdad exige In-App Purchase de Apple, y eso una cuenta de
// desarrollador de pago. Mientras tanto, Pro se concede con un código: sirve para
// usarlo de verdad y para que el tribunal pueda probarlo, sin simular una compra
// que no existe.
//
// Un código puede admitir uno o varios canjes: uno solo para entregarle Pro a una
// persona, varios para repartirlo entre gente de confianza. Quién lo canjeó vive
// en `pro_redemptions`, lo que permite retirarlo después.
export const proCodes = pgTable("pro_codes", {
  code: text("code").primaryKey(),
  // Para quién se emitió, en texto libre: "Tribunal TFM", "Diego"…
  issuedTo: text("issued_to"),
  // Cuántos dispositivos distintos pueden canjearlo. Nulo = sin límite.
  //
  // Un código de un solo uso sirve para entregar Pro a una persona; uno de varios
  // usos, para repartirlo entre gente de la que uno se fía —el tribunal— sin tener
  // que emitir y llevar la cuenta de un código por cabeza.
  maxRedemptions: integer("max_redemptions"),
  // Hasta cuándo dura el Pro que concede. Nulo = sin caducidad.
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  // Cuándo se rotó. La fila se conserva en vez de borrarse porque los códigos se
  // siembran al arrancar: si desapareciera, el siguiente reinicio la devolvería a
  // la vida y la rotación no duraría nada.
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Quién ha canjeado qué. Es una tabla y no un contador porque hace falta saber
// los dispositivos concretos: para que repetir el canje no gaste otro uso, y para
// poder retirar Pro justo a quienes entraron por un código al rotarlo.
export const proRedemptions = pgTable(
  "pro_redemptions",
  {
    code: text("code").notNull(),
    deviceId: text("device_id").notNull(),
    redeemedAt: timestamp("redeemed_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.code, t.deviceId] })],
);

export type Device = typeof devices.$inferSelect;
export type ProCode = typeof proCodes.$inferSelect;
export type NewDevice = typeof devices.$inferInsert;
export type AICall = typeof aiCalls.$inferInsert;
