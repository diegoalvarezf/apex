import Foundation

// Calculadoras de carga de entrenamiento — única fuente de verdad para toda la app.
//
// Fórmulas publicadas:
// - TRIMP de Banister (Banister 1991; Morton, Fitz-Clarke & Banister 1990):
//     TRIMP = t(min) · HRr · 0.64 · e^(1.92·HRr)   (hombres)
//     TRIMP = t(min) · HRr · 0.86 · e^(1.67·HRr)   (mujeres)
//     con HRr = (FCmedia − FCreposo) / (FCmáx − FCreposo)
// - TRIMP de Edwards (Edwards 1993, método de zonas sumadas):
//     TRIMP = Σ minutos en zona i × i, con zonas del 50-60%…90-100% de FCmáx
// - TSS (Coggan / TrainingPeaks):
//     TSS = (segundos · NP · IF) / (FTP · 3600) · 100, con IF = NP / FTP
//
// Nota de calibración: la única constante NO procedente de literatura es la
// conversión del TRIMP de Edwards diario a la escala 0-100 del tile "Esfuerzo"
// (EFFORT_SCALE). PeakWatch no publica su mapeo; aquí se define explícitamente.
enum TrainingMetrics {

    static let rideTypes: Set<String> = ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"]

    // MARK: - Banister TRIMP (carga por sesión, alimenta ATL/CTL)

    static func banisterTRIMP(minutes: Double, avgHR: Double, restingHR: Double, maxHR: Double, isMale: Bool) -> Double {
        guard minutes > 0, maxHR > restingHR else { return 0 }
        let hrr = max(0.0, min(1.0, (avgHR - restingHR) / (maxHR - restingHR)))
        let a = isMale ? 0.64 : 0.86
        let b = isMale ? 1.92 : 1.67
        return minutes * hrr * a * Foundation.exp(b * hrr)
    }

    // MARK: - TSS (ciclismo con potencia)

    static func tss(seconds: Double, normalizedPower: Double, ftp: Double) -> Double {
        guard seconds > 0, ftp > 0, normalizedPower > 0 else { return 0 }
        let intensity = normalizedPower / ftp
        return (seconds * normalizedPower * intensity) / (ftp * 3600.0) * 100.0
    }

    // FTP estimado = 95% de la mejor potencia normalizada (weighted_average_watts)
    // en salidas de ≥20 min del periodo cargado. Aproxima el test de 20 minutos
    // (FTP ≈ 0.95 × mejor potencia sostenida 20 min). Si no hay potencia → nil.
    static func estimateFTP(from activities: [StravaActivity]) -> Double? {
        let best = activities
            .filter { rideTypes.contains($0.sportType.lowercased()) && $0.movingTime >= 20 * 60 }
            .compactMap { act -> Double? in
                if let w = act.weightedAverageWatts { return Double(w) }
                return act.averageWatts
            }
            .max()
        guard let best, best > 0 else { return nil }
        return best * 0.95
    }

    // MARK: - Carga de una sesión (para ATL/CTL/ACWR)

    // TSS si es ciclismo con potencia y hay FTP; en caso contrario, Banister TRIMP.
    // Sin factores extra: la FC y la potencia ya reflejan el desnivel.
    static func sessionLoad(_ act: StravaActivity, ftp: Double?, restingHR: Double, maxHR: Double, isMale: Bool) -> Double {
        let np: Double? = act.weightedAverageWatts.map(Double.init) ?? act.averageWatts
        if rideTypes.contains(act.sportType.lowercased()),
           let ftp, ftp > 0, let np, np > 0 {
            return tss(seconds: Double(act.movingTime), normalizedPower: np, ftp: ftp)
        }
        let avgHR = act.averageHeartrate ?? fallbackAvgHR(sport: act.sportType, restingHR: restingHR, maxHR: maxHR)
        return banisterTRIMP(minutes: Double(act.movingTime) / 60.0,
                             avgHR: avgHR, restingHR: restingHR, maxHR: maxHR, isMale: isMale)
    }

    // FC media típica por deporte cuando la actividad no trae FC (fracción de la
    // reserva cardíaca). Heurística de fallback, no medida — se usa solo sin datos.
    static func fallbackAvgHR(sport: String, restingHR: Double, maxHR: Double) -> Double {
        let frac: Double
        switch sport.lowercased() {
        case "run", "trail_run", "virtualrun":         frac = 0.75
        case "ride", "virtualride", "ebikeride":       frac = 0.65
        case "swim":                                   frac = 0.70
        case "weighttraining", "crossfit", "workout":  frac = 0.55
        case "walk", "hike":                           frac = 0.40
        case "yoga", "pilates":                        frac = 0.30
        default:                                       frac = 0.60
        }
        return restingHR + frac * (maxHR - restingHR)
    }

