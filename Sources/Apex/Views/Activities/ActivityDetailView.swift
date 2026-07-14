import SwiftUI
import MapKit

struct ActivityDetailView: View {
    let activity: StravaActivity
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var stravaAuth: StravaAuthManager

    // Detalle completo de Strava (incluye `calories` reales, que NO vienen en la
    // lista). Mientras carga se usa el resumen; al llegar se prefiere el detalle.
    @State private var detailed: StravaActivity?
    private var act: StravaActivity { detailed ?? activity }

    private var isRunningActivity: Bool {
        ["run", "trail_run", "virtualrun"].contains(act.sportType.lowercased())
    }
    private var isCyclingActivity: Bool {
        ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"].contains(act.sportType.lowercased())
    }

    private var recentSameSportActivities: [StravaActivity] {
        Array(dashVM.activities.filter {
            $0.id != act.id &&
            $0.sportType.lowercased() == act.sportType.lowercased()
        }.prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityHeaderCard(activity: act)
                    .padding(.horizontal)

                // Mapa de ruta (si hay polyline)
                if let polyline = act.summaryPolyline, !polyline.isEmpty {
                    RouteMapCard(polyline: polyline, sportType: act.sportType)
                        .padding(.horizontal)
                }

                StatsGrid(activity: act)
                    .padding(.horizontal)

                if let hr = act.averageHeartrate {
                    HeartRateCard(avg: hr, max: act.maxHeartrate)
                        .padding(.horizontal)
                }

                // Análisis IA de la sesión (lee la curva real de FC/ritmo/potencia de Strava)
                if (isRunningActivity || isCyclingActivity) && (act.averageHeartrate != nil || act.averageWatts != nil) {
                    ActivityAIAnalysisCard(activity: act)
                        .padding(.horizontal)
                }

                // Economía de carrera (cálculo fijo) — solo tiene sentido en carrera
                // continua; en intervalos el promedio engaña, así que se omite.
                if isRunningActivity && act.averageHeartrate != nil && !act.isStructuredWorkout {
                    RunningEconomyCard(activity: act, recentRuns: recentSameSportActivities)
                        .padding(.horizontal)
                }

                if let watts = act.averageWatts {
                    PowerCard(avg: watts, weighted: act.weightedAverageWatts, kj: act.kilojoules)
                        .padding(.horizontal)
                }

                if let sufferScore = act.sufferScore {
                    SufferScoreCard(score: sufferScore)
                        .padding(.horizontal)
                }
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(act.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard detailed == nil, let token = stravaAuth.accessToken else { return }
            detailed = try? await StravaAPI.shared.fetchActivity(id: activity.id, token: token)
        }
    }
}

// MARK: - Running Economy Card

private struct RunningEconomyCard: View {
    let activity: StravaActivity
    let recentRuns: [StravaActivity]

    private var avgPaceSecondsPerKm: Double {
        guard activity.distance > 0 else { return 0 }
        return Double(activity.movingTime) / (activity.distance / 1000)
    }

    private var historicalAvgPace: Double? {
        let validRuns = recentRuns.filter { $0.distance > 0 }
        guard !validRuns.isEmpty else { return nil }
        let paces = validRuns.map { Double($0.movingTime) / ($0.distance / 1000) }
        return paces.reduce(0, +) / Double(paces.count)
    }

