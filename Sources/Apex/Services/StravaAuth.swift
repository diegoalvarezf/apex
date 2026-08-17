import AuthenticationServices
import Foundation
import UIKit

enum StravaConfig {
    // El client_id NO es secreto: viaja en la URL de autorización, a la vista de
    // cualquiera, y Strava lo trata como público. Por eso puede estar aquí.
    //
    // El client_secret, en cambio, ya no está en la app: vive en el backend, que
    // es quien canjea y refresca los tokens. Era la vulnerabilidad conocida del
    // proyecto, porque el OAuth de Strava lo exige y no admite PKCE, así que
    // dentro del binario no había forma de protegerlo.
    static let clientID     = "259817"
    static let redirectURI  = "apex-strava://localhost/oauth"
    static let scopes       = "read,activity:read_all,profile:read_all"
}

@MainActor
final class StravaAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var athlete: StravaAthlete?
    // Último error del canje. Antes se fallaba en silencio: el usuario volvía de
    // Strava, seguía viendo "Conectado" porque el token viejo continuaba ahí, y no
    // había forma de saber que la reconexión no había servido de nada.
    @Published var connectError: String?

    // Los dos tokens son credenciales: van al Keychain, no a UserDefaults. La fecha
    // de caducidad no lo es y se queda donde estaba.
    private let tokenAccount = "strava-access-token"
    private let refreshAccount = "strava-refresh-token"
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
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)

        // Strava puede volver sin código: si el usuario deniega el permiso manda
        // `error=access_denied`. Antes se salía en silencio en ambos casos y la
        // reconexión fallida no se distinguía de una correcta.
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            connectError = error == "access_denied"
                ? "No has autorizado el acceso en Strava."
                : "Strava devolvió un error: \(error)"
            return
        }

        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            connectError = "Strava volvió sin código de autorización."
            return
        }

        Task { await exchangeCode(code) }
    }

    // El canje pasa por el backend porque exige el client_secret: el OAuth de
    // Strava no admite PKCE, así que dentro de la app ese secreto viajaba en el
    // binario y cualquiera podía sacarlo del .ipa. Ahora vive solo en el servidor.
    private func exchangeCode(_ code: String) async {
        connectError = nil
        do {
            saveToken(try await BackendClient.shared.stravaExchange(code: code))
        } catch {
            connectError = error.localizedDescription
        }
    }

    // Refresco en curso, para no lanzar dos a la vez.
    //
    // Al abrir la app hay dos llamadas casi simultáneas: la que dispara el propio
    // arranque de StravaAuthManager (loadStoredToken) y la del `.task` de
    // MainTabView. Sin coalescer, las dos leen del Keychain el MISMO refresh
    // token —ninguna ha terminado todavía de renovarlo— y las dos se lo mandan a
    // Strava. Strava rota el refresh token en cada uso: la segunda petición llega
    // con uno que la primera ya dejó caducado, Strava la rechaza con un 400, y ese
    // rechazo se trataba como "hay que reconectar" —borrando del Keychain el par
    // que la primera petición ACABABA de guardar bien—. Así es como una mañana
    // cualquiera Apex parecía desconectado sin haberlo estado nunca. Mismo
    // problema, mismo remedio que ya tiene DeviceAuth para el registro.
    private var refreshEnCurso: Task<Void, Never>?

    func refreshTokenIfNeeded() async {
        if let enCurso = refreshEnCurso {
            return await enCurso.value
        }
        let tarea = Task { await self.doRefreshTokenIfNeeded() }
        refreshEnCurso = tarea
        await tarea.value
        refreshEnCurso = nil
    }

    private func doRefreshTokenIfNeeded() async {
        // Refrescar si el token expira en menos de 5 minutos o ya caducó
        let expires = UserDefaults.standard.object(forKey: expiresKey) as? Date ?? .distantPast
        guard expires < Date().addingTimeInterval(300),
              let refresh = Keychain.read(refreshAccount)
        else {
            // Token vigente — aseguramos que el atleta esté cargado
            if athlete == nil, let token = accessToken {
                athlete = try? await StravaAPI.shared.fetchAthlete(token: token)
            }
            return
        }

        do {
            let json = try await BackendClient.shared.stravaRefresh(refreshToken: refresh)
            saveToken(json)
        } catch BackendError.stravaRechazado {
            // El refresh token está revocado o caducado: hay que reconectar.
            signOut()
        } catch {
            // Red o servidor caído: la sesión se mantiene y se reintenta al
            // reabrir. Cerrarla aquí obligaría a reconectar Strava cada vez que
            // hubiera un corte pasajero.
            return
        }
    }

    private func saveToken(_ token: TokenResponse) {
        Keychain.save(token.accessToken, account: tokenAccount)
        Keychain.save(token.refreshToken, account: refreshAccount)
        UserDefaults.standard.set(Date(timeIntervalSince1970: TimeInterval(token.expiresAt)), forKey: expiresKey)
        accessToken = token.accessToken
        isAuthenticated = true
        Task { athlete = try? await StravaAPI.shared.fetchAthlete(token: token.accessToken) }
    }

    private func loadStoredToken() {
        // Si hay refresh token guardado marcamos autenticado aunque el access haya caducado.
        // refreshTokenIfNeeded() se llamará al arrancar y renovará el access token.
        // Versiones anteriores los guardaban en UserDefaults: se trasladan al
        // Keychain la primera vez, para no obligar a reconectar Strava.
        Keychain.migrateFromUserDefaults(key: "strava_access_token", account: tokenAccount)
        Keychain.migrateFromUserDefaults(key: "strava_refresh_token", account: refreshAccount)

        let hasRefresh = Keychain.read(refreshAccount) != nil
        guard let token = Keychain.read(tokenAccount), hasRefresh else { return }
        accessToken = token
        isAuthenticated = true
        // Si ya hay atleta en cache lo cargamos; se actualizará tras el refresh
        Task { await refreshTokenIfNeeded() }
    }

    func signOut() {
        Keychain.delete(tokenAccount)
        Keychain.delete(refreshAccount)
        UserDefaults.standard.removeObject(forKey: expiresKey)
        accessToken = nil
        isAuthenticated = false
        athlete = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    struct TokenResponse: Codable {
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
