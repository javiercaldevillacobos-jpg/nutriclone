import Foundation
import Testing
@testable import NutriClone

/// Ningún test llama a Google: las respuestas HTTP se simulan con un transporte falso.
private actor FakeTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let (status, body) = responses.isEmpty ? (500, "{}") : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ delay: Duration) { delays.append(delay) }
}

private func okBody(_ modelText: String) -> String {
    let escaped = String(data: try! JSONEncoder().encode(modelText), encoding: .utf8)!
    return #"{"candidates":[{"content":{"parts":[{"text":\#(escaped)}],"role":"model"},"finishReason":"STOP"}]}"#
}

private let mealJSON = #"{"foods":[{"name":"arroz blanco cocido","grams":180},{"name":"pechuga de pollo","grams":150.5},{"name":"aceite de oliva","grams":"10 g"}]}"#
private let rateLimitBody = #"{"error":{"code":429,"message":"Resource has been exhausted","status":"RESOURCE_EXHAUSTED"}}"#
private let invalidKeyBody = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}"#

private func makeService(_ responses: [(Int, String)]) -> (GeminiService, FakeTransport, SleepRecorder) {
    let transport = FakeTransport(responses)
    let sleeper = SleepRecorder()
    let service = GeminiService(
        transport: { try await transport.send($0) },
        sleep: { await sleeper.record($0) }
    )
    return (service, transport, sleeper)
}

struct GeminiParserTests {
    @Test func parsesFoodsFromGenerateContentResponse() throws {
        let foods = try GeminiParser.foods(fromResponse: Data(okBody(mealJSON).utf8))
        #expect(foods.map(\.name) == ["arroz blanco cocido", "pechuga de pollo", "aceite de oliva"])
        #expect(foods.map(\.grams) == [180, 150.5, 10])
    }

    @Test func acceptsMarkdownFences() throws {
        let foods = try GeminiParser.foods(fromModelText: "```json\n\(mealJSON)\n```")
        #expect(foods.count == 3)
    }

    @Test func dropsInvalidEntriesAndCapsAtTen() throws {
        let many = (1...15).map { #"{"name":"alimento \#($0)","grams":50}"# }.joined(separator: ",")
        let text = #"{"foods":[{"name":"","grams":10},{"name":"pan","grams":0},\#(many)]}"#
        let foods = try GeminiParser.foods(fromModelText: text)
        #expect(foods.count == 10)
        #expect(foods.first?.name == "alimento 1")
    }

    @Test func blockedPromptIsReported() {
        let body = #"{"promptFeedback":{"blockReason":"SAFETY"}}"#
        #expect(throws: GeminiError.blocked("SAFETY")) {
            try GeminiParser.foods(fromResponse: Data(body.utf8))
        }
    }

    @Test func garbageIsUnreadable() {
        #expect(throws: GeminiError.unreadableResponse) {
            try GeminiParser.foods(fromModelText: "no es json { roto")
        }
    }
}

struct GeminiServiceTests {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    @Test func requestUsesHeaderKeyAndJSONMode() async throws {
        let (service, transport, _) = makeService([(200, okBody(mealJSON))])
        _ = try await service.analyze(jpeg: jpeg, apiKey: " clave-de-prueba ", model: .flash)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent")
        #expect(request.url?.query == nil, "la clave no debe ir en la URL")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "clave-de-prueba")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try #require(json["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts.last?["inlineData"] as? [String: Any])
        #expect(inline["mimeType"] as? String == "image/jpeg")
        #expect(inline["data"] as? String == jpeg.base64EncodedString())
    }

    @Test func retriesRateLimitWithBackoffThenSucceeds() async throws {
        let (service, transport, sleeper) = makeService([(429, rateLimitBody), (429, rateLimitBody), (200, okBody(mealJSON))])
        let foods = try await service.analyze(jpeg: jpeg, apiKey: "k")
        #expect(foods.count == 3)
        #expect(await transport.requests.count == 3)
        #expect(await sleeper.delays == [.seconds(2), .seconds(4)])
    }

