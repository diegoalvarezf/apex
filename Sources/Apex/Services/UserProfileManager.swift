import Foundation
import HealthKit
import WidgetKit

// Acceso estático sin actor isolation — para usar en modelos/structs
enum UserProfile {
    static var weightKg: Double {
        let w = UserDefaults.standard.double(forKey: "user_weight")
        return w > 30 ? w : 70.0
    }
    static var maxHR: Int {
        let hr = UserDefaults.standard.integer(forKey: "user_max_hr")
        if hr > 100 { return hr }
        let age = UserDefaults.standard.integer(forKey: "user_age")
        return max(150, 220 - (age > 0 ? age : 30))
    }
    static var age: Int {
        let a = UserDefaults.standard.integer(forKey: "user_age")
        return a > 0 ? a : 30
    }
    // Sexo biológico (HealthKit) — coeficientes del TRIMP de Banister
    static var isMale: Bool {
        UserDefaults.standard.object(forKey: "user_is_male") as? Bool ?? true
    }
    // Última FC en reposo conocida (HealthKit); 55 como fallback
    static var restingHR: Double {
        let r = UserDefaults.standard.double(forKey: "user_resting_hr")
        return r > 20 ? r : 55.0
    }
    // FCmáx efectiva: custom del usuario > máxima registrada en 30 días (PeakWatch
    // usa "la FC más alta registrada en los últimos 30 días") > 220 − edad
    static var effectiveMaxHR: Double {
        let custom = UserDefaults.standard.integer(forKey: "user_max_hr")
        if custom > 100 { return Double(custom) }
        let observed = UserDefaults.standard.double(forKey: "user_observed_max_hr_30d")
        if observed >= 150 { return observed }
        return Double(max(150, 220 - age))
    }
}

// ObservableObject para vistas SwiftUI
@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published var weightKg: Double = UserProfile.weightKg
    @Published var maxHR: Int = UserProfile.maxHR
    @Published var age: Int = UserProfile.age
    @Published var customMaxHR: Int? = {
        let v = UserDefaults.standard.integer(forKey: "user_max_hr")
        return v > 100 ? v : nil
    }()

    // Llamar después de que HealthKitManager cargue sus datos
    func syncFromHealthKit(weightKg: Double?, chronologicalAge: Int?) {
        if let w = weightKg, w > 30 {
            self.weightKg = w
            UserDefaults.standard.set(w, forKey: "user_weight")
        }
        if let a = chronologicalAge, a > 0 {
            self.age = a
            UserDefaults.standard.set(a, forKey: "user_age")
            if customMaxHR == nil {
                self.maxHR = max(150, 220 - a)
            }
        }
    }

    func saveCustomMaxHR(_ hr: Int?) {
        customMaxHR = hr
        if let hr {
            UserDefaults.standard.set(hr, forKey: "user_max_hr")
            maxHR = hr
        } else {
            UserDefaults.standard.removeObject(forKey: "user_max_hr")
            maxHR = max(150, 220 - age)
        }
        UserDefaults.standard.synchronize()
    }

    // Escribe datos al AppGroup para el widget y recarga timelines
    func updateWidget(battery: Int, recovery: Int, label: String, effort: Int = 0, sleep: Int = 0) {
        let suite = UserDefaults(suiteName: "group.com.diegoalvarezfrancos.apex")
        suite?.set(battery, forKey: "widget_battery")
        suite?.set(recovery, forKey: "widget_recovery")
        suite?.set(label, forKey: "widget_label")
        suite?.set(effort, forKey: "widget_effort")
        suite?.set(sleep, forKey: "widget_sleep")
        suite?.set(Date(), forKey: "widget_updated")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
