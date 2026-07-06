import SwiftUI

struct SleepCard: View {
    let sleep: SleepData?

    private var hours: Double { (sleep?.totalSleep ?? 0) / 3600 }
    private var score: Int { sleep?.score ?? 0 }

    private var statusColor: Color {
        guard sleep != nil else { return .secondary }
        if hours >= 7 && score >= 70 { return .indigo }
        if hours >= 6 && score >= 50 { return .orange }
        return .red
    }

    private var subtitle: String {
        guard let s = sleep else { return "Sin datos de anoche" }
        let diff = hours - 7.0
        if hours < 6   { return "Te faltaron \(fmt(7 - hours)) para el mínimo" }
        if hours < 7   { return "Te faltaron \(fmt(7 - hours)) del rango ideal" }
        if hours > 9   { return "Dormiste \(fmt(hours - 9)) más de lo recomendado" }
        if s.score < 60 { return "Duración ok, calidad mejorable" }
        return "Dentro del rango recomendado (7–9h)"
    }

    private func fmt(_ h: Double) -> String {
        let m = Int(h * 60); let hr = m / 60; let mn = m % 60
        if hr > 0 { return mn > 0 ? "\(hr)h \(mn)min" : "\(hr)h" }
        return "\(mn)min"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(statusColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "moon.fill")
                    .foregroundColor(statusColor).font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sueño").font(.subheadline)
                Text(subtitle).font(.caption).foregroundColor(statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(sleep?.formattedTotal ?? "--")
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                        .foregroundColor(statusColor)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(score)")
                        .font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                        .foregroundColor(statusColor)
                    Text("/100").font(.caption2).foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
