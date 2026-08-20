import SwiftUI
import Charts

struct HeartRateZonesView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager

    // Zonas por %FCmáx (modelo estándar de 5 zonas). FCmáx efectiva del perfil:
    // custom del usuario > máxima registrada 30 días > 220−edad.
    var zones: [HeartRateZone] {
        computeZones(maxHR: UserProfile.effectiveMaxHR, activities: dashVM.activities)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Distribución total
                VStack(alignment: .leading, spacing: 12) {
                    Text("Distribución de zonas").font(.headline)
                    Text("Basado en las últimas actividades de Strava")
                        .font(.caption).foregroundColor(.secondary)

                    ForEach(zones) { zone in
                        ZoneBar(zone: zone, totalTime: zones.map(\.timeInZone).reduce(0, +))
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Referencia de zonas
                VStack(alignment: .leading, spacing: 0) {
                    Text("Referencia de zonas").font(.headline)
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                    ForEach(zones) { zone in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Circle().fill(zone.color).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Zona \(zone.zone) — \(zone.name)").font(.subheadline).fontWeight(.medium)
                                    Text("\(zone.minBPM)–\(zone.maxBPM) bpm").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(zone.formattedTime).font(.caption).fontWeight(.medium).foregroundColor(zone.color)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            if zone.zone < 5 { Divider().padding(.leading, 38) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Explicación
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entrenamiento por zonas").font(.headline)
                    Text("Un entrenamiento equilibrado sigue la distribución 80/20: el 80% del tiempo en Zona 1-2 (aeróbico suave) y el 20% restante en Zona 4-5 (alta intensidad). Evita pasar demasiado tiempo en Zona 3.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Zonas de entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func computeZones(maxHR: Double, activities: [StravaActivity]) -> [HeartRateZone] {
        let names = ["Recuperación", "Aeróbico base", "Aeróbico umbral", "Anaeróbico", "Máximo"]
        let pcts: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.7), (0.7, 0.8), (0.8, 0.9), (0.9, 1.0)]
        var timeInZone = [Double](repeating: 0, count: 5)

        // Aproximación: sin streams de FC de Strava, se imputa toda la duración de
        // cada actividad a la zona de su FC media. Con datos de stream sería exacto.
        for act in activities {
            guard let avgHR = act.averageHeartrate else { continue }
            let z = zoneIndex(hr: avgHR, maxHR: maxHR, pcts: pcts)
            if z >= 0 { timeInZone[z] += Double(act.movingTime) }
        }

        return (0..<5).map { i in
            HeartRateZone(
                zone: i + 1, name: names[i],
                minBPM: Int(maxHR * pcts[i].0), maxBPM: Int(maxHR * pcts[i].1),
                timeInZone: timeInZone[i]
            )
        }
    }

    private func zoneIndex(hr: Double, maxHR: Double, pcts: [(Double, Double)]) -> Int {
        for (i, (lo, hi)) in pcts.enumerated() {
            if hr >= maxHR * lo && hr < maxHR * hi { return i }
        }
        return hr >= maxHR * 0.9 ? 4 : 0
    }
}

private struct ZoneBar: View {
    let zone: HeartRateZone
    let totalTime: TimeInterval

    var pct: Double { totalTime > 0 ? zone.timeInZone / totalTime : 0 }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Circle().fill(zone.color).frame(width: 8, height: 8)
                Text("Z\(zone.zone)").font(.caption2).fontWeight(.semibold).foregroundColor(zone.color)
                Spacer()
                Text(String(format: "%.0f%%", pct * 100)).font(.caption2).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.06)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(zone.color)
                        .frame(width: geo.size.width * CGFloat(pct), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}
