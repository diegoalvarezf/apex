import AuthenticationServices
import Foundation
import UIKit

enum StravaConfig {
    // Credenciales desde StravaSecrets.plist (local, en .gitignore). Ver
    // StravaSecrets.example.plist. Fallback al placeholder si el fichero no existe.
    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "StravaSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return dict
    }()

    static let clientID     = secrets["ClientID"]     ?? "YOUR_STRAVA_CLIENT_ID"
    static let clientSecret = secrets["ClientSecret"] ?? "YOUR_STRAVA_CLIENT_SECRET"
    static let redirectURI  = "apex-strava://localhost/oauth"
    static let scopes       = "read,activity:read_all,profile:read_all"
}

@MainActor
final class StravaAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var athlete: StravaAthlete?

    private let tokenKey = "strava_access_token"
    private let refreshKey = "strava_refresh_token"
    private let expiresKey = "strava_token_expires"
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        loadStoredToken()
    }

    func authorize() {
        let queryItems: [URLQueryItem] = [
            .init(name: "client_id", value: StravaConfig.clientID),
            .init(name: "redirect_uri", value: StravaConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: StravaConfig.scopes)
        ]

        // Intentar abrir la app de Strava directamente si está instalada
        var stravaAppComponents = URLComponents(string: "strava://oauth/mobile/authorize")!
        stravaAppComponents.queryItems = queryItems
        if let stravaAppURL = stravaAppComponents.url, UIApplication.shared.canOpenURL(stravaAppURL) {
            UIApplication.shared.open(stravaAppURL)
            return
        }

        // Fallback: navegador web si Strava no está instalada
        var webComponents = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        webComponents.queryItems = queryItems
        authSession = ASWebAuthenticationSession(
            url: webComponents.url!,
            callbackURLScheme: "apex-strava"
        ) { [weak self] callbackURL, error in
            guard let self, let url = callbackURL, error == nil else { return }
            self.handleCallback(url: url)
        }
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }

        Task { await exchangeCode(code) }
    }

    private func exchangeCode(_ code: String) async {
        guard let url = URL(string: "https://www.strava.com/oauth/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return }

        saveToken(json)
    }

    func refreshTokenIfNeeded() async {
        // Refrescar si el token expira en menos de 5 minutos o ya caducó
        let expires = UserDefaults.standard.object(forKey: expiresKey) as? Date ?? .distantPast
        guard expires < Date().addingTimeInterval(300),
              let refresh = UserDefaults.standard.string(forKey: refreshKey)
        else {
            // Token vigente — aseguramos que el atleta esté cargado
            if athlete == nil, let token = accessToken {
                athlete = try? await StravaAPI.shared.fetchAthlete(token: token)
            }
            return
        }

        guard let url = URL(string: "https://www.strava.com/oauth/token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 400/401 = refresh token revocado o inválido → forzar reconexión.
                // Otros códigos (5xx, rate limit) son transitorios: mantener sesión.
                if http.statusCode == 400 || http.statusCode == 401 { signOut() }
                return
            }
            let json = try JSONDecoder().decode(TokenResponse.self, from: data)
            saveToken(json)
        } catch {
            // Error de red transitorio: mantener la sesión, se reintenta al reabrir.
            return
        }
    }

    private func saveToken(_ token: TokenResponse) {
        UserDefaults.standard.set(token.accessToken, forKey: tokenKey)
        UserDefaults.standard.set(token.refreshToken, forKey: refreshKey)
        UserDefaults.standard.set(Date(timeIntervalSince1970: TimeInterval(token.expiresAt)), forKey: expiresKey)
        accessToken = token.accessToken
        isAuthenticated = true
        Task { athlete = try? await StravaAPI.shared.fetchAthlete(token: token.accessToken) }
    }

    private func loadStoredToken() {
        // Si hay refresh token guardado marcamos autenticado aunque el access haya caducado.
        // refreshTokenIfNeeded() se llamará al arrancar y renovará el access token.
        let hasRefresh = UserDefaults.standard.string(forKey: refreshKey) != nil
        guard let token = UserDefaults.standard.string(forKey: tokenKey), hasRefresh else { return }
        accessToken = token
        isAuthenticated = true
        // Si ya hay atleta en cache lo cargamos; se actualizará tras el refresh
        Task { await refreshTokenIfNeeded() }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: expiresKey)
        accessToken = nil
        isAuthenticated = false
        athlete = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    private struct TokenResponse: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }
}
