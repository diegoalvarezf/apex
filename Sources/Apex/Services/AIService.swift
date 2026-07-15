import Foundation

enum ClaudeConfig {
    // API key desde StravaSecrets.plist (local, en .gitignore) bajo la clave
    // "AnthropicAPIKey". Fallback al placeholder si el fichero no la tiene.
    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "StravaSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return dict
    }()

    static let apiKey = secrets["AnthropicAPIKey"] ?? "YOUR_ANTHROPIC_API_KEY"

    // Sonnet para insights diarios (barato, rápido); Opus para crear rutinas (más capaz)
    static let model = "claude-sonnet-4-6"
    static let opusModel = "claude-opus-4-8"
}

final class AIService {
    static let shared = AIService()

    func generateInsights(context: AICoachContext) async throws -> [AIInsight] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": ClaudeConfig.model,
            "max_tokens": 1800,
            "messages": [
                ["role": "user", "content": context.buildPrompt()]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.apiError
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.firstText else { throw AIError.emptyResponse }

        return try parseInsights(from: text)
    }

    private func parseInsights(from text: String) throws -> [AIInsight] {
        guard let jsonText = AIService.extractJSON(from: text) else { throw AIError.parseError }
        guard let data = jsonText.data(using: .utf8) else { throw AIError.parseError }
        let parsed = try JSONDecoder().decode(InsightsWrapper.self, from: data)

        return parsed.insights.compactMap { raw in
            // Category rawValues are lowercase English — match directly
            guard let category = AIInsight.Category(rawValue: raw.category.lowercased()),
                  let priority = AIInsight.Priority(rawValue: raw.priority.lowercased())
            else { return nil }
            return AIInsight(category: category, title: raw.title, body: raw.body,
                             recommendations: raw.recommendations, priority: priority)
        }
    }

    private struct ClaudeResponse: Codable {
        let content: [ContentBlock]
        struct ContentBlock: Codable {
            let text: String?   // los bloques de thinking no traen texto
        }
        var firstText: String? { content.compactMap(\.text).first }
    }

    private struct InsightsWrapper: Codable {
        let insights: [RawInsight]
    }

    private struct RawInsight: Codable {
        let category: String
        let title: String
        let body: String
        let recommendations: [String]
        let priority: String
    }

    /// Returns raw text from Claude. Optionally pass a system prompt for JSON-only tasks.
    /// `model` y `maxTokens` permiten usar Opus con más presupuesto para tareas complejas.
    func rawCompletion(prompt: String, system: String? = nil,
                       model: String = ClaudeConfig.model, maxTokens: Int = 2048) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120  // Opus con effort alto puede tardar

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        if let system { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.apiError
        }
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.firstText else { throw AIError.emptyResponse }
        return text
    }

    /// Chat multi-turno con system prompt. `messages` = [["role":"user"/"assistant","content":...]].
    func chatCompletion(messages: [[String: String]], system: String,
                        model: String = ClaudeConfig.model, maxTokens: Int = 1024) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens,
            "system": system, "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIError.apiError }
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.firstText else { throw AIError.emptyResponse }
        return text
    }

    /// Extracts the first valid JSON object `{...}` from any text (handles markdown fences, preamble, etc.)
    static func extractJSON(from text: String) -> String? {
        var depth = 0
        var start: String.Index? = nil
        for idx in text.indices {
            switch text[idx] {
            case "{":
                if depth == 0 { start = idx }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let s = start {
                    return String(text[s...idx])
                }
            default: break
            }
        }
        return nil
    }

    enum AIError: Error {
        case invalidURL, apiError, emptyResponse, parseError
    }
}
