import Foundation

/// El JSON que pedimos a Gemini: `{ "foods": [ { "name": ..., "grams": ... } ] }`.
struct GeminiResponse: Decodable, Sendable {
    let foods: [DetectedFood]
}

/// Sobre de la respuesta REST de generateContent (solo los campos que usamos).
struct GenerateContentEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

/// Error estándar de las APIs de Google: `{ "error": { "code", "message", "status", "details" } }`.
struct GoogleAPIErrorEnvelope: Decodable {
    struct Body: Decodable {
        struct Detail: Decodable {
            let type: String?
            let retryDelay: String?
            let reason: String?

            private enum CodingKeys: String, CodingKey {
                case type = "@type"
                case retryDelay, reason
            }
        }
        let code: Int?
        let message: String?
        let status: String?
        let details: [Detail]?
    }
    let error: Body
}

enum GeminiParser {
    static let maxFoods = 10

    /// Extrae la lista de alimentos de una respuesta 200 de generateContent.
    static func foods(fromResponse data: Data) throws -> [DetectedFood] {
        let envelope: GenerateContentEnvelope
        do {
            envelope = try JSONDecoder().decode(GenerateContentEnvelope.self, from: data)
        } catch {
            throw GeminiError.unreadableResponse
        }
        guard let candidate = envelope.candidates?.first else {
            if let reason = envelope.promptFeedback?.blockReason {
                throw GeminiError.blocked(reason)
            }
            throw GeminiError.emptyResponse
        }
        if let reason = candidate.finishReason, ["SAFETY", "PROHIBITED_CONTENT", "IMAGE_SAFETY", "BLOCKLIST"].contains(reason) {
            throw GeminiError.blocked(reason)
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        return try foods(fromModelText: text)
    }

    /// Lee el JSON que escribe el modelo. Acepta que venga envuelto en ```json … ```.
    static func foods(fromModelText text: String) throws -> [DetectedFood] {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}"), start < end {
            json = String(json[start...end])
        }
        guard !json.isEmpty, let data = json.data(using: .utf8) else { throw GeminiError.emptyResponse }
        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiError.unreadableResponse
        }
        return Array(decoded.foods
            .filter { !$0.name.isEmpty && $0.grams > 0 && $0.grams <= 3000 }
            .prefix(maxFoods))
    }

    static func apiError(from data: Data) -> GoogleAPIErrorEnvelope.Body? {
        try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data).error
    }
}
