import { describe, it, expect } from "vitest";
import { construirCorreo } from "./notify.js";

// Solo se prueba la parte pura (construir el contenido). Enviarlo de verdad
// depende de Resend y de la red, así que eso queda fuera de los tests igual que
// la llamada a Anthropic: aquí se fija el contrato, no la entrega.
describe("contenido del aviso de canje", () => {
  it("incluye el código, para quién y el dispositivo", () => {
    const correo = construirCorreo({
      code: "APEXTRIBUNAL", issuedTo: "Tribunal TFM", deviceId: "abc-123", platform: "ios",
    });
    expect(correo.subject).toContain("Tribunal TFM");
    expect(correo.text).toContain("APEXTRIBUNAL");
    expect(correo.text).toContain("Tribunal TFM");
    expect(correo.text).toContain("abc-123");
    expect(correo.text).toContain("ios");
  });

  // Un código sembrado sin --para (o emitido a mano sin `issuedTo`) no debe
  // reventar el correo ni mandarlo con "undefined" en el asunto.
  it("un código sin destinatario asignado no rompe el correo", () => {
    const correo = construirCorreo({ code: "X", issuedTo: null, deviceId: "d", platform: "ios" });
    expect(correo.subject).not.toContain("undefined");
    expect(correo.subject).not.toContain("null");
    expect(correo.text).toContain("sin asignar");
  });
});
