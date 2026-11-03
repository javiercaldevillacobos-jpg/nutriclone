import Foundation

/// Una fila de la revisión del escáner: lo que vio Gemini y el alimento de la base que le corresponde.
struct ScanItem: Identifiable {
    let id = UUID()
    var detectedName: String
    var grams: Double
    var food: Food?
    /// true si no hubo coincidencia o fue solo parcial: el usuario debe revisarlo.
    var needsReview: Bool
    var include = true

    var macros: Macros {
        guard include, let food else { return Macros() }
        return food.macros(forGrams: grams)
    }
}

/// Cruza los nombres que devuelve Gemini con el catálogo local (BEDCA, foods.json y alimentos propios).
enum ScanMatcher {
    /// Palabras que no ayudan a buscar.
    static let stopWords: Set<String> = [
        "de", "del", "la", "el", "los", "las", "con", "sin", "a", "al", "en", "y", "o", "un", "una", "para",
    ]
    static let minimumScore = 0.6

    static func items(for detected: [DetectedFood], in foods: [Food]) -> [ScanItem] {
        detected.map { item in
            let match = bestMatch(for: item.name, in: foods)
            return ScanItem(
                detectedName: item.name,
                grams: item.grams.rounded(),
                food: match?.food,
                needsReview: match.map { $0.score < 1 } ?? true
            )
        }
    }

    /// Mejor alimento para un nombre, con una puntuación entre 0 y ~1,3 (1 = todas las palabras aparecen).
    static func bestMatch(for name: String, in foods: [Food]) -> (food: Food, score: Double)? {
        let tokens = tokens(of: name)
        guard !tokens.isEmpty else { return nil }
        let query = Food.normalize(name)

        var best: (food: Food, score: Double)?
        for food in foods {
            let matched = tokens.filter { food.searchKey.contains($0) }.count
            guard matched > 0 else { continue }
            var score = Double(matched) / Double(tokens.count)
            // La primera palabra suele ser el alimento principal ("arroz", "pollo").
            if !food.searchKey.contains(tokens[0]) { score -= 0.3 }
            if food.searchKey.hasPrefix(query) || food.searchKey.hasPrefix(tokens[0]) { score += 0.2 }
            if food.source == .bedca || food.source == .user { score += 0.05 }
            // Desempate: nombres más cortos son más genéricos.
            score -= Double(food.searchKey.count) / 10_000
            if score > (best?.score ?? -1) { best = (food, score) }
        }
        guard let best, best.score >= minimumScore else { return nil }
        return best
    }

    /// Palabras normalizadas sin las vacías y en singular aproximado ("huevos" → "huevo").
    static func tokens(of name: String) -> [String] {
        Food.normalize(name)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
            .map { word in
                if word.count > 4, word.hasSuffix("es"), !word.hasSuffix("ses") { return String(word.dropLast(2)) }
                if word.count > 3, word.hasSuffix("s") { return String(word.dropLast()) }
                return word
            }
    }
}
