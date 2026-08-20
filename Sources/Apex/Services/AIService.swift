import Foundation

// Fachada de la IA para el resto de la app.
//
// Ya no habla con Anthropic: manda al backend el tipo de análisis y los datos, y
// es el servidor quien pone el prompt, el modelo y la clave. Por eso aquí no queda
// ninguna credencial ni ningún prompt.
//
// Se mantiene como `AIService.shared` con métodos parecidos a los de antes para no
// reescribir las once pantallas que la usan.
final class AIService {
    static let shared = AIService()

    private init() {}

    // Un análisis del catálogo. `input` son los datos ya calculados por la app.
    func analyze(_ kind: AnalysisKind, input: String) async throws -> String {
        try await BackendClient.shared.analyze(kind: kind, input: input)
    }

    // El análisis que abre la pantalla de Apex IA.
    func generateInsights(context: AICoachContext) async throws -> [AIInsight] {
        // Solo datos: la tarea y el esquema JSON los pone el servidor.
        let text = try await BackendClient.shared.analyze(
            kind: .insights, input: context.contextText())

        guard let json = Self.extractJSON(from: text),
              let data = json.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(InsightsWrapper.self, from: data)
        else {
            throw BackendError.respuestaIlegible
        }
        return wrapper.insights
    }

    // Chat del coach. Va por su propio endpoint porque es multi-turno.
    func chatCompletion(messages: [[String: String]], context: String) async throws -> String {
        try await BackendClient.shared.chat(messages: messages, context: context)
    }

    private struct InsightsWrapper: Decodable {
        let insights: [AIInsight]
    }

    // El modelo devuelve JSON, a veces envuelto en ```json o con una frase delante.
    // Se extrae el objeto en vez de fiarse de que venga limpio.
    static func extractJSON(from text: String) -> String? {
        guard let inicio = text.firstIndex(of: "{"),
              let fin = text.lastIndex(of: "}"), inicio < fin else { return nil }
        return String(text[inicio...fin])
    }
}
