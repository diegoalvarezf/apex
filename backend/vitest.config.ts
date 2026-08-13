import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // La configuración se valida al cargarse (para que un despliegue mal
    // configurado falle al arrancar y no en la primera petición de un usuario).
    // Eso obliga a darle valores aquí: los tests no tocan la base de datos ni las
    // APIs, solo importan módulos que las declaran.
    env: {
      DATABASE_URL: "postgres://test:test@localhost:5432/test",
      ANTHROPIC_API_KEY: "sk-ant-test-no-se-usa",
      STRAVA_CLIENT_ID: "0",
      STRAVA_CLIENT_SECRET: "test",
      NODE_ENV: "test",
    },
  },
});
