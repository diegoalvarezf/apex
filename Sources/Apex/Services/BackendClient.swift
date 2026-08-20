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
    // Strava rechazó el canje o el refresh: el código o el refresh token ya no
    // valen. Se distingue de un fallo de red porque obliga a reconectar.
    case stravaRechazado
    case codigoNoValido
    case codigoYaUsado
    // El servidor frena los intentos fallidos de canje para que nadie pueda ir
    // probando códigos: son palabras adivinables, no cadenas aleatorias.
    case demasiadosIntentos

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
        case .stravaRechazado:
            return "Strava ha rechazado la conexión. Vuelve a conectarla."
        case .codigoNoValido:
            return "Ese código no existe. Revisa que esté bien escrito."
        case .codigoYaUsado:
            return "Ese código ya se ha usado en otro dispositivo."
        case .demasiadosIntentos:
            return "Demasiados intentos fallidos. Inténtalo mañana."
        }
    }
}

// Los análisis que el servidor sabe hacer. Debe coincidir con el catálogo de
// `backend/src/services/catalog.ts`: si aquí se pide uno que allí no existe, el
// servidor responde 400 en vez de gastar tokens.
enum AnalysisKind: String {
    case insights
    case alerts
    case weekly
    case recovery
    case stress
    case effort
    case sleep
    case run
    case routineDay
    case exerciseProgress
    case routineParse
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

    // Chat del coach. Endpoint propio porque manda la conversación entera, no un
    // bloque de datos.
    func chat(messages: [[String: String]], context: String) async throws -> String {
        try await withRetryOnUnauthorized { token in
            var request = URLRequest(url: BackendConfig.url("/v1/ai/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 60
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["messages": messages, "context": context])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.respuestaIlegible }

            switch http.statusCode {
            case 200:
                struct R: Decodable { let text: String }
                return try JSONDecoder().decode(R.self, from: data).text
            case 401: throw BackendError.noAutorizado
            case 400: throw BackendError.respuestaIlegible
            case 429:
                let e = try? JSONDecoder().decode(QuotaError.self, from: data)
                throw BackendError.cuotaAgotada(
                    restantes: 0, limite: e?.limit ?? 0,
                    renuevaEn: e?.resetsAt.flatMap(Self.parseFecha))
            default: throw BackendError.servidorCaido
            }
        }
    }

    // MARK: - Apex Pro

    struct ProStatus: Decodable {
        let isPro: Bool
        let expiresAt: String?
    }

    // Canjea un código de activación. Mientras no haya cuenta de desarrollador de
    // pago no hay compras dentro de la app, así que Pro se concede así.
    @discardableResult
    func redeemPro(code: String) async throws -> ProStatus {
        try await withRetryOnUnauthorized { token in
            var request = URLRequest(url: BackendConfig.url("/v1/pro/redeem"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.respuestaIlegible }

            switch http.statusCode {
            case 200: return try JSONDecoder().decode(ProStatus.self, from: data)
            case 401: throw BackendError.noAutorizado
            case 404: throw BackendError.codigoNoValido
            case 409: throw BackendError.codigoYaUsado
            case 429: throw BackendError.demasiadosIntentos
            case 400: throw BackendError.codigoNoValido
            default:  throw BackendError.servidorCaido
            }
        }
    }

    // MARK: - Strava

    // El servidor pone el client_secret y devuelve solo lo que la app necesita.
    // Los tokens de Strava NO se guardan en el servidor: los custodia la app en su
    // Keychain, para que este servicio no se convierta en un depósito de
    // credenciales de terceros.
    func stravaExchange(code: String) async throws -> StravaAuthManager.TokenResponse {
        try await stravaCall(path: "/v1/strava/exchange", body: ["code": code])
    }

    func stravaRefresh(refreshToken: String) async throws -> StravaAuthManager.TokenResponse {
        try await stravaCall(path: "/v1/strava/refresh", body: ["refreshToken": refreshToken])
    }

    private struct StravaTokens: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
    }

    private func stravaCall(
        path: String, body: [String: String]
    ) async throws -> StravaAuthManager.TokenResponse {
        try await withRetryOnUnauthorized { token in
            var request = URLRequest(url: BackendConfig.url(path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.respuestaIlegible }

            switch http.statusCode {
            case 200:
                let t = try JSONDecoder().decode(StravaTokens.self, from: data)
                return StravaAuthManager.TokenResponse(
                    accessToken: t.accessToken,
                    refreshToken: t.refreshToken,
                    expiresAt: t.expiresAt)
            case 401: throw BackendError.noAutorizado
            case 400: throw BackendError.stravaRechazado
            default: throw BackendError.servidorCaido
            }
        }
    }

    // MARK: - Cuotas

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
