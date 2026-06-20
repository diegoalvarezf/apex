import Foundation

enum ClaudeConfig {
    // Añade tu API key de Anthropic
    static let apiKey = "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"
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
        let jsonText: String
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            jsonText = String(text[start.lowerBound...end.upperBound])
        } else {
            jsonText = text
        }

        guard let data = jsonText.data(using: .utf8) else { throw AIError.parseError }
        let parsed = try JSONDecoder().decode(InsightsWrapper.self, from: data)

        return parsed.insights.compactMap { raw in
            guard let category = AIInsight.Category(rawValue: raw.category),
                  let priority = AIInsight.Priority(rawValue: raw.priority)
            else { return nil }
            return AIInsight(category: category, title: raw.title, body: raw.body, recommendations: raw.recommendations, priority: priority)
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

    enum AIError: Error {
        case invalidURL, apiError, emptyResponse, parseError
    }
}