    private var historicalAvgHR: Double? {
        let hrs = recentRuns.compactMap { $0.averageHeartrate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / Double(hrs.count)
    }

    // Aerobic decoupling: (maxHR - avgHR) / avgHR * 100
    // Only meaningful for sessions > 45 min
    private var aerobicDecoupling: Double? {
        guard let maxHR = activity.maxHeartrate,
              let avgHR = activity.averageHeartrate,
              avgHR > 0,
              activity.movingTime > 45 * 60 else { return nil }
        return (maxHR - avgHR) / avgHR * 100
    }

    // HR × pace ratio trend: lower = more economical
    private var hrPaceRatioTrend: String? {
        guard let currentHR = activity.averageHeartrate, activity.distance > 0 else { return nil }
        let currentRatio = currentHR * avgPaceSecondsPerKm

        let validRuns = recentRuns.filter { $0.averageHeartrate != nil && $0.distance > 0 }
        let last5 = Array(validRuns.prefix(5))
        guard last5.count >= 3 else { return nil }

        let ratios = last5.map { run -> Double in
            let pace = Double(run.movingTime) / (run.distance / 1000)
            return run.averageHeartrate! * pace
        }
        let avgRecent = ratios.reduce(0, +) / Double(ratios.count)

        if currentRatio < avgRecent * 0.98 { return "up" }
        if currentRatio > avgRecent * 1.02 { return "down" }
        return "flat"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.run.circle.fill").foregroundColor(.orange)
                Text("Economía de carrera").font(.headline)
            }

            Divider()

            // Pace vs HR comparison
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Ritmo").font(.caption2).foregroundColor(.secondary)
                    Text(activity.formattedPace)
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                    if let histPace = historicalAvgPace, avgPaceSecondsPerKm > 0 {
                        let diff = avgPaceSecondsPerKm - histPace
                        Text(diff < -5 ? "Mas rapido" : diff > 5 ? "Mas lento" : "Similar")
                            .font(.caption2)
                            .foregroundColor(diff < -5 ? .green : diff > 5 ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                if activity.averageHeartrate != nil {
                    Divider().frame(height: 50)
                    VStack(spacing: 4) {
                        Text("FC media").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.0f bpm", activity.averageHeartrate!))
                            .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                        if let histHR = historicalAvgHR, let avgHR = activity.averageHeartrate {
                            let diff = avgHR - histHR
                            Text(diff < -3 ? "Mas baja" : diff > 3 ? "Mas alta" : "Similar")
                                .font(.caption2)
                                .foregroundColor(diff < -3 ? .green : diff > 3 ? .red : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let trend = hrPaceRatioTrend {
                    Divider().frame(height: 50)
                    VStack(spacing: 4) {
                        Text("Tendencia").font(.caption2).foregroundColor(.secondary)
                        Image(systemName: trend == "up" ? "arrow.up.circle.fill" :
                                         trend == "down" ? "arrow.down.circle.fill" : "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(trend == "up" ? .green : trend == "down" ? .red : .secondary)
                        Text(trend == "up" ? "Mejora" : trend == "down" ? "Declive" : "Estable")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Aerobic decoupling section
            if let decoupling = aerobicDecoupling {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: decoupling > 5 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(decoupling > 5 ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Desacoplamiento aerobi co: %.1f%%", decoupling))
                            .font(.subheadline).fontWeight(.medium)
                        Text(decoupling > 5 ? "Hay fatiga cardiovascular" : "Buena base aerobica")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Route Map

private struct RouteMapCard: View {
    let polyline: String
    let sportType: String

    private var coordinates: [CLLocationCoordinate2D] {
        decodePolyline(polyline)
    }

    private var routeColor: Color {
        switch sportType.lowercased() {
        case "ride", "virtualride": return .orange
        case "swim": return .cyan
        case "hike": return .green
        default: return .red
        }
    }

    var body: some View {
        Group {
            if coordinates.count > 1 {
                Map {
                    MapPolyline(coordinates: coordinates)
                        .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                    // Inicio y fin
                    if let first = coordinates.first {
                        Annotation("", coordinate: first) {
                            Circle().fill(.green).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    if let last = coordinates.last {
                        Annotation("", coordinate: last) {
                            Circle().fill(routeColor).frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - Header

private struct ActivityHeaderCard: View {
    let activity: StravaActivity

    var body: some View {
        HStack(spacing: 16) {
            Text(activity.sportEmoji)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.sportType)
                    .font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                Text(activity.name).font(.headline).lineLimit(2)
                Text(activity.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Stats Grid

private struct StatsGrid: View {
    let activity: StravaActivity

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if activity.distance > 0 {
                StatCell(title: "Distancia", value: activity.formattedDistance,
                         icon: "arrow.right.circle.fill", color: .blue)
            }
            StatCell(title: "Tiempo", value: activity.formattedDuration,
                     icon: "clock.fill", color: .purple)
            if activity.distance > 0 {
                StatCell(title: "Ritmo", value: activity.formattedPace,
                         icon: "gauge.with.needle.fill", color: .orange)
            }
            if activity.totalElevationGain > 0 {
                StatCell(title: "Desnivel", value: String(format: "%.0f m", activity.totalElevationGain),
                         icon: "mountain.2.fill", color: .green)
            }
            if let k = activity.kcal {
                StatCell(title: "Calorias", value: String(format: "%.0f kcal", k),
                         icon: "flame.fill", color: .red)
            }
        }
    }
}

struct StatCell: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(.title3, design: .rounded)).fontWeight(.bold)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Heart Rate

private struct HeartRateCard: View {
    let avg: Double
    let max: Double?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "heart.fill").foregroundColor(.red)
                Text(String(format: "%.0f", avg))
                    .font(.system(.title, design: .rounded)).fontWeight(.bold)
                Text("FC media").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let max {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundColor(.red.opacity(0.5))
                    Text(String(format: "%.0f", max))
                        .font(.system(.title, design: .rounded)).fontWeight(.bold)
                    Text("FC maxima").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Power

private struct PowerCard: View {
    let avg: Double
    let weighted: Int?
    let kj: Double?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundColor(.yellow)
                Text(String(format: "%.0f W", avg))
                    .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                Text("Potencia media").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            if let w = weighted {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "bolt.circle.fill").foregroundColor(.yellow.opacity(0.7))
                    Text("\(w) W")
                        .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                    Text("NP").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if let kj {
                Divider().frame(height: 60)
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundColor(.orange)
                    Text(String(format: "%.0f kJ", kj))
                        .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                    Text("Trabajo").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Suffer Score

private struct SufferScoreCard: View {
    let score: Int

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suffer Score").font(.headline)
                Text("Esfuerzo relativo de esta actividad")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(sufferColor)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sufferColor: Color {
        switch score {
        case 0..<50: return .blue
        case 50..<100: return .green
        case 100..<150: return .yellow
        case 150..<200: return .orange
        default: return .red
        }
    }
}

// MARK: - Google Encoded Polyline Decoder

private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
    var coords: [CLLocationCoordinate2D] = []
    var idx = encoded.startIndex
    var lat = 0, lng = 0

    while idx < encoded.endIndex {
        // decode one varint
        func decodeNext() -> Int {
            var shift = 0, result = 0, b: Int
            repeat {
                guard idx < encoded.endIndex else { return 0 }
                b = Int(encoded[idx].asciiValue ?? 63) - 63
                idx = encoded.index(after: idx)
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }
        lat += decodeNext()
        lng += decodeNext()
        coords.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5,
                                             longitude: Double(lng) / 1e5))
    }
    return coords
}
