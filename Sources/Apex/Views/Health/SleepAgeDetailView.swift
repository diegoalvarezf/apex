import SwiftUI

struct SleepAgeDetailView: View {
    let result: SleepAgeResult

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero
                VStack(spacing: 12) {
                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text("\(result.chronologicalAge)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("Edad real").font(.caption).foregroundColor(.secondary)
                        }
                        Image(systemName: result.delta < 0 ? "arrow.left" : "arrow.right")
                            .font(.title2).foregroundColor(result.deltaColor)
                        VStack(spacing: 4) {
                            Text("\(result.sleepAge)")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundColor(result.deltaColor)
                            Text("Edad de sueño").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text(result.deltaLabel.capitalized)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(result.deltaColor)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(result.deltaColor.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)

                // Factores
                VStack(alignment: .leading, spacing: 0) {
                    Text("Factores de sueño")
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

                    ForEach(result.factors) { f in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(f.color.opacity(0.15)).frame(width: 36, height: 36)
                                    Image(systemName: f.icon).foregroundColor(f.color).font(.system(size: 15))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).font(.subheadline).fontWeight(.medium)
                                    Text(f.valueLabel).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(f.ageDelta == 0 ? "±0 años" : f.ageDelta < 0 ? "\(f.ageDelta) años" : "+\(f.ageDelta) años")
                                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                                        .foregroundColor(f.ageDelta <= 0 ? .green : .red)
                                    Text(f.ageDelta < 0 ? "más joven" : f.ageDelta > 0 ? "más mayor" : "neutral")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            GeometryReader { geo in
                                ZStack(alignment: f.ageDelta <= 0 ? .trailing : .leading) {
                                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 4)
                                    let pct = min(abs(Double(f.ageDelta)) / 5.0, 1.0)
                                    Rectangle()
                                        .fill(f.ageDelta <= 0 ? Color.green : Color.red)
                                        .frame(width: geo.size.width * CGFloat(pct), height: 4)
                                }
                            }
                            .frame(height: 4).padding(.horizontal, 52).padding(.bottom, 8)

                            if f.id != result.factors.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Cómo mejorarla
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cómo rejuvenecer tu sueño").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        TipRow2(icon: "clock", text: "Acuéstate y levántate siempre a la misma hora — el ritmo circadiano es clave para el sueño profundo")
                        TipRow2(icon: "thermometer.medium", text: "La temperatura ideal del dormitorio es 18-20°C")
                        TipRow2(icon: "iphone.slash", text: "Sin pantallas 1h antes de dormir — la luz azul suprime la melatonina")
                        TipRow2(icon: "cup.and.saucer", text: "Evita cafeína después de las 14h — su vida media es de 6-8h")
                        TipRow2(icon: "figure.run", text: "El ejercicio regular aumenta el sueño profundo, pero no entrenes 3h antes de dormir")
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edad de sueño")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TipRow2: View {
    let icon: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundColor(.indigo).frame(width: 16)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
    }
}
