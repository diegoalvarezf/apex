import SwiftUI
import Charts

// Un día concreto del pasado, con las mismas métricas que el inicio muestra de hoy.
//
// No hay datos "congelados" de días anteriores más allá del cierre de Body Battery:
// todo lo demás se recalcula con las mismas funciones que usa el dashboard, pero
// acotando la entrada a ese día. Así un día pasado y el de hoy no pueden discrepar
// por usar caminos distintos.
struct HealthDayDetailView: View {
    let day: Date

    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var dashVM: DashboardViewModel

    private var cal: Calendar { Calendar.current }

    // Lo que la app calculó ese día. Es la única fuente para los cuatro valores:
    // no se recalculan, porque los parámetros de hoy (FC en reposo, FCmáx) pueden
    // no ser los de entonces y el número saldría distinto al que se vio.
    private var snapshot: DailySnapshot? { DailySnapshotStore.shared.snapshot(for: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if sinSnapshot && !sinNada { avisoSinRegistro }
                resumen
                if !batteryCurve.isEmpty { curvaBateria }
                if let sleep = sleepDelDia { tarjetaSueno(sleep) }
                if !actividadesDelDia.isEmpty { tarjetaActividades }
                if sinNada { sinDatos }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Datos de ese día

    private var actividadesDelDia: [StravaActivity] {
        dashVM.activities.filter { cal.isDate($0.startDate, inSameDayAs: day) }
    }

    private var sleepDelDia: SleepData? {
        healthKit.sleepHistory.first { cal.isDate($0.date, inSameDayAs: day) }
    }

    private var recoveryDelDia: Int? { snapshot?.recovery }

    private var restingHR: Double { healthKit.todaySummary?.restingHR ?? UserProfile.restingHR }

    // Curva horaria de batería de ese día, reconstruida con el cierre del día
    // anterior como punto de partida (el mismo encadenado que usa el dashboard).
    // Curva guardada tal cual se calculó ese día.
    private var batteryCurve: [MetricSample] {
        (snapshot?.batteryCurve ?? []).map { MetricSample(date: $0.date, value: $0.value) }
    }

    private var batteryDelDia: Int? { snapshot?.battery }

    private var estresDelDia: Int? { snapshot?.stress }

    private var esfuerzoDelDia: Int? { snapshot?.effort }

    // No hay foto guardada de ese día: puede ser anterior a que la app empezara a
    // guardarlas. El sueño y las actividades sí son registros reales y se muestran.
    private var sinSnapshot: Bool { snapshot?.isEmpty ?? true }

    private var sinNada: Bool {
        sinSnapshot && sleepDelDia == nil && actividadesDelDia.isEmpty
    }

    // MARK: - Secciones

    private var resumen: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            valorTile("Body Battery", "bolt.heart.fill", batteryDelDia, higherIsBetter: true)
            valorTile("Recuperación", "arrow.up.heart.fill", recoveryDelDia, higherIsBetter: true)
            valorTile("Estrés", "brain.head.profile", estresDelDia, higherIsBetter: false)
            valorTile("Esfuerzo", "bolt.fill", esfuerzoDelDia, higherIsBetter: true)
        }
    }

    private func valorTile(_ titulo: String, _ icono: String, _ valor: Int?, higherIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titulo).font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: icono).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valor.map(String.init) ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(valor.map { color($0, higherIsBetter: higherIsBetter) } ?? .secondary)
                if valor != nil {
                    Text("%").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var curvaBateria: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body Battery durante el día").font(.headline)
            Chart(batteryCurve) { s in
                AreaMark(x: .value("Hora", s.date), y: .value("Batería", s.value))
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Hora", s.date), y: .value("Batería", s.value))
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tarjetaSueno(_ sleep: SleepData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sueño", systemImage: "moon.fill").font(.headline)
                Spacer()
                Text("\(sleep.score)/100").font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.indigo)
            }
            HStack(spacing: 18) {
                dato("Total", sleep.formattedTotal)
                dato("Profundo", String(format: "%.0f min", sleep.deepSleep / 60))
                dato("REM", String(format: "%.0f min", sleep.remSleep / 60))
                dato("Eficiencia", String(format: "%.0f%%", sleep.efficiency))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tarjetaActividades: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Actividades", systemImage: "figure.run").font(.headline)
            ForEach(actividadesDelDia) { act in
                HStack(spacing: 10) {
                    Text(act.sportEmoji)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(act.name).font(.subheadline).lineLimit(1)
                        Text("\(act.formattedDistance) · \(act.formattedDuration)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Se dice de forma explícita en lugar de rellenar con un recálculo: los valores
    // dependen de parámetros que pueden haber cambiado desde entonces.
    private var avisoSinRegistro: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
            Text("De este día no hay valores guardados: es anterior a que la app empezara a registrarlos. El sueño y las actividades sí son datos reales de ese día.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sinDatos: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Sin datos de este día").font(.headline)
            Text("La app conserva unos 30 días de historial.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dato(_ etiqueta: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).font(.subheadline).fontWeight(.semibold)
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func color(_ valor: Int, higherIsBetter: Bool) -> Color {
        let v = higherIsBetter ? valor : 100 - valor
        switch v {
        case 75...:   return .green
        case 55..<75: return .cyan
        case 35..<55: return .yellow
        default:      return .red
        }
    }
}
