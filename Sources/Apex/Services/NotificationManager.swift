import UserNotifications
import Foundation

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var isAuthorized = false

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isAuthorized = granted
    }

    func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // Programa notificación diaria a las 8:30am con mensaje personalizado
    func scheduleDailyRecovery(recovery: Int, highLoadDaysStreak: Int) {
        guard isAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["apex_daily_recovery"])

        let content = UNMutableNotificationContent()
        content.title = "Apex"
        content.sound = .default

        if highLoadDaysStreak >= 3 {
            content.body = "⚠️ Llevas \(highLoadDaysStreak) días seguidos entrenando fuerte. Hoy descansa o entrena suave."
        } else if recovery >= 80 {
            content.body = "💪 Recuperación excelente (\(recovery)%). Día ideal para entrenar al máximo."
        } else if recovery >= 65 {
            content.body = "✅ Recuperación buena (\(recovery)%). Sesión moderada recomendada."
        } else if recovery >= 45 {
            content.body = "😐 Recuperación moderada (\(recovery)%). Carga ligera hoy."
        } else {
            content.body = "🛌 Recuperación baja (\(recovery)%). Tu cuerpo pide descanso."
        }

        var components = DateComponents()
        components.hour = 8
        components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "apex_daily_recovery", content: content, trigger: trigger)
        center.add(request)
    }

    // Recordatorio semanal: domingo 20:00. El resumen IA se genera al abrir la app,
    // así que el aviso invita a abrirla (no afirma tener nada "listo" que no exista).
    func scheduleWeeklySummary() {
        guard isAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["apex_weekly_summary"])

        let content = UNMutableNotificationContent()
        content.title = "Apex · Resumen semanal"
        content.body = "🗓️ Ábreme para ver cómo ha ido tu semana de entreno y en qué enfocarte la próxima."
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1   // domingo
        components.hour = 20
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "apex_weekly_summary", content: content, trigger: trigger)
        center.add(request)
    }
}
