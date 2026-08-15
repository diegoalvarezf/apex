import { describe, it, expect } from "vitest";
import { generarCodigo, normalizar, esProVigente } from "./pro.js";

// Los códigos se teclean a mano, así que su forma importa tanto como su
// aleatoriedad: un carácter ambiguo convierte un canje en una llamada de soporte.
describe("generación de códigos", () => {
  it("tiene el formato XXXX-XXXX-XXXX", () => {
    expect(generarCodigo()).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  });

  // Sin 0/O ni 1/I/L: son los que se confunden al leerlos o dictarlos.
  it("evita los caracteres que se confunden", () => {
    const muchos = Array.from({ length: 200 }, () => generarCodigo()).join("");
    for (const malo of ["O", "0", "I", "1", "L"]) {
      expect(muchos.includes(malo), `no debería salir ${malo}`).toBe(false);
    }
  });

  it("no repite", () => {
    const codigos = new Set(Array.from({ length: 500 }, () => generarCodigo()));
    expect(codigos.size).toBe(500);
  });
});

// Quien teclea puede poner minúsculas, comerse los guiones o dejar un espacio.
// Nada de eso debería impedir un canje legítimo.
describe("normalización", () => {
  it("acepta las variantes razonables de un mismo código", () => {
    const canonico = "ABCD2345EFGH";
    for (const variante of [
      "ABCD-2345-EFGH",
      "abcd-2345-efgh",
      "  ABCD 2345 EFGH  ",
      "abcd2345efgh",
    ]) {
      expect(normalizar(variante), variante).toBe(canonico);
    }
  });
});

// El Pro con caducidad pasada deja de serlo. Se comprueba al vuelo, así que esta
// función decide qué cuota se aplica en cada petición.
describe("vigencia del plan Pro", () => {
  it("sin Pro, no hay Pro", () => {
    expect(esProVigente({ isPro: false, proUntil: null })).toBe(false);
    // Ni siquiera con una fecha futura: el booleano manda.
    expect(esProVigente({ isPro: false, proUntil: new Date(Date.now() + 86_400_000) })).toBe(false);
  });

  it("Pro sin fecha es Pro para siempre", () => {
    expect(esProVigente({ isPro: true, proUntil: null })).toBe(true);
  });

  it("Pro con fecha futura sigue activo", () => {
    expect(esProVigente({ isPro: true, proUntil: new Date(Date.now() + 86_400_000) })).toBe(true);
  });

  // El caso que evita que un código caducado siga dando cuota ampliada.
  it("Pro con fecha pasada ya no vale", () => {
    expect(esProVigente({ isPro: true, proUntil: new Date(Date.now() - 1000) })).toBe(false);
  });
});
