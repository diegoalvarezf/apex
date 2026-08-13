import Foundation
import Security

// Acceso al Keychain para las credenciales de la app.
//
// Todo lo que sirva para actuar en nombre del usuario —el token de Strava, la clave
// de la API de IA— va aquí y no a UserDefaults: UserDefaults es un fichero en claro
// dentro del contenedor de la app y entra en las copias de seguridad, así que
// cualquiera con acceso a un backup sin cifrar podría leer esas credenciales.
enum Keychain {

    private static let service = "com.diegoalvarezfrancos.apex"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // Solo con el dispositivo desbloqueado y sin salir de este dispositivo:
        // las credenciales no viajan a las copias de seguridad ni a otro iPhone.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // Traslada al Keychain un valor que versiones anteriores guardaron en
    // UserDefaults y lo borra de allí. Sin esto, actualizar la app cerraría la
    // sesión de Strava del usuario.
    @discardableResult
    static func migrateFromUserDefaults(key: String, account: String) -> Bool {
        guard read(account) == nil,
              let legacy = UserDefaults.standard.string(forKey: key),
              !legacy.isEmpty else { return false }
        let ok = save(legacy, account: account)
        if ok { UserDefaults.standard.removeObject(forKey: key) }
        return ok
    }
}
