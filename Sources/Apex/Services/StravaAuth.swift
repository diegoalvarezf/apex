import AuthenticationServices
import Foundation

enum StravaConfig {
    // Crea tu app en https://www.strava.com/settings/api
    static let clientID = "YOUR_STRAVA_CLIENT_ID"
    static let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
    static let redirectURI = "apex-strava://oauth"
    static let scopes = "read,activity:read_all,profile:read_all"
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
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: StravaConfig.clientID),
            .init(name: "redirect_uri", value: StravaConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: StravaConfig.scopes)
        ]

        authSession = ASWebAuthenticationSession(
            url: components.url!,
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
        guard let expires = UserDefaults.standard.object(forKey: expiresKey) as? Date,
              expires < Date().addingTimeInterval(300),
              let refresh = UserDefaults.standard.string(forKey: refreshKey)
        else { return }

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

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return }

        saveToken(json)
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
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let expires = UserDefaults.standard.object(forKey: expiresKey) as? Date,
              expires > Date()
        else { return }
        accessToken = token
        isAuthenticated = true
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
