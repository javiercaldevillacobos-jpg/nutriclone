import Foundation

/// Un alimento que Gemini ve en la foto, con los gramos estimados.
struct DetectedFood: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let grams: Double

    init(name: String, grams: Double) {
        self.id = UUID()
        self.name = name
        self.grams = grams
    }

    private enum CodingKeys: String, CodingKey {
        case name, grams
    }

    /// Tolera "grams" como entero, decimal o texto ("150", "150 g").
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = try? container.decode(Double.self, forKey: .grams) {
            grams = number
        } else if let text = try? container.decode(String.self, forKey: .grams) {
            let digits = text.filter { $0.isNumber || $0 == "." || $0 == "," }
            grams = Double(digits.replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            grams = 0
        }
    }

    static func == (a: DetectedFood, b: DetectedFood) -> Bool {
        a.name == b.name && a.grams == b.grams
    }
}
