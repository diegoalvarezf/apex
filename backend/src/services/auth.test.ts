import { describe, it, expect } from "vitest";
import { hashToken, bearerToken } from "./auth.js";

// El token del dispositivo es lo único que separa a un usuario de la clave de
// Anthropic del servidor. Estos tests fijan las dos propiedades que lo sostienen:
// que la base de datos no guarde el original, y que la cabecera se lea bien.
describe("token de dispositivo", () => {
  it("el hash no deja ver el token", () => {
    const token = "un-token-secreto-de-ejemplo";
    const hash = hashToken(token);

    expect(hash).not.toContain(token);
    expect(hash).toHaveLength(64); // sha256 en hexadecimal
  });

  it("el mismo token da siempre el mismo hash", () => {
    expect(hashToken("abc")).toBe(hashToken("abc"));
  });

  // Si dos tokens distintos colisionaran, un dispositivo podría hacerse pasar por
  // otro y gastarle la cuota.
  it("tokens distintos dan hashes distintos", () => {
    expect(hashToken("abc")).not.toBe(hashToken("abd"));
  });
});

describe("cabecera Authorization", () => {
  it("lee un Bearer bien formado", () => {
    expect(bearerToken("Bearer abc123")).toBe("abc123");
  });

  it("acepta el esquema en cualquier caja", () => {
    expect(bearerToken("bearer abc123")).toBe("abc123");
    expect(bearerToken("BEARER abc123")).toBe("abc123");
  });

  // Todo lo que no sea un Bearer con valor devuelve null, y el servidor responde
  // 401. Se prueba explícitamente para que un cambio futuro no lo deje pasar.
  it("rechaza lo que no es un Bearer con valor", () => {
    expect(bearerToken(undefined)).toBeNull();
    expect(bearerToken("")).toBeNull();
    expect(bearerToken("abc123")).toBeNull();          // sin esquema
    expect(bearerToken("Basic abc123")).toBeNull();    // otro esquema
    expect(bearerToken("Bearer")).toBeNull();          // sin valor
    expect(bearerToken("Bearer ")).toBeNull();
  });
});
