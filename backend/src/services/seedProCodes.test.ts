import { describe, it, expect } from "vitest";
import { parsearCodigos } from "./seedProCodes.js";

// La variable la teclea una persona en el panel de Railway, así que lo que hay que
// fijar es que una entrada mal escrita no se cuele ni tumbe el arranque.
describe("lectura de PRO_CODES", () => {
  it("lee código y usos", () => {
    expect(parsearCodigos("APEX-DESARROLLO:1")).toEqual([
      { code: "APEXDESARROLLO", maxRedemptions: 1 },
    ]);
  });

  it("cero usos significa sin límite", () => {
    expect(parsearCodigos("APEX-TRIBUNAL:0")[0]!.maxRedemptions).toBeNull();
  });

  it("sin usos, uno solo", () => {
    expect(parsearCodigos("APEX-TRIBUNAL")[0]!.maxRedemptions).toBe(1);
  });

  it("lee varios y aguanta los espacios", () => {
    expect(parsearCodigos(" APEX-DESARROLLO:1 , APEX-TRIBUNAL:0 ")).toHaveLength(2);
  });

  // Un código de dos letras se adivina a mano; mejor no sembrarlo que sembrarlo mal.
  it("descarta lo que no sirve como código", () => {
    expect(parsearCodigos("AB:1,,   ,APEX-BUENO:2,OTRO:-3")).toEqual([
      { code: "APEXBUENO", maxRedemptions: 2 },
    ]);
  });

  it("una variable vacía no siembra nada", () => {
    expect(parsearCodigos("")).toEqual([]);
  });
});
