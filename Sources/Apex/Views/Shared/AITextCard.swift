import SwiftUI

// Card genérica de análisis IA bajo demanda: botón → llamada → texto, con caché
// por clave. Reutilizable (sueño, progresión de fuerza…). El caller sólo aporta
// el texto explicativo y un closure que devuelve el análisis.
struct AITextCard: View {
    let title: String
    let subtitle: String
    let cacheKey: String
    let generate: () async throws -> String

    @State private var text: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var updatedAt: Date?

    private var dateKey: String { cacheKey + "_at" }
    private var freshnessText: String? {
        guard let at = updatedAt else { return nil }
        return Calendar.current.isDateInToday(at)
            ? "Actualizado hoy " + at.formatted(date: .omitted, time: .shortened)
            : "Actualizado " + at.formatted(.relative(presentation: .named))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(title).font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                } else if text != nil {
                    Button { run() } label: { Image(systemName: "arrow.clockwise").font(.caption) }
                }
            }

            if isLoading {
                // Mientras (re)genera, se muestra el spinner aunque ya hubiera texto
                HStack(spacing: 10) {
                    ProgressView()
                    Text(text == nil ? "Analizando…" : "Actualizando…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let text {
                AIAnalysisBody(text: text)
                if let freshnessText {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 9))
                        Text(freshnessText).font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                }
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            text = UserDefaults.standard.string(forKey: cacheKey)
            updatedAt = UserDefaults.standard.object(forKey: dateKey) as? Date
            // Automático: si no hay nada cacheado para esta clave, se genera solo
            if text == nil { run() }
        }
    }

    private func run() {
        Task {
            isLoading = true; error = nil
            defer { isLoading = false }
            do {
                let out = try await generate().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !out.isEmpty else { error = "La IA no devolvió análisis."; return }
                text = out
                updatedAt = Date()
                UserDefaults.standard.set(out, forKey: cacheKey)
                UserDefaults.standard.set(updatedAt, forKey: dateKey)
            } catch {
                self.error = "No pude analizar: \(error.localizedDescription)"
            }
        }
    }
}

// Renderiza un análisis IA separando el cuerpo de la línea "Conclusión: …",
// que se destaca en su propia caja. Reutilizada por todas las cards de IA.
struct AIAnalysisBody: View {
    let text: String

    private var parts: (body: String, conclusion: String?) {
        guard let r = text.range(of: "Conclusión:", options: .caseInsensitive) else {
            return (text, nil)
        }
        let body = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let concl = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, concl.isEmpty ? nil : concl)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !parts.body.isEmpty {
                Text(parts.body)
                    .font(.subheadline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let concl = parts.conclusion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(concl)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.purple.opacity(0.12), .blue.opacity(0.12)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
    }
}