    // MARK: - Estrés fisiológico (estilo Firstbeat: HRV + FC)

    // Nivel de estrés autonómico de BASE a partir del HRV (SDNN) frente al baseline
    // personal: HRV alto (parasimpático) → estrés bajo; HRV bajo (simpático) → alto.
    // A diferencia del %FC puro, tiene un SUELO en reposo (siempre hay algo de tono
    // autonómico), como el estrés de Firstbeat/Garmin — no cae a 0 al estar sentado.
    static func hrvBaseStress(todaySDNN: Double?, baseline: [Double]) -> Double {
        guard let sdnn = todaySDNN else { return 30 }
        if baseline.count >= 7 {
            let mean = baseline.reduce(0, +) / Double(baseline.count)
            let variance = baseline.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(baseline.count)
            let sd = max(sqrt(variance), 6.0)
            let z = (sdnn - mean) / sd
            return max(12.0, min(72.0, 35.0 - z * 14.0))
        }
        // Sin baseline: mapa absoluto suave (SDNN 76→~15, 40→30, 20→50)
        return max(12.0, min(60.0, 70.0 - sdnn))
    }

    // Estrés instantáneo = base autonómica (HRV) + empuje por actividad (FC sobre
    // reposo). Combina el tono de fondo con la demanda del momento.
    static func physiologicalStress(hr: Double, restingHR: Double, maxHR: Double, hrvBase: Double) -> Double {
        guard maxHR > restingHR else { return hrvBase }
        let hrr = max(0.0, min(1.0, (hr - restingHR) / (maxHR - restingHR)))
        return max(0.0, min(100.0, hrvBase + hrr * 70.0))
    }

    // MARK: - Esfuerzo diario

    // Carga cardiovascular de un día completo (TRIMP de Banister continuo):
    // suma las actividades Strava a cualquier intensidad + la FC de fondo de las
    // horas no cubiertas SOLO cuando está elevada (HRr > 0.20, para excluir el reposo/
    // estar sentado). El TRIMP de Edwards por zonas se reserva para el desglose visual.
    static func dailyEffortTRIMP(
        day: Date,
        activities: [StravaActivity],
        hourlyHR: [MetricSample],
        restingHR: Double,
        maxHR: Double,
        isMale: Bool
    ) -> Double {
        let cal = Calendar.current
        var total = 0.0
        var coveredHours: Set<Int> = []

        for act in activities where cal.isDate(act.startDate, inSameDayAs: day) {
            let minutes = Double(act.movingTime) / 60.0
            let hr = act.averageHeartrate ?? fallbackAvgHR(sport: act.sportType, restingHR: restingHR, maxHR: maxHR)
            total += banisterTRIMP(minutes: minutes, avgHR: hr, restingHR: restingHR, maxHR: maxHR, isMale: isMale)
            let startH = cal.component(.hour, from: act.startDate)
            let endH = min(23, startH + Int(ceil(minutes / 60.0)))
            if startH <= endH { for h in startH...endH { coveredHours.insert(h) } }
        }

        for s in hourlyHR where cal.isDate(s.date, inSameDayAs: day) {
            let hour = cal.component(.hour, from: s.date)
            guard !coveredHours.contains(hour) else { continue }
            let hrr = (s.value - restingHR) / (maxHR - restingHR)
            guard hrr > 0.20 else { continue }   // ignora reposo / estar sentado
            total += banisterTRIMP(minutes: 60, avgHR: s.value, restingHR: restingHR, maxHR: maxHR, isMale: isMale)
        }
        return total
    }

    // Curva saturante hacia 0-100 (calibración de producto documentada, no ciencia):
    // K=90 → día de descanso ≈ 10-20, día activo ligero ≈ 35-45, entreno duro ≈ 80-95.
    private static let EFFORT_K = 90.0

    static func effortScore(dailyTRIMP: Double) -> Int {
        guard dailyTRIMP > 0 else { return 0 }
        return Int((100.0 * (1.0 - Foundation.exp(-dailyTRIMP / EFFORT_K))).rounded())
    }

    // FCmáx efectiva estilo PeakWatch: la mayor FC observada en los datos
    // disponibles, con suelo en la FCmáx de perfil (custom / observada 30d / 220-edad).
    static func observedMaxHR(hourlyHR: [MetricSample]) -> Double {
        max(UserProfile.effectiveMaxHR, hourlyHR.map(\.value).max() ?? 0)
    }
}
