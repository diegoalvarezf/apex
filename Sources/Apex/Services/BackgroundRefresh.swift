import Foundation
import BackgroundTasks

// Despierta la app de vez en cuando para registrar las métricas del día.
//
// Sin esto, la foto diaria solo se guardaba al abrir Inicio, así que los días que no
// se abre la app quedaban sin histórico. Los datos están en HealthKit, en el
// dispositivo, así que no hay forma de calcularlos desde fuera: tiene que ejecutarse
// la app aunque sea un momento.
//
// iOS decide cuándo concede esas ejecuciones según el uso que se le da a la app, así
// que esto NO garantiza un registro diario: mejora la cobertura, no la asegura.
@MainActor
enum BackgroundRefresh {

    static let taskID = "com.diegoalvarezfrancos.apex.dailyrefresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in await handle(refreshTask) }
        }
    }

    // Se reprograma en cada ejecución: iOS solo mantiene una petición pendiente.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) async {
        schedule()

        let trabajo = Task { @MainActor () -> Bool in
            let healthKit = HealthKitManager()
            await healthKit.loadAll()
            // Sin red o sin token de Strava se registra igual lo de HealthKit: es
            // mejor una foto sin actividades que ninguna foto.
            return DailyMetricsRecorder.recordToday(healthKit: healthKit, activities: [])
        }

        // iOS puede cortar la ejecución en cualquier momento.
        task.expirationHandler = { trabajo.cancel() }

        let ok = await trabajo.value
        task.setTaskCompleted(success: ok)
    }
}
