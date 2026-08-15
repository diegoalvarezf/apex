import { buildServer } from "./server.js";
import { config } from "./config.js";
import { seedProCodes } from "./services/seedProCodes.js";

const app = buildServer();

try {
  await seedProCodes(app.log);
  // 0.0.0.0 y no localhost: dentro del contenedor de Railway hay que escuchar en
  // todas las interfaces o el enrutador externo no llega al servicio.
  await app.listen({ port: config.port, host: "0.0.0.0" });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}

// Railway manda SIGTERM al desplegar una versión nueva. Cerrar ordenadamente evita
// cortar a mitad una generación de rutina, que puede llevar cerca de un minuto.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, async () => {
    app.log.info(`${signal} recibido, cerrando`);
    await app.close();
    process.exit(0);
  });
}
