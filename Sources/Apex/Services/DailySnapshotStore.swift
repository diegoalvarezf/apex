import Foundation

// Lo que la app calculó realmente cada día.
//
// Sin esto, mirar un día pasado obligaba a recalcularlo con los parámetros de HOY
// (FC en reposo y FCmáx actuales), y el resultado podía no coincidir con lo que el
// usuario vio aquel día. En una app cuyo criterio es no presentar nada que no sea
// verificable, eso es inaceptable: el histórico tiene que ser el dato que hubo, no
// una reconstrucción aproximada.
//
// Se guarda una foto por día con los valores y la curva horaria de batería tal y
// como se calcularon, junto con los parámetros usados, para poder auditar después
// de dónde salió cada número.
struct DailySnapshot: Codable, Equatable {
    let date: Date
    var battery: Int?
    var recovery: Int?
    var stress: Int?
    var effort: Int?
    // Curva horaria de Body Battery de ese día, tal cual se calculó.
    var batteryCurve: [HourValue] = []
    // Parámetros con los que se calculó, para poder explicar el número más adelante.
    var restingHR: Double?
    var maxHR: Double?
    var savedAt: Date = Date()

    struct HourValue: Codable, Equatable {
        let date: Date
        let value: Double
    }

    var isEmpty: Bool {
        battery == nil && recovery == nil && stress == nil && effort == nil
    }
}

@MainActor
final class DailySnapshotStore {
    static let shared = DailySnapshotStore()

    private let storageKey = "apex_daily_snapshots_v1"
    private let cal = Calendar.current
    // 90 días: más que el calendario necesita, y sigue siendo poco espacio.
    private let diasAConservar = 90

    private init() {}

    private var cache: [String: DailySnapshot]?

    private func load() -> [String: DailySnapshot] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let dict = try? JSONDecoder().decode([String: DailySnapshot].self, from: data)
        else {
            cache = [:]
            return [:]
        }
        cache = dict
        return dict
    }

    func snapshot(for day: Date) -> DailySnapshot? {
        load()[key(day)]
    }

    func all() -> [Date: DailySnapshot] {
        var out: [Date: DailySnapshot] = [:]
        for (k, v) in load() {
            if let d = parse(k) { out[d] = v }
        }
        return out
    }

    // Guarda lo calculado para un día. Solo sobrescribe los campos que llegan con
    // valor, porque el dashboard va completando el día a medida que cargan las
    // fuentes (HealthKit primero, Strava después).
    func save(
        day: Date,
        battery: Int? = nil,
        recovery: Int? = nil,
        stress: Int? = nil,
        effort: Int? = nil,
        batteryCurve: [MetricSample]? = nil,
        restingHR: Double? = nil,
        maxHR: Double? = nil
    ) {
        var dict = load()
        let k = key(day)
        var snap = dict[k] ?? DailySnapshot(date: cal.startOfDay(for: day))

        if let battery { snap.battery = battery }
        if let recovery { snap.recovery = recovery }
        if let stress { snap.stress = stress }
        if let effort { snap.effort = effort }
        if let batteryCurve, !batteryCurve.isEmpty {
            snap.batteryCurve = batteryCurve.map { .init(date: $0.date, value: $0.value) }
        }
        if let restingHR { snap.restingHR = restingHR }
        if let maxHR { snap.maxHR = maxHR }
        snap.savedAt = Date()

        dict[k] = snap
        // Poda: no interesa arrastrar histórico indefinido en UserDefaults.
        if let corte = cal.date(byAdding: .day, value: -diasAConservar, to: Date()) {
            dict = dict.filter { parse($0.key).map { $0 >= corte } ?? false }
        }
        cache = dict
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Claves

    private func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: cal.startOfDay(for: date))
    }

    private func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { cal.startOfDay(for: $0) }
    }
}
