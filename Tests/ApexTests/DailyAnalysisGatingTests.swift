import Testing
import Foundation
@testable import Apex

// Los análisis del día (alertas, insights, resumen semanal) son de 1×/día o 1×/semana
// y se cachean. Eso los hace baratos, y también implica que escribirlos sobre datos a
// medio cargar deja la foto equivocada fija hasta el día siguiente.
//
// Pasó de verdad: al abrir la app por la mañana, las alertas decían "sin entrenar"
// con un entrenamiento del día anterior registrado. Strava tarda —renueva el token y
// va por la red— mientras que HealthKit responde al instante desde el dispositivo, y
// el análisis salía con la lista de actividades todavía vacía.
@MainActor
struct DailyAnalysisGatingTests {

    // Con recuperación calculada, que es lo que hay al abrir la app por la mañana:
    // HealthKit ya ha respondido y Strava no. Sin esto el análisis se cortaría por
    // falta de datos y el test pasaría aunque el fallo siguiera ahí.
    private func healthConDatos() -> HealthKitManager {
        let health = HealthKitManager()
        health.recoveryScore = RecoveryScore(
            value: 72, sleepScore: 70, hrvScore: 75, trainingLoadScore: 70, restingHRScore: 72)
        return health
    }

    // Almacén propio por test: el del dispositivo guarda los análisis cacheados, y
    // uno escrito por otra prueba haría pasar esta sin que el fallo esté arreglado.
    private func nuevoVM() -> DashboardViewModel {
        DashboardViewModel(defaults: UserDefaults(suiteName: "apex.tests.\(UUID())")!)
    }

    private func conActividadDeAyer() -> DashboardViewModel {
        let vm = nuevoVM()
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        vm.activities = [StravaActivityFixture.make(startDate: ayer)]
        return vm
    }

    // Lo que fallaba: el análisis arrancaba antes de que Strava contestara.
    @Test func noSeAnalizaAntesDeQueStravaConteste() async {
        let vm = nuevoVM()
        #expect(vm.activitiesSettled == false)

        await vm.loadAlertsIfStale(health: healthConDatos())

        // Sin marcar, no se ha escrito nada: ni alertas ni fecha que cachear.
        #expect(vm.aiAlerts.isEmpty)
        #expect(vm.aiAlertsAt == nil)
    }

    // Y forzarlo a mano tampoco puede saltarse la espera: el botón de recargar
    // volvería a dejar cacheada la misma foto vacía.
    @Test func niSiquieraForzandoALaBrava() async {
        let vm = nuevoVM()
        await vm.reloadAlerts(health: healthConDatos())
        #expect(vm.aiAlertsAt == nil)
    }

    // La marca se pone aunque no haya Strava conectado. Si dependiera de que la
    // carga fuera bien, quien no lo use no tendría análisis nunca.
    @Test func sinStravaTambienSeDesbloquea() {
        let vm = nuevoVM()
        vm.markActivitiesSettled()
        #expect(vm.activitiesSettled)
    }

    // El resumen semanal y los insights comparten el mismo momento de arranque y el
    // mismo caché, así que comparten la espera.
    @Test func elResumenSemanalTambienEspera() async {
        let vm = conActividadDeAyer()
        await vm.loadWeeklySummaryIfStale(health: healthConDatos())
        #expect(vm.weeklySummaryAt == nil)
    }

    // La regla local que dio el aviso equivocado: con la actividad de ayer cargada
    // no debe aparecer ninguna racha sin entrenar.
    @Test func conLaActividadDeAyerNoHayRachaSinEntrenar() {
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tips = SmartTipsEngine.compute(
            recovery: nil, sleep: nil, sleepHistory: [], hourlyHR: [],
            rhr: nil, rhrHistory: [], hrvHistory: [],
            activities: [StravaActivityFixture.make(startDate: ayer)]
        )
        #expect(!tips.contains { $0.title.contains("Sin actividad") })
    }

    // Y la lista va en orden cronológico —la más reciente al final—, que es de donde
    // sale ese cálculo: al revés, el aviso se mediría contra la actividad más vieja.
    @Test func laRachaSeMideContraLaActividadMasReciente() {
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let haceUnMes = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let tips = SmartTipsEngine.compute(
            recovery: nil, sleep: nil, sleepHistory: [], hourlyHR: [],
            rhr: nil, rhrHistory: [], hrvHistory: [],
            activities: [
                StravaActivityFixture.make(startDate: haceUnMes),
                StravaActivityFixture.make(startDate: ayer),
            ]
        )
        #expect(!tips.contains { $0.title.contains("Sin actividad") })
    }
}
