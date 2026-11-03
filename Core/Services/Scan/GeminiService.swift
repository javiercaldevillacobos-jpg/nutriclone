import Foundation
import UIKit

/// Modelos de la familia Flash con nivel gratuito (comprobado en la documentación de
/// precios de Google AI Studio el 2026-11-03). Si Google cambia los nombres, se edita aquí.
enum GeminiModel: String, CaseIterable, Identifiable, Sendable {
    /// Mejor reconocimiento y estimación de gramos.
    case flash = "gemini-3.6-flash"
    /// Más ligero; suele tener límites gratuitos más altos.
    case flashLite = "gemini-3.5-flash-lite"

    static let `default`: GeminiModel = .flash
    static let storageKey = "geminiModel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: "Gemini Flash (más preciso)"
        case .flashLite: "Gemini Flash-Lite (más peticiones gratis)"
        }
    }
}

enum GeminiError: LocalizedError, Equatable {
    case missingKey
    case rateLimited
    case invalidKey(String?)
    case forbidden(String?)
    case badRequest(String?)
    case server(Int)
    case offline
    case timeout
    case blocked(String)
    case emptyResponse
    case unreadableResponse
    case imageEncoding
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Añade tu clave gratuita de Gemini en Perfil > Escáner de platos."
        case .rateLimited:
            "Has alcanzado el límite gratuito de Gemini por ahora. Espera un minuto y vuelve a intentarlo."
        case .invalidKey:
            "Google no acepta la clave de API. Revísala en Perfil > Escáner de platos."
        case .forbidden:
            "La clave no tiene permiso para usar Gemini. Revísala en Perfil > Escáner de platos o crea una nueva en Google AI Studio."
        case .badRequest(let message):
            "Google rechazó la petición" + (message.map { ": \($0)" } ?? ".")
        case .server(let code):
            "Los servidores de Google están fallando (error \(code)). Inténtalo más tarde."
        case .offline:
            "El escáner necesita conexión a internet."
        case .timeout:
            "Google tardó demasiado en responder. Inténtalo de nuevo."
        case .blocked:
            "Gemini no ha querido analizar esta foto. Prueba con otra en la que solo se vea la comida."
        case .emptyResponse:
            "No hemos reconocido ningún alimento. Prueba con una foto más cercana y con buena luz."
        case .unreadableResponse:
            "La respuesta de Gemini no tenía el formato esperado. Inténtalo de nuevo."
        case .imageEncoding:
            "No se pudo preparar la foto."
        case .network(let message):
            "Error de red: \(message)"
        }
    }

    /// Errores que se arreglan cambiando la clave en ajustes.
    var isKeyProblem: Bool {
        switch self {
        case .missingKey, .invalidKey, .forbidden: true
        default: false
        }
    }
}

/// Cliente de la API de Gemini para el escáner de platos.
///
/// Solo usa la clave que el usuario pega en ajustes (BYOK). No hay ninguna ruta a planes de pago:
/// si la cuota gratuita se agota, Google devuelve 429 y la app espera y, si sigue igual, avisa.
actor GeminiService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    static let shared = GeminiService()

    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/")!
    /// Esperas antes de reintentar un 429: 2 s, 4 s y 8 s (tres reintentos como máximo).
    static let rateLimitBackoff: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]
    static let serverRetryDelay: Duration = .seconds(2)
    static let maxImageSide: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.7

    static let systemPrompt = """
        Eres un nutricionista experto. Analiza la imagen de comida y devuelve EXCLUSIVAMENTE un JSON \
        válido con este esquema, sin texto adicional, sin markdown y sin explicaciones:
        {"foods": [{"name": "nombre del alimento en español", "grams": número_entero}]}
        Reglas:
        - Estima los gramos de forma realista según el tamaño típico de los platos y los alimentos visibles.
        - Cuenta también el aceite o las salsas si se ven claramente.
        - Si no estás seguro de un alimento, no lo incluyas.
        - No inventes alimentos que no estén claramente en la imagen.
        - Usa nombres genéricos y buscables, en singular (ej. "pechuga de pollo", "arroz blanco cocido", "aceite de oliva").
        - Devuelve entre 1 y 10 alimentos. Si no hay comida en la imagen, devuelve {"foods": []}.
        """

    private let transport: Transport
    private let wait: Sleeper

    init(transport: Transport? = nil, sleep: Sleeper? = nil) {
        if let transport {
            self.transport = transport
        } else {
            // Sesión efímera: sin cookies, sin caché en disco, 30 s por petición.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.urlCache = nil
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            self.transport = { request in try await session.data(for: request) }
        }
        self.wait = sleep ?? { duration in try await Task.sleep(for: duration) }
    }

    /// Reduce la foto, la codifica en JPEG y la analiza.
    nonisolated func analyze(image: UIImage, apiKey: String, model: GeminiModel = .default) async throws -> [DetectedFood] {
        guard let jpeg = Self.jpegData(for: image) else { throw GeminiError.imageEncoding }
        return try await analyze(jpeg: jpeg, apiKey: apiKey, model: model)
    }

    func analyze(jpeg: Data, apiKey: String, model: GeminiModel = .default) async throws -> [DetectedFood] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeminiError.missingKey }
        let request = try Self.makeRequest(jpeg: jpeg, apiKey: key, model: model)

        var rateLimitRetries = 0
        var serverRetries = 0
        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport(request)
            } catch let error as URLError {
                throw Self.map(error)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let apiError = GeminiParser.apiError(from: data)

            switch status {
            case 200..<300:
                let foods = try GeminiParser.foods(fromResponse: data)
                guard !foods.isEmpty else { throw GeminiError.emptyResponse }
                return foods
            case 429:
                guard rateLimitRetries < Self.rateLimitBackoff.count else { throw GeminiError.rateLimited }
                try await wait(Self.rateLimitBackoff[rateLimitRetries])
                rateLimitRetries += 1
            case 500, 502, 503, 504:
                guard serverRetries < 1 else { throw GeminiError.server(status) }
                try await wait(Self.serverRetryDelay)
                serverRetries += 1
            case 400:
                if Self.isKeyError(apiError) { throw GeminiError.invalidKey(apiError?.message) }
                throw GeminiError.badRequest(apiError?.message)
            case 401, 403:
                throw GeminiError.forbidden(apiError?.message)
            default:
                throw GeminiError.server(status)
            }
        }
    }

    // MARK: - Petición

    /// La clave va en la cabecera `x-goog-api-key` (la forma que documenta Google) y no en la URL,
    /// para que no quede en registros de proxies ni en informes de errores.
    static func makeRequest(jpeg: Data, apiKey: String, model: GeminiModel) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("\(model.rawValue):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]],
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": "Analiza esta foto de comida y devuelve el JSON."],
                    ["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ],
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Lado mayor como máximo de 1024 px y JPEG al 70 %: unos 100–300 KB, muy lejos del límite de 20 MB.
    static func jpegData(for image: UIImage) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxImageSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    private static func isKeyError(_ error: GoogleAPIErrorEnvelope.Body?) -> Bool {
        guard let error else { return false }
        if error.details?.contains(where: { $0.reason == "API_KEY_INVALID" }) == true { return true }
        return error.message?.localizedCaseInsensitiveContains("api key") == true
    }

    private static func map(_ error: URLError) -> GeminiError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .timedOut:
            .timeout
        default:
            .network(error.localizedDescription)
        }
    }
}
