import Testing
import Foundation
@testable import Apex

// Validación de la clave que introduce el usuario. Solo el formato: si la clave
// es realmente válida lo dice la API, no nosotros.
struct APIKeyStoreTests {

    @Test func aceptaUnaClaveConFormatoDeAnthropic() throws {
        let valida = "sk-ant-api03-" + String(repeating: "x", count: 40)
        try APIKeyStore.validateFormat(valida)   // no lanza
    }

    @Test func ignoraEspaciosAlrededor() throws {
        let conEspacios = "  sk-ant-api03-" + String(repeating: "x", count: 40) + "\n"
        try APIKeyStore.validateFormat(conEspacios)
    }

    @Test func rechazaVacio() {
        #expect(throws: APIKeyStore.ValidationError.self) {
            try APIKeyStore.validateFormat("   ")
        }
    }

    // Pegar la clave de otro servicio es el error más probable, así que se avisa
    // por el prefijo en vez de dejar que la API devuelva un 401 opaco.
    @Test func rechazaClavesDeOtrosServicios() {
        #expect(throws: APIKeyStore.ValidationError.self) {
            try APIKeyStore.validateFormat("sk-proj-" + String(repeating: "x", count: 40))
        }
    }

    @Test func rechazaClavesCortadas() {
        #expect(throws: APIKeyStore.ValidationError.self) {
            try APIKeyStore.validateFormat("sk-ant-api03-abc")
        }
    }

    // Al mostrarla nunca se enseña entera.
    @Test func laMascaraNoRevelaLaClave() {
        let clave = "sk-ant-api03-" + String(repeating: "x", count: 36) + "a1b2"
        let mostrada = APIKeyStore.masked(clave)
        #expect(mostrada.hasSuffix("a1b2"))
        #expect(!mostrada.contains(String(repeating: "x", count: 36)))
        #expect(mostrada.count < 20)
    }

    @Test func laMascaraAguantaClavesCortas() {
        #expect(APIKeyStore.masked("abc") == "••••")
    }
}
