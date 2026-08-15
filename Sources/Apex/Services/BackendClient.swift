import Foundation

enum BackendConfig {
    // El servidor que custodia las credenciales y aplica las cuotas. No es un
    // secreto: es una URL pública, y lo que protege el acceso es el token del
    // dispositivo, no que la dirección sea desconocida.
    static let baseURL = "https://apex-production-cbfa.up.railway.app"

    static func url(_ path: String) -> URL {
        URL(string: baseURL + path)!
    }
}

enum BackendError: LocalizedError {
    case registroFallido
    case noAutorizado
    case cuotaAgotada(restantes: Int, limite: Int, renuevaEn: Date?)
    case tipoDesconocido
    case servidorCaido
    case respuestaIlegible

    var errorDescription: String? {
        switch self {
        case .registroFallido:
            return "No se ha podido registrar el dispositivo. Revisa tu conexión."
        case .noAutorizado:
            return "Sesión no válida. Inténtalo de nuevo."
        case .cuotaAgotada(_, let limite, let renuevaEn):
            let cuando = renuevaEn.map {
                let f = DateFormatter()
                f.locale = Locale(identifier: "es_ES")
                f.dateFormat = "d 'de' MMMM"
                return " Se renueva el \(f.string(from: $0))."
            } ?? ""
            return "Has agotado tus \(limite) usos.\(cuando)"
        case .tipoDesconocido:
            return "Este análisis ya no está disponible. Actualiza la app."
        case .servidorCaido:
            return "El servicio no está disponible ahora mismo. Inténtalo más tarde."
        case .respuestaIlegible:
            return "Respuesta inesperada del servidor."
        }
    }
}

// Los análisis que el servidor sabe hacer. Debe coincidir con el catálogo de
// `backend/src/services/catalog.ts`: si aquí se pide uno que allí no existe, el
// servidor responde 400 en vez de gastar tokens.
enum AnalysisKind: String {
    case alerts
    case weekly
    case recovery
    case stress
    case effort
    case sleep
    case run
    case routineDay
    case exerciseProgress
    case routineCreate
    case exerciseSwap
}

struct QuotaInfo: Decodable {
    let remaining: Int
    let limit: Int
    let resetsAt: String?
}

struct AllQuotas: Decodable {
    let isPro: Bool
    let standard: QuotaInfo
    let routine: QuotaInfo
    let swap: QuotaInfo
}

// Cliente del backend.
//
// La app ya no habla con Anthropic: manda el tipo de análisis y los datos, y el
// servidor pone el prompt, el modelo y la clave. Por eso aquí no hay ni prompts ni
// credenciales de terceros.
final class BackendClient {
    static let shared = BackendClient()

    private init() {}

    private struct AnalyzeResponse: Decodable {
        let text: String
        let quota: QuotaInfo?
    }

    private struct QuotaError: Decodable {
        let error: String
        let used: Int?
        let limit: Int?
        let resetsAt: String?
    }

    // Ejecuta un análisis del catálogo. `input` son los datos ya calculados por la
    // app; el prompt lo pone el servidor.
    func analyze(kind: AnalysisKind, input: String) async throws -> String {
        try await withRetryOnUnauthorized { token in
            var request = URLRequest(url: BackendConfig.url("/v1/ai/analyze"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // La generación de rutina ronda el medio minuto; con el valor por
            // defecto la petición se cortaría antes de que el servidor conteste.
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["kind": kind.rawValue, "input": input])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BackendError.respuestaIlegible
            }

            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(AnalyzeResponse.self, from: data).text
            case 401:
                throw BackendError.noAutorizado
            case 400:
                throw BackendError.tipoDesconocido
            case 429:
                let e = try? JSONDecoder().decode(QuotaError.self, from: data)
                throw BackendError.cuotaAgotada(
                    restantes: 0,
                    limite: e?.limit ?? 0,
                    renuevaEn: e?.resetsAt.flatMap(Self.parseFecha))
            default:
                throw BackendError.servidorCaido
            }
        }
    }

    // Cuotas restantes, sin gastar nada. La usan las pantallas que enseñan
    // "te quedan N rutinas" antes de que el usuario pulse.
    func quotas() async throws -> AllQuotas {
        try await withRetryOnUnauthorized { token in
            var request = URLRequest(url: BackendConfig.url("/v1/ai/quota"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.respuestaIlegible }
            if http.statusCode == 401 { throw BackendError.noAutorizado }
            guard http.statusCode == 200 else { throw BackendError.servidorCaido }
            return try JSONDecoder().decode(AllQuotas.self, from: data)
        }
    }

    // Un 401 significa que el token dejó de valer (dispositivo borrado en el
    // servidor, base de datos reiniciada). Se descarta y se reintenta UNA vez, lo
    // que registra de nuevo: si no, la app quedaría inutilizable para siempre.
    private func withRetryOnUnauthorized<T>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        let token = try await DeviceAuth.shared.token()
        do {
            return try await operation(token)
        } catch BackendError.noAutorizado {
            await DeviceAuth.shared.invalidate()
            let nuevo = try await DeviceAuth.shared.token()
            return try await operation(nuevo)
        }
    }

    static func parseFecha(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}
