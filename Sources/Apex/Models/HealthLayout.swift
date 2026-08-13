import Foundation
import SwiftUI

// Layout configurable de la pestaña Salud: orden de las secciones y qué métricas
// se muestran. Se persiste en UserDefaults.

enum HealthSectionID: String, CaseIterable, Codable, Identifiable {
    case bioAge, vitals, activity, body
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bioAge:   return "Edad Apex"
        case .vitals:   return "Métricas corporales"
        case .activity: return "Actividad"
        case .body:     return "Composición corporal"
        }
    }
    var icon: String {
        switch self {
        case .bioAge:   return "figure.walk.motion"
        case .vitals:   return "waveform.path.ecg"
        case .activity: return "figure.run"
        case .body:     return "figure.stand"
        }
    }
}

enum HealthMetricID: String, CaseIterable, Codable, Identifiable {
    // Métricas corporales
    case hrv, restingHR, vo2max, respiratory, spo2, wristTemp
    // Actividad
    case zone13, zone45, strength, steps, flights, daylight
    // Composición corporal
    case weight, bmi, bodyFat, leanMass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv:         return "HRV"
        case .restingHR:   return "FC en reposo"
        case .vo2max:      return "VO₂Max"
        case .respiratory: return "Frec. respiratoria"
        case .spo2:        return "Oxígeno en sangre"
        case .wristTemp:   return "Temp. muñeca"
        case .zone13:      return "Zona 1–3 / sem."
        case .zone45:      return "Zona 4–5 / sem."
        case .strength:    return "Fuerza / sem."
        case .steps:       return "Pasos"
        case .flights:     return "Pisos subidos"
        case .daylight:    return "Luz diurna"
        case .weight:      return "Peso"
        case .bmi:         return "IMC"
        case .bodyFat:     return "Grasa corporal"
        case .leanMass:    return "Masa magra"
        }
    }

    var section: HealthSectionID {
        switch self {
        case .hrv, .restingHR, .vo2max, .respiratory, .spo2, .wristTemp: return .vitals
        case .zone13, .zone45, .strength, .steps, .flights, .daylight:   return .activity
        case .weight, .bmi, .bodyFat, .leanMass:                          return .body
        }
    }
}

@MainActor
final class HealthLayoutStore: ObservableObject {
    static let shared = HealthLayoutStore()

    @Published var sectionOrder: [HealthSectionID] { didSet { persist() } }
    @Published var hidden: Set<HealthMetricID>     { didSet { persist() } }

    private let orderKey = "apex_health_section_order_v1"
    private let hiddenKey = "apex_health_hidden_metrics_v1"

    // La luz diurna solo la mide el Apple Watch → oculta por defecto
    private static let defaultHidden: Set<HealthMetricID> = [.daylight]

    private init() {
        let d = UserDefaults.standard
        if let raw = d.array(forKey: orderKey) as? [String] {
            let restored = raw.compactMap { HealthSectionID(rawValue: $0) }
            // Añade al final las secciones nuevas que no estuvieran guardadas
            sectionOrder = restored + HealthSectionID.allCases.filter { !restored.contains($0) }
        } else {
            sectionOrder = HealthSectionID.allCases
        }
        if let raw = d.array(forKey: hiddenKey) as? [String] {
            hidden = Set(raw.compactMap { HealthMetricID(rawValue: $0) })
        } else {
            hidden = Self.defaultHidden
        }
    }

    func isVisible(_ m: HealthMetricID) -> Bool { !hidden.contains(m) }

    func toggle(_ m: HealthMetricID) {
        if hidden.contains(m) { hidden.remove(m) } else { hidden.insert(m) }
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefaults() {
        sectionOrder = HealthSectionID.allCases
        hidden = Self.defaultHidden
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(sectionOrder.map(\.rawValue), forKey: orderKey)
        d.set(hidden.map(\.rawValue), forKey: hiddenKey)
    }
}
