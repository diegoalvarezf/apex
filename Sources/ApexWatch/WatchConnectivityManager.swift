import Foundation
import WatchConnectivity

@MainActor
final class WatchDataStore: ObservableObject {
    static let shared = WatchDataStore()

    @Published var data = WatchDashboardData()

    // El reloj solo recibe datos cuando el iPhone los manda. Si no se guardaran,
    // cada vez que se cierra la app se volvería a "--" hasta la siguiente
    // sincronización, que puede tardar. Se conserva la última recibida.
    private let storageKey = "apex_watch_last_dash"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(WatchDashboardData.self, from: raw) {
            data = saved
        }
    }

    func update(_ nueva: WatchDashboardData) {
        data = nueva
        if let encoded = try? JSONEncoder().encode(nueva) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()
    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // El contexto que el iPhone dejó puesto sigue disponible en la sesión, pero
    // didReceiveApplicationContext solo avisa de los NUEVOS. Sin leerlo al arrancar,
    // abrir la app del reloj mostraba "--" aunque el teléfono ya hubiera enviado.
    fileprivate func applyPendingContext(_ session: WCSession) {
        decodeAndStore(session.receivedApplicationContext)
    }

    fileprivate func decodeAndStore(_ payload: [String: Any]) {
        guard let raw = payload["dash"] as? Data,
              let dash = try? JSONDecoder().decode(WatchDashboardData.self, from: raw) else { return }
        Task { @MainActor in
            WatchDataStore.shared.update(dash)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        applyPendingContext(session)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        decodeAndStore(context)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        decodeAndStore(message)
    }
}
