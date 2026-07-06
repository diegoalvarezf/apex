import Foundation

enum ClaudeConfig {
    // Añade tu API key de Anthropic
    static let apiKey = "YOUR_ANTHROPIC_API_KEY"  // https://console.anthropic.com
    static let model = "claude-sonnet-4-6"
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
            "max_tokens": 1024,
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
        guard let text = claudeResponse.content.first?.text else { throw AIError.emptyResponse }

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
            let text: String
        }
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
    func rawCompletion(prompt: String, system: String? = nil) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": ClaudeConfig.model,
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]
        if let system { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.apiError
        }
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.content.first?.text else { throw AIError.emptyResponse }
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