    @Test func givesUpAfterThreeRateLimitRetries() async {
        let (service, transport, sleeper) = makeService(Array(repeating: (429, rateLimitBody), count: 5))
        await #expect(throws: GeminiError.rateLimited) {
            try await service.analyze(jpeg: jpeg, apiKey: "k")
        }
        #expect(await transport.requests.count == 4)
        #expect(await sleeper.delays == [.seconds(2), .seconds(4), .seconds(8)])
    }

    @Test func serverErrorIsRetriedOnce() async {
        let (service, transport, _) = makeService([(503, "{}"), (503, "{}")])
        await #expect(throws: GeminiError.server(503)) {
            try await service.analyze(jpeg: jpeg, apiKey: "k")
        }
        #expect(await transport.requests.count == 2)
    }

    @Test func invalidKeyIsDetected() async {
        let (service, _, _) = makeService([(400, invalidKeyBody)])
        await #expect(throws: GeminiError.invalidKey("API key not valid. Please pass a valid API key.")) {
            try await service.analyze(jpeg: jpeg, apiKey: "mala")
        }
    }

    @Test func forbiddenIsReported() async throws {
        let (service, _, _) = makeService([(403, #"{"error":{"code":403,"message":"Permission denied","status":"PERMISSION_DENIED"}}"#)])
        do {
            _ = try await service.analyze(jpeg: jpeg, apiKey: "k")
            Issue.record("debería fallar")
        } catch let error as GeminiError {
            #expect(error.isKeyProblem)
        }
    }

    @Test func emptyKeyNeverHitsTheNetwork() async {
        let (service, transport, _) = makeService([])
        await #expect(throws: GeminiError.missingKey) {
            try await service.analyze(jpeg: jpeg, apiKey: "   ")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func offlineIsMapped() async {
        let service = GeminiService(transport: { _ in throw URLError(.notConnectedToInternet) }, sleep: { _ in })
        await #expect(throws: GeminiError.offline) {
            try await service.analyze(jpeg: jpeg, apiKey: "k")
        }
    }
}

struct ScanMatcherTests {
    private let catalog = [
        Food(name: "Arroz, blanco, cocido", source: .bedca, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3),
        Food(name: "Arroz, integral, crudo", source: .bedca, kcal: 350, protein: 7, carbs: 72, fat: 2.5),
        Food(name: "Pollo, pechuga, sin piel, cruda", source: .bedca, kcal: 110, protein: 23, carbs: 0, fat: 1.5),
        Food(name: "Aceite de oliva", source: .seed, kcal: 884, protein: 0, carbs: 0, fat: 100),
        Food(name: "Huevo de gallina, frito", source: .bedca, kcal: 196, protein: 13.6, carbs: 0.8, fat: 15.3),
    ]

    @Test func matchesAllWordsAndComputesMacros() throws {
        let items = ScanMatcher.items(for: [DetectedFood(name: "arroz blanco cocido", grams: 200)], in: catalog)
        let item = try #require(items.first)
        #expect(item.food?.name == "Arroz, blanco, cocido")
        #expect(!item.needsReview)
        #expect(abs(item.macros.kcal - 260) < 0.001)
    }

    @Test func pluralsAndStopWords() {
        #expect(ScanMatcher.bestMatch(for: "huevos fritos", in: catalog)?.food.name == "Huevo de gallina, frito")
        #expect(ScanMatcher.bestMatch(for: "pechuga de pollo", in: catalog)?.food.name == "Pollo, pechuga, sin piel, cruda")
    }

    @Test func unknownFoodNeedsReviewWithZeroMacros() throws {
        let item = try #require(ScanMatcher.items(for: [DetectedFood(name: "sushi de anguila", grams: 120)], in: catalog).first)
        #expect(item.food == nil)
        #expect(item.needsReview)
        #expect(item.macros == Macros())
    }
}

struct KeychainServiceTests {
    @Test func saveReadUpdateDelete() throws {
        let keychain = KeychainService(service: "com.nutriclone.tests.\(UUID().uuidString)")
        let account = "test-account"
        defer { try? keychain.delete(account: account) }

        #expect(try keychain.read(account: account) == nil)
        try keychain.save("primera", account: account)
        #expect(try keychain.read(account: account) == "primera")
        try keychain.save("segunda", account: account)
        #expect(try keychain.read(account: account) == "segunda")
        try keychain.delete(account: account)
        #expect(try keychain.read(account: account) == nil)
        // Borrar lo que no existe no es un error.
        try keychain.delete(account: account)
    }
}
