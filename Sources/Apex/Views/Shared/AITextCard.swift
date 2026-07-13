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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(title).font(.headline)
                Spacer()
                if text != nil && !isLoading {
                    Button { run() } label: { Image(systemName: "arrow.clockwise").font(.caption) }
                }
            }

            if let text {
                Text(text).font(.subheadline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analizando…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Button { run() } label: {
                    Label("Analizar con IA", systemImage: "sparkles")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { text = UserDefaults.standard.string(forKey: cacheKey) }
    }

    private func run() {
        Task {
            isLoading = true; error = nil
            defer { isLoading = false }
            do {
                let out = try await generate().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !out.isEmpty else { error = "La IA no devolvió análisis."; return }
                text = out
                UserDefaults.standard.set(out, forKey: cacheKey)
            } catch {
                self.error = "No pude analizar: \(error.localizedDescription)"
            }
        }
    }
}
