import SwiftUI
import Charts

struct BodyCompositionView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var showingEntry = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero
                if let body = healthKit.bodyComposition {
                    HStack(spacing: 0) {
                        if let w = body.weightKg {
                            StatHero(label: "Peso", value: String(format: "%.1f", w), unit: "kg", color: .pink)
                        }
                        if let b = body.bmi {
                            Divider().frame(height: 60)
                            StatHero(label: "IMC", value: String(format: "%.1f", b), unit: bmiLabel(b), color: bmiColor(b))
                        }
                        if let t = body.trend as MetricTrend? {
                            Divider().frame(height: 60)
                            VStack(spacing: 4) {
                                Image(systemName: t.systemImage)
                                    .foregroundColor(t.color(higherIsBetter: false))
                                    .font(.title3)
                                Text("Tendencia").font(.caption2).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)

                    // Historial peso
                    if !body.samples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Historial de peso").font(.headline)
                            Chart(body.samples) { s in
                                LineMark(x: .value("Fecha", s.date), y: .value("kg", s.value))
                                    .foregroundStyle(Color.pink).interpolationMethod(.catmullRom)
                                PointMark(x: .value("Fecha", s.date), y: .value("kg", s.value))
                                    .foregroundStyle(Color.pink)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { v in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    AxisValueLabel().foregroundStyle(Color.secondary)
                                }
                            }
                            .frame(height: 160)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }
                } else {
                    ContentUnavailableView("Sin registros", systemImage: "figure.stand",
                                          description: Text("Añade tu peso para empezar a hacer seguimiento"))
                        .padding(.top, 40)
                }

                Button {
                    showingEntry = true
                } label: {
                    Label("Registrar peso", systemImage: "plus")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.pink).foregroundColor(.white)
                        .fontWeight(.semibold)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal)

                // IMC tabla
                VStack(alignment: .leading, spacing: 0) {
                    Text("Clasificación IMC").font(.headline)
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                    ForEach(bmiRanges, id: \.label) { range in
                        HStack {
                            Circle().fill(range.color).frame(width: 8, height: 8)
                            Text(range.label).font(.subheadline)
                            Spacer()
                            Text(range.range).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        if range.label != bmiRanges.last?.label { Divider().padding(.leading, 30) }
                    }
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Peso e IMC")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEntry) {
            WeightEntrySheet()
        }
    }

    private func bmiLabel(_ b: Double) -> String {
        switch b {
        case ..<18.5: return "Bajo peso"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Sobrepeso"
        default: return "Obesidad"
        }
    }

    private func bmiColor(_ b: Double) -> Color {
        switch b {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }

    private let bmiRanges: [(label: String, range: String, color: Color)] = [
        ("Bajo peso", "< 18.5", .blue),
        ("Peso normal", "18.5 – 24.9", .green),
        ("Sobrepeso", "25 – 29.9", .orange),
        ("Obesidad", "≥ 30", .red)
    ]
}

private struct StatHero: View {
    let label: String; let value: String; let unit: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(.title2, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}
