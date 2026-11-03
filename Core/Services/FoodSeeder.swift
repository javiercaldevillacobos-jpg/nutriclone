import Foundation
import SwiftData

/// Carga la base de alimentos incluida (Resources/foods.json). Con BEDCA cargado actúa
/// de complemento: se salta los alimentos que BEDCA ya tiene (ver `BedcaImporter.duplicateKeys`).
enum FoodSeeder {
    private struct SeedFood: Decodable {
        let n: String       // nombre
        let k: Double       // kcal / 100 g
        let p: Double       // proteína g
        let c: Double       // carbohidratos g
        let f: Double       // grasa g
        let fi: Double?     // fibra g
        let s: Double?      // azúcares g
        let u: String?      // ración típica, texto
        let g: Double?      // ración típica, gramos
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext, skipping bedcaKeys: Set<String> = []) {
        let seed = FoodSource.seed.rawValue
        let seeded = (try? context.fetchCount(FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.sourceRaw == seed }
        ))) ?? 0
        guard seeded == 0,
              let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SeedFood].self, from: data)
        else { return }

        for item in items where !bedcaKeys.contains(BedcaImporter.duplicateKey(forName: item.n)) {
            context.insert(Food(
                name: item.n,
                source: .seed,
                kcal: item.k,
                protein: item.p,
                carbs: item.c,
                fat: item.f,
                fiber: item.fi,
                sugar: item.s,
                servingLabel: item.u,
                servingGrams: item.g
            ))
        }
        try? context.save()
    }

    /// Para instalaciones que ya tenían foods.json antes de añadir BEDCA: borra los genéricos
    /// repetidos, salvo los que el usuario marcó como favoritos o ya ha usado.
    @MainActor
    static func removeDuplicates(_ context: ModelContext, of bedcaKeys: Set<String>) {
        guard !bedcaKeys.isEmpty else { return }
        let seed = FoodSource.seed.rawValue
        let foods = (try? context.fetch(FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.sourceRaw == seed }
        ))) ?? []
        var removed = 0
        for food in foods
        where !food.isFavorite && food.lastUsedAt == nil
            && bedcaKeys.contains(BedcaImporter.duplicateKey(forName: food.name)) {
            context.delete(food)
            removed += 1
        }
        if removed > 0 { try? context.save() }
    }
}

/// Búsqueda de alimentos sin tildes ni mayúsculas. Separada de la vista para poder probarla.
enum FoodSearch {
    /// Todas las palabras de la consulta deben aparecer en la clave del alimento.
    static func matches(searchKey: String, query: String) -> Bool {
        let words = Food.normalize(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { searchKey.contains($0) }
    }

    /// Primero lo que empieza por la consulta, luego lo propio y BEDCA, luego lo más corto.
    static func rank(_ foods: [Food], query: String, limit: Int = 60) -> [Food] {
        let q = Food.normalize(query)
        guard !q.isEmpty else { return [] }
        return foods
            .filter { matches(searchKey: $0.searchKey, query: q) }
            .sorted { a, b in
                let aPrefix = a.searchKey.hasPrefix(q)
                let bPrefix = b.searchKey.hasPrefix(q)
                if aPrefix != bPrefix { return aPrefix }
                let aRank = sourceRank(a.source)
                let bRank = sourceRank(b.source)
                if aRank != bRank { return aRank < bRank }
                return a.searchKey.count < b.searchKey.count
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func sourceRank(_ source: FoodSource) -> Int {
        switch source {
        case .user: 0
        case .bedca: 1
        case .seed: 2
        case .openFoodFacts: 3
        }
    }
}
