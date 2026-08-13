import SwiftUI

// Calendario mensual con el valor de una métrica por día.
//
// Cada día pinta una barra cuyo color y longitud salen del propio valor, para que
// el mes se lea de un vistazo. Los días sin dato se quedan en gris: la app no
// rellena huecos, y aquí se nota más que en ninguna otra pantalla porque el
// historial disponible depende de cada métrica (ver `MetricCalendarData`).
struct MetricCalendarView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var dashVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    enum Metric: String, CaseIterable, Identifiable {
        case battery = "Body Battery"
        case stress = "Estrés"
        case recovery = "Recuperación"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .battery:  return "bolt.heart.fill"
            case .stress:   return "brain.head.profile"
            case .recovery: return "arrow.up.heart.fill"
            }
        }

        // En estrés, menos es mejor: el degradado se invierte.
        var higherIsBetter: Bool { self != .stress }
    }

    @State private var metric: Metric = .battery
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date?

    private let cal = Calendar.current

    private var data: [Date: Int] {
        MetricCalendarData.values(for: metric, healthKit: healthKit, activities: dashVM.activities)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    metricPicker
                    monthHeader
                    weekdayHeader
                    grid
                    if let selectedDay { dayDetail(selectedDay) }
                    legend
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    // MARK: - Piezas

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Metric.allCases) { m in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            metric = m
                            selectedDay = nil
                        }
                    } label: {
                        Label(m.rawValue, systemImage: m.icon)
                            .font(.subheadline).fontWeight(.medium)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(
                                metric == m ? color(for: 75).opacity(0.18) : Color(.secondarySystemGroupedBackground),
                                in: Capsule())
                            .foregroundStyle(metric == m ? color(for: 75) : .secondary)
                            .overlay(
                                Capsule().stroke(metric == m ? color(for: 75).opacity(0.5) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { cambiarMes(-1) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()
            VStack(spacing: 0) {
                Text(month, format: .dateTime.year())
                    .font(.caption).foregroundStyle(.secondary)
                Text(month, format: .dateTime.month(.wide))
                    .font(.title3).fontWeight(.bold)
            }
            Spacer()

            Button { cambiarMes(1) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .buttonStyle(.plain)
            // No se navega al futuro: no hay nada que enseñar.
            .disabled(esMesActual)
            .opacity(esMesActual ? 0.3 : 1)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(diasSemana, id: \.self) { d in
                Text(d).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let dias = diasDelMes()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(Array(dias.enumerated()), id: \.offset) { _, dia in
                if let dia {
                    dayCell(dia)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ dia: Date) -> some View {
        let valor = data[cal.startOfDay(for: dia)]
        let esHoy = cal.isDateInToday(dia)
        let futuro = dia > Date()
        let seleccionado = selectedDay.map { cal.isDate($0, inSameDayAs: dia) } ?? false

        return Button {
            guard valor != nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDay = seleccionado ? nil : dia
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: dia))")
                    .font(.system(size: 13, weight: esHoy ? .bold : .regular, design: .rounded))
                    .foregroundStyle(futuro ? .tertiary : (valor == nil ? .secondary : .primary))

                // Barra del día: proporción del valor y color según su tramo.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        if let valor {
                            Capsule()
                                .fill(color(for: valor))
                                .frame(width: max(4, geo.size.width * CGFloat(valor) / 100))
                        }
                    }
                }
                .frame(height: 5)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                seleccionado ? Color.primary.opacity(0.10)
                : (esHoy ? Color.primary.opacity(0.05) : .clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(esHoy ? Color.primary.opacity(0.25) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(valor == nil)
    }

    private func dayDetail(_ dia: Date) -> some View {
        let valor = data[cal.startOfDay(for: dia)]
        return HStack(spacing: 14) {
            Image(systemName: metric.icon)
                .font(.title3)
                .foregroundStyle(color(for: valor ?? 0))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(dia, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).fontWeight(.semibold)
                Text(metric.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let valor {
                Text("\(valor)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: valor))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: metric.higherIsBetter ? [.red, .yellow, .green] : [.green, .yellow, .red],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 90, height: 6)
                Text(metric.higherIsBetter ? "de peor a mejor" : "de menos a más estrés")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(MetricCalendarData.disponibilidad(metric))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Utilidades

    private var esMesActual: Bool {
        cal.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private func cambiarMes(_ delta: Int) {
        guard let nuevo = cal.date(byAdding: .month, value: delta, to: month) else { return }
        // Nunca más allá del mes en curso
        if delta > 0, nuevo > Date() { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            month = nuevo
            selectedDay = nil
        }
    }

    private var diasSemana: [String] {
        // Empieza en lunes, como el calendario del sistema en España
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        let simbolos = f.shortStandaloneWeekdaySymbols ?? ["L","M","X","J","V","S","D"]
        return Array(simbolos[1...] + simbolos[..<1]).map { String($0.prefix(3)) }
    }

    // Celdas del mes, con nil al principio para cuadrar el primer día en su columna.
    private func diasDelMes() -> [Date?] {
        guard let rango = cal.range(of: .day, in: .month, for: month),
              let primero = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }

        // weekday: 1=domingo. Se desplaza para que la semana empiece en lunes.
        let weekday = cal.component(.weekday, from: primero)
        let huecos = (weekday + 5) % 7

        var celdas: [Date?] = Array(repeating: nil, count: huecos)
        for d in rango {
            if let fecha = cal.date(byAdding: .day, value: d - 1, to: primero) {
                celdas.append(fecha)
            }
        }
        return celdas
    }

    private func color(for valor: Int) -> Color {
        let v = metric.higherIsBetter ? valor : 100 - valor
        switch v {
        case 75...:   return .green
        case 55..<75: return .cyan
        case 35..<55: return .yellow
        default:      return .red
        }
    }
}
