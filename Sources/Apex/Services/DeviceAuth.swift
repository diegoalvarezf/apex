import Foundation

// Identidad del dispositivo frente al backend.
//
// No hay cuentas ni contraseñas: en el primer arranque la app se registra y recibe
// un token que guarda en el Keychain. Es todo lo que el servidor necesita para
// saber a quién aplicarle las cuotas.
//
// El token va al Keychain y no a UserDefaults por lo mismo que las credenciales de
// Strava: con él se consume la clave de Anthropic del servidor, así que es una
// credencial con la que se gasta dinero.
actor DeviceAuth {
    static let shared = DeviceAuth()

    private static let account = "apex-device-token"

    private var cached: String?
    // Registro en curso. Sin esto, varias pantallas pidiendo análisis a la vez en
    // el primer arranque dispararían un registro cada una y el dispositivo
    // quedaría duplicado en el servidor tantas veces como llamadas simultáneas.
    private var enCurso: Task<String, Error>?

    private init() {}

    // Token utilizable, registrando el dispositivo la primera vez.
    func token() async throws -> String {
        if let cached { return cached }

        if let guardado = Keychain.read(Self.account), !guardado.isEmpty {
            cached = guardado
            return guardado
        }

        if let enCurso { return try await enCurso.value }

        let task = Task<String, Error> {
            let nuevo = try await register()
            _ = Keychain.save(nuevo, account: Self.account)
            return nuevo
        }
        enCurso = task

        defer { enCurso = nil }
        let nuevo = try await task.value
        cached = nuevo
        return nuevo
    }

    // Se llama cuando el servidor responde 401: el token ya no vale (dispositivo
    // borrado en el servidor, base de datos reiniciada…). Se descarta para que la
    // siguiente petición registre de nuevo en vez de fallar para siempre.
    func invalidate() {
        cached = nil
        _ = Keychain.delete(Self.account)
    }

    var isRegistered: Bool {
        cached != nil || Keychain.read(Self.account)?.isEmpty == false
    }

    private func register() async throws -> String {
        struct Respuesta: Decodable {
            let deviceId: String
            let token: String
        }

        var request = URLRequest(url: BackendConfig.url("/v1/devices/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["platform": "ios"])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw BackendError.registroFallido
        }
        return try JSONDecoder().decode(Respuesta.self, from: data).token
    }
}
