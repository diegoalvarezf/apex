import Foundation
import WatchConnectivity

@MainActor
final class WatchDataStore: ObservableObject {
    static let shared = WatchDataStore()
    @Published var data = WatchDashboardData()
    private init() {}
}

final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()
    private override init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let raw = context["dash"] as? Data,
              let dash = try? JSONDecoder().decode(WatchDashboardData.self, from: raw) else { return }
        Task { @MainActor in
            WatchDataStore.shared.data = dash
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message["dash"] as? Data,
              let dash = try? JSONDecoder().decode(WatchDashboardData.self, from: raw) else { return }
        Task { @MainActor in
            WatchDataStore.shared.data = dash
        }
    }
}
