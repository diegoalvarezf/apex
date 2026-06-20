import SwiftUI

struct HealthView: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            Group {
                if !healthKit.isAuthorized {
                    ScrollView { HealthAuthCard().padding() }
                } else {
                    List {
                        Section("Cardio") {
                            if let rhr = healthKit.todaySummary?.restingHR {
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "FC en reposo", icon: "heart.fill", color: .red,
                                    unit: "bpm", value: String(format: "%.0f", rhr),
                                    samples: healthKit.restingHRHistory, higherIsBetter: false,
                                    normalRange: 40...80,
                                    explanation: "La frecuencia cardíaca en reposo es un indicador clave de tu forma cardiovascular. Valores más bajos indican mejor condición física."
                                ))) {
                                    HealthListRow(icon: "heart.fill", color: .red, title: "FC en reposo",
                                                 value: String(format: "%.0f bpm", rhr),
                                                 samples: healthKit.restingHRHistory)
                                }
                            }
                            if let vo2 = healthKit.vo2MaxData {
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "VO₂Max", icon: "lungs.fill", color: .blue,
                                    unit: "ml/kg/min", value: String(format: "%.1f", vo2.current),
                                    samples: vo2.samples, higherIsBetter: true, normalRange: 35...60,
                                    explanation: "El VO₂Max mide tu capacidad aeróbica máxima. Es el mejor predictor de rendimiento de resistencia a largo plazo."
                                ))) {
                                    HealthListRow(icon: "lungs.fill", color: .blue, title: "VO₂Max",
                                                 value: String(format: "%.1f ml/kg/min", vo2.current),
                                                 samples: vo2.samples, trend: vo2.trend)
                                }
                            }
                            if let hrv = healthKit.hrvHistory.first {
                                let samples = healthKit.hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "HRV", icon: "waveform.path.ecg", color: .green,
                                    unit: "ms", value: String(format: "%.0f", hrv.sdnn),
                                    samples: samples, higherIsBetter: true, normalRange: 20...80,
                                    explanation: "La variabilidad de la frecuencia cardíaca refleja la recuperación del sistema nervioso. Un HRV alto indica mejor capacidad de adaptación al estrés."
                                ))) {
                                    HealthListRow(icon: "waveform.path.ecg", color: .green, title: "HRV",
                                                 value: String(format: "%.0f ms", hrv.sdnn),
                                                 samples: samples, trend: computeTrend(samples: samples))
                                }
                            }
                            if let resp = healthKit.respiratoryData {
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "Freq. respiratoria", icon: "wind", color: .cyan,
                                    unit: "resp/min", value: String(format: "%.0f", resp.current),
                                    samples: resp.samples, higherIsBetter: false, normalRange: 12...20,
                                    explanation: "La frecuencia respiratoria nocturna es sensible a enfermedad, estrés y sobreentrenamiento."
                                ))) {
                                    HealthListRow(icon: "wind", color: .cyan, title: "Freq. respiratoria",
                                                 value: String(format: "%.0f resp/min", resp.current),
                                                 samples: resp.samples, trend: resp.trend)
                                }
                            }
                        }

                        Section("Recuperación") {
                            if !healthKit.sleepHistory.isEmpty {
                                NavigationLink(destination: SleepDetailView(history: healthKit.sleepHistory)) {
                                    if let latest = healthKit.sleepHistory.first {
                                        HealthListRow(icon: "moon.fill", color: .indigo, title: "Sueño",
                                                     value: latest.formattedTotal, badge: "\(latest.score)")
                                    }
                                }
                            }
                            if let wrist = healthKit.wristTempData {
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "Temp. muñeca", icon: "thermometer.medium", color: .purple,
                                    unit: "°C desviación", value: String(format: "%+.1f°", wrist.deviation),
                                    samples: wrist.samples, higherIsBetter: false,
                                    explanation: "La temperatura de la muñeca durante el sueño varía con enfermedades y recuperación. Las desviaciones persistentes merecen atención."
                                ))) {
                                    HealthListRow(icon: "thermometer.medium", color: .purple, title: "Temp. muñeca",
                                                 value: String(format: "%+.1f° vs baseline", wrist.deviation),
                                                 samples: wrist.samples)
                                }
                            }
                        }

                        Section("Actividad y entorno") {
                            if let dl = healthKit.daylightData {
                                NavigationLink(destination: MetricDetailView(config: MetricConfig(
                                    title: "Luz diurna", icon: "sun.max.fill", color: .yellow,
                                    unit: "minutos", value: "\(dl.todayMinutes)",
                                    samples: dl.samples, higherIsBetter: true, normalRange: 20...120,
                                    explanation: "La exposición diaria a la luz natural sincroniza el ritmo circadiano y mejora el sueño. Objetivo: mínimo 20-30 min."
                                ))) {
                                    HealthListRow(icon: "sun.max.fill", color: .yellow, title: "Luz diurna",
                                                 value: "\(dl.todayMinutes) min hoy",
                                                 samples: dl.samples, trend: dl.trend)
                                }
                            }
                            NavigationLink(destination: HeartRateZonesView()) {
                                HStack {
                                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                                        .foregroundColor(.orange).frame(width: 28)
                                    Text("Zonas de entrenamiento").font(.subheadline)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section("Cuerpo") {
                            NavigationLink(destination: BodyCompositionView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "figure.stand")
                                        .foregroundColor(.pink).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Peso e IMC").font(.subheadline)
                                        if let body = healthKit.bodyComposition,
                                           let w = body.weightKg, let b = body.bmi {
                                            Text(String(format: "%.1f kg · IMC %.1f", w, b))
                                                .font(.caption).foregroundColor(.secondary)
                                        } else {
                                            Text("Toca para registrar").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Salud")
            .refreshable { await healthKit.loadAll() }
        }
    }
}

struct HealthListRow: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    var samples: [MetricSample] = []
    var trend: MetricTrend? = nil
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(value).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if samples.count >= 4 {
                TrendSparkline(samples: Array(samples.suffix(10)), color: color, height: 24)
                    .frame(width: 60)
            }
            if let trend {
                Image(systemName: trend.systemImage).font(.caption)
                    .foregroundColor(trend.color(higherIsBetter: true))
            }
            if let badge {
                Text(badge).font(.caption2).fontWeight(.semibold)
                    .foregroundColor(color).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HealthAuthCard: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill").font(.system(size: 52)).foregroundColor(.red)
            VStack(spacing: 6) {
                Text("Conectar Apple Health").font(.title3).fontWeight(.semibold)
                Text("Autoriza el acceso para ver sueño, HRV, recuperación y mucho más.")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button("Autorizar acceso") { Task { await healthKit.requestAuthorization() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
