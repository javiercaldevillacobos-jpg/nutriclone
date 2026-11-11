import Foundation

/// Producto leído de Open Food Facts, en las unidades de la app y por 100 g (o 100 ml).
/// `kcal` y los macros pueden faltar: entonces el usuario los completa con la etiqueta.
struct OFFProduct: Equatable, Sendable {
    let barcode: String
    let name: String?
    let brand: String?
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let saturatedFat: Double?
    let sodiumMg: Double?
    let servingLabel: String?
    let servingGrams: Double?

    /// Tiene lo mínimo para registrarlo sin preguntar: nombre y calorías.
    var isComplete: Bool { (name?.isEmpty == false) && kcal != nil }
}

enum OpenFoodFactsError: LocalizedError, Equatable {
    case invalidBarcode
    case offline
    case timeout
    case rateLimited
    case server(Int)
    case unreadableResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: "El código no se ha leído bien. Prueba a escanearlo otra vez."
        case .offline: "Para buscar el producto hace falta conexión a internet."
        case .timeout: "Open Food Facts tardó demasiado en responder."
        case .rateLimited: "Demasiadas búsquedas seguidas. Espera un minuto."
        case .server(let code): "Open Food Facts no responde (error \(code)). Inténtalo más tarde."
        case .unreadableResponse: "La respuesta de Open Food Facts no tenía el formato esperado."
        case .network(let message): "Error de red: \(message)"
        }
    }
}

/// Cliente de la API pública de Open Food Facts (sin clave). Base de datos abierta bajo
/// licencia ODbL: la app la cita en el detalle del alimento y en Perfil > Fuentes de datos.
actor OpenFoodFactsService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = OpenFoodFactsService()
    static let baseURL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!
    static let websiteURL = URL(string: "https://world.openfoodfacts.org/")!
    /// Open Food Facts pide identificar la app en el User-Agent.
    static let userAgent = "NutriClone/0.4 (iOS; https://github.com/javiercaldevillacobos-jpg/nutriclone)"
    static let fields = [
        "code", "product_name", "product_name_es", "generic_name", "brands",
        "serving_size", "serving_quantity", "nutriments",
    ]

    private let transport: Transport

    init(transport: Transport? = nil) {
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: configuration)
            self.transport = { request in try await session.data(for: request) }
        }
    }

    /// Busca un producto. nil si Open Food Facts no lo tiene.
    func product(barcode raw: String) async throws -> OFFProduct? {
        guard let barcode = Barcode.normalize(raw) else { throw OpenFoodFactsError.invalidBarcode }
        let request = Self.makeRequest(barcode: barcode)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw OpenFoodFactsError.offline
            case .timedOut: throw OpenFoodFactsError.timeout
            default: throw OpenFoodFactsError.network(error.localizedDescription)
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200, 404:
            // Producto no encontrado: 404 o 200 con "status": 0.
            return try Self.parse(data, barcode: barcode)
        case 429:
            throw OpenFoodFactsError.rateLimited
        default:
            throw OpenFoodFactsError.server(status)
        }
    }

    static func makeRequest(barcode: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(barcode).json"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Lee la respuesta con JSONSerialization porque los números a veces llegan como texto.
    static func parse(_ data: Data, barcode: String) throws -> OFFProduct? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OpenFoodFactsError.unreadableResponse
        }
        guard number(root["status"]) == 1, let product = root["product"] as? [String: Any] else {
            return nil
        }
        let n = product["nutriments"] as? [String: Any] ?? [:]

        func text(_ key: String) -> String? {
            let value = (product[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        func per100(_ key: String) -> Double? { number(n["\(key)_100g"]) }

        let kcal = per100("energy-kcal")
            ?? per100("energy-kj").map { $0 / BedcaImporter.kJPerKcal }
            ?? per100("energy").map { $0 / BedcaImporter.kJPerKcal }   // "energy" va en kJ
        let brand = text("brands")?.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var servingLabel = text("serving_size")
        var servingGrams = number(product["serving_quantity"])
        if servingGrams == nil || servingGrams! <= 0 || servingGrams! > 2000 {
            servingLabel = nil
            servingGrams = nil
        }

        return OFFProduct(
            barcode: barcode,
            name: text("product_name_es") ?? text("product_name") ?? text("generic_name"),
            brand: brand,
            kcal: kcal,
            protein: per100("proteins"),
            carbs: per100("carbohydrates"),
            fat: per100("fat"),
            fiber: per100("fiber"),
            sugar: per100("sugars"),
            saturatedFat: per100("saturated-fat"),
            sodiumMg: per100("sodium").map { $0 * 1000 },    // viene en gramos
            servingLabel: servingLabel,
            servingGrams: servingGrams
        )
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: d
        case let i as Int: Double(i)
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }
}
