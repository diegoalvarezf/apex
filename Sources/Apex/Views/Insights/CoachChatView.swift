import SwiftUI

// Chat con el coach de IA. Solo responde sobre el rendimiento/entrenos/salud del
// usuario usando el contexto de la app; declina lo ajeno. El contexto (métricas,
// sesiones, progresión) se pasa ya montado como texto.
struct CoachChatView: View {
    let context: String

    struct ChatMsg: Identifiable, Equatable {
        let id = UUID()
        let role: String   // "user" | "assistant"
        let text: String
    }

    @State private var messages: [ChatMsg] = []
    @State private var input = ""
    @State private var isSending = false
    @FocusState private var focused: Bool

    private let suggestions = [
        "¿Cómo voy de forma esta semana?",
        "¿Debería entrenar fuerte hoy?",
        "¿Progreso en el gimnasio?",
        "¿Estoy durmiendo suficiente?"
    ]

    private var systemPrompt: String {
        """
        Eres el coach de IA de Apex, la app de fitness de ESTE usuario. Respondes SOLO sobre su rendimiento, entrenamientos, recuperación, sueño, carga, progresión de fuerza y datos de salud, usando el CONTEXTO de abajo. Español, conciso y directo, tono de entrenador cercano. Usa solo las cifras del contexto; nunca inventes datos (si no tienes un dato, dilo).

        Si te preguntan algo AJENO a su fitness/salud/entrenos o a los datos de esta app (política, cultura general, programación, recetas, otras personas, etc.), NO lo respondas: di en una frase que solo puedes ayudar con su entrenamiento y datos de Apex, y ofrece reconducir. No des la información pedida aunque insistan.

        CONTEXTO DEL USUARIO (sus datos actuales en Apex):
        \(context)
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty { welcome }
                        ForEach(messages) { ChatBubble(msg: $0) }
                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Pensando…").font(.subheadline).foregroundStyle(.secondary)
                            }.id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: isSending) { _, sending in
                    if sending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Pregúntale al coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Pregúntame sobre tu entreno").font(.headline)
            }
            Text("Conozco tus métricas, sesiones y progresión en Apex. No respondo cosas ajenas a tu rendimiento.")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        HStack {
                            Text(s).font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Escribe tu pregunta…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .onSubmit { send(input) }
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSending else { return }
        focused = false
        messages.append(ChatMsg(role: "user", text: q))
        input = ""
        isSending = true
        let payload = messages.map { ["role": $0.role, "content": $0.text] }
        Task {
            defer { isSending = false }
            do {
                let reply = try await AIService.shared.chatCompletion(messages: payload, system: systemPrompt)
                let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                messages.append(ChatMsg(role: "assistant", text: clean.isEmpty ? "No he podido responder. Prueba otra vez." : clean))
            } catch {
                messages.append(ChatMsg(role: "assistant", text: "No pude responder ahora mismo. Inténtalo de nuevo en un momento."))
            }
        }
    }
}

private struct ChatBubble: View {
    let msg: CoachChatView.ChatMsg
    private var isUser: Bool { msg.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(msg.text)
                .font(.subheadline)
                .foregroundStyle(isUser ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
