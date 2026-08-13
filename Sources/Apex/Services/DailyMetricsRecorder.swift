import Foundation

// Calcula y guarda las métricas del día.
//
// Vivía dentro de la vista del dashboard, así que solo ocurría al abrir Inicio: los
// días que el usuario no abría la app quedaban sin registro. Al extraerlo aquí puede
// ejecutarlo también la tarea en segundo plano, que no tiene interfaz.
//
// Es la única función que escribe la foto del día y el widget, para que ambos
// caminos —abrir la app o despertarse en segundo plano— produzcan lo mismo.
@MainActor
enum DailyMetricsRecorder {

    @discardableResult
    static func recordToday(healthKit: HealthKitManager, activities: [StravaActivity]) -> Bool {
        guard let score = healthKit.recoveryScore else { return false }

        let rhr = healthKit.todaySummary?.restingHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: healthKit.recentHourlyHR)
        let hrvSamples = healthKit.hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }

        let curva = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: score,
            sleepHistory: healthKit.sleepHistory,
            hourlyHR: healthKit.recentHourlyHR,
            restingHR: healthKit.todaySummary?.restingHR,
            recoveryHistory: healthKit.recoveryHistory,
            activities: activities,
            hrvHistory: hrvSamples)
        let battery = Int(curva.last?.value ?? Double(score.value))

        let effort = TrainingMetrics.effortScore(dailyTRIMP: TrainingMetrics.dailyEffortTRIMP(
            day: Date(), activities: activities, hourlyHR: healthKit.recentHourlyHR,
            restingHR: rhr, maxHR: maxHR, isMale: UserProfile.isMale))

        UserProfileManager.shared.updateWidget(
            battery: battery,
            recovery: score.value,
            label: score.label,
            effort: effort,
            sleep: healthKit.sleepHistory.last?.score ?? 0)

        DailySnapshotStore.shared.save(
            day: Date(),
            battery: battery,
            recovery: score.value,
            stress: stressHoy(healthKit: healthKit, restingHR: rhr, maxHR: maxHR),
            effort: effort,
            batteryCurve: curva,
            restingHR: rhr,
            maxHR: maxHR)
        return true
    }

    // Media del estrés horario de hoy, con la misma fórmula que el tile del inicio.
    private static func stressHoy(healthKit: HealthKitManager, restingHR: Double, maxHR: Double) -> Int? {
        let hoy = Calendar.current.startOfDay(for: Date())
        let muestras = healthKit.recentHourlyHR.filter { $0.date >= hoy }
        guard !muestras.isEmpty else { return nil }

        let hrv = healthKit.hrvHistory
        let base = TrainingMetrics.hrvBaseStress(
            todaySDNN: hrv.last?.sdnn,
            baseline: hrv.dropLast().map(\.sdnn))
        let valores = muestras.map {
            TrainingMetrics.physiologicalStress(hr: $0.value, restingHR: restingHR, maxHR: maxHR, hrvBase: base)
        }
        return Int((valores.reduce(0, +) / Double(valores.count)).rounded())
    }
}
