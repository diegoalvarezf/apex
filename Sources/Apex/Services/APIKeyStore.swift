import Foundation
import Security

// Guarda la clave de la API de Anthropic que introduce el usuario.
//
// Va al Keychain y no a UserDefaults: es una credencial con la que se puede gastar
// dinero de su cuenta. UserDefaults se guarda en claro dentro del contenedor de la
// app y sale en las copias de seguridad.
//
// Cada usuario pone la suya. La alternativa —una clave compilada en la app— no
// funciona fuera de un uso personal: se puede extraer del binario y el consumo de
// todos los usuarios lo pagaría quien publicase la app.
enum APIKeyStore {

    private static let account = "anthropic-api-key"

    // MARK: - Validación

    enum ValidationError: LocalizedError {
        case empty
        case wrongPrefix
        case tooShort
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .empty:       return "Escribe una clave."
            case .wrongPrefix: return "Las claves de Anthropic empiezan por «sk-ant-». Comprueba que no has pegado la de otro servicio."
            case .tooShort:    return "La clave parece incompleta. Cópiala entera desde console.anthropic.com."
            case .rejected(let motivo): return motivo
            }
        }
    }

    // Comprobación de formato, para avisar antes de gastar una llamada de red.
    // No garantiza que la clave sea válida: eso solo lo dice la API.
    static func validateFormat(_ key: String) throws {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { throw ValidationError.empty }
        guard k.hasPrefix("sk-ant-") else { throw ValidationError.wrongPrefix }
        guard k.count >= 40 else { throw ValidationError.tooShort }
    }

    // MARK: - Keychain


    static var key: String? { Keychain.read(account) }

    @discardableResult
    static func save(_ key: String) -> Bool {
        Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
    }

    @discardableResult
    static func delete() -> Bool { Keychain.delete(account) }

    static var hasKey: Bool { key?.isEmpty == false }

    // Para mostrarla sin exponerla entera: sk-ant-…a1b2
    static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "sk-ant-…" + String(key.suffix(4))
    }
}
