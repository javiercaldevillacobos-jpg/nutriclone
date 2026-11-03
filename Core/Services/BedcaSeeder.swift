import Foundation
import SwiftData

/// Alimento leído de BEDCA, ya en las unidades de la app (kcal, g, mg) y por 100 g de porción comestible.
struct BedcaFood: Sendable, Equatable {
    let id: Int
    let name: String
    let englishName: String?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let alcohol: Double?
    let fiber: Double?
    let sugar: Double?
    let saturatedFat: Double?
    let cholesterolMg: Double?
    let sodiumMg: Double?
    let potassiumMg: Double?
    let calciumMg: Double?
    let ironMg: Double?
    let vitaminCMg: Double?
}

/// Lee `bedca_foods.csv` (dataset "BEDCA Food Composition Dataset 2026", Zenodo
/// 10.5281/zenodo.22017001): tabla ancha con columnas de metadatos y, por cada componente
/// EuroFIR, un par `CÓDIGO,CÓDIGO_unit` (por ejemplo `ENERC,ENERC_unit` = `1215.5,kJ`).
///
/// Los valores del fichero no se modifican; solo se convierten de unidad al cargarlos
/// (kJ → kcal, µg/mg → g cuando hace falta) porque la unidad viene en cada celda.
enum BedcaImporter {
    static let resourceName = "bedca_foods"
    static let attribution = "AESAN/BEDCA Base de Datos Española de Composición de Alimentos v1.0 (2010)"
    static let websiteURL = URL(string: "https://www.bedca.net/")!
    static let kJPerKcal = 4.184

    static var bundledURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "csv")
    }

    enum ImportError: Error, Equatable {
        case empty
        case missingColumn(String)
    }

    struct Report: Sendable {
        let foods: [BedcaFood]
        /// Filas sin energía o sin nombre, que no se cargan.
        let skipped: Int
    }

    enum TargetUnit {
        case kcal, g, mg
    }

    // MARK: - Lectura

    static func load(url: URL) throws -> Report {
        let data = try Data(contentsOf: url)
        return try parse(csv: String(decoding: data, as: UTF8.self))
    }

    static func parse(csv text: String) throws -> Report {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { throw ImportError.empty }

        var column: [String: Int] = [:]
        for (index, name) in header.enumerated() {
            column[name.trimmingCharacters(in: .whitespaces)] = index
        }
        for required in ["f_id", "f_ori_name", "ENERC", "ENERC_unit"] where column[required] == nil {
            throw ImportError.missingColumn(required)
        }

        func cell(_ row: [String], _ name: String) -> String? {
            guard let i = column[name], i < row.count else { return nil }
            let value = row[i].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }

        /// Valor de un componente convertido a la unidad pedida; nil si falta o no se reconoce.
        func value(_ row: [String], _ code: String, as target: TargetUnit) -> Double? {
            guard let raw = cell(row, code), let amount = Self.number(raw) else { return nil }
            let unit = cell(row, code + "_unit") ?? defaultUnit(for: target)
            return convert(amount, from: unit, to: target)
        }

        var foods: [BedcaFood] = []
        var skipped = 0
        for row in rows.dropFirst() {
            guard let idText = cell(row, "f_id"), let id = Int(idText),
                  let name = cell(row, "f_ori_name"),
                  let kcal = value(row, "ENERC", as: .kcal)
            else {
                skipped += 1
                continue
            }
            foods.append(BedcaFood(
                id: id,
                name: name,
                englishName: cell(row, "f_eng_name"),
                kcal: kcal,
                protein: value(row, "PROT", as: .g) ?? 0,
                carbs: value(row, "CHO", as: .g) ?? 0,
                fat: value(row, "FAT", as: .g) ?? 0,
                alcohol: value(row, "ALC", as: .g),
                fiber: value(row, "FIBT", as: .g),
                sugar: value(row, "SUGAR", as: .g),
                saturatedFat: value(row, "FASAT", as: .g),
                cholesterolMg: value(row, "CHORL", as: .mg),
                sodiumMg: value(row, "NA", as: .mg),
                potassiumMg: value(row, "K", as: .mg),
                calciumMg: value(row, "CA", as: .mg),
                ironMg: value(row, "FE", as: .mg),
                vitaminCMg: value(row, "VITC", as: .mg)
            ))
        }
        return Report(foods: foods, skipped: skipped)
    }

    // MARK: - Unidades

    /// Acepta punto o coma decimal ("0.7" o "0,7").
    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func convert(_ value: Double, from unit: String, to target: TargetUnit) -> Double? {
        let u = unit.trimmingCharacters(in: .whitespaces).lowercased()
        if target == .kcal {
            switch u {
            case "kcal": return value
            case "kj": return value / kJPerKcal
            default: return nil
            }
        }
        let grams: Double
        switch u {
        case "g": grams = value
        case "mg": grams = value / 1_000
        case "ug", "µg", "μg", "mcg": grams = value / 1_000_000
        default: return nil
        }
        return target == .g ? grams : grams * 1_000
    }

    private static func defaultUnit(for target: TargetUnit) -> String {
        switch target {
        case .kcal: "kcal"
        case .g: "g"
        case .mg: "mg"
        }
    }

    // MARK: - Duplicados

    /// Claves para detectar que un alimento genérico de foods.json ya está en BEDCA:
    /// el nombre completo sin comas ("pan blanco") y el primer tramo ("manzana" de "Manzana, golden, con piel").
    static func duplicateKeys(forBedcaName name: String) -> [String] {
        let normalized = Food.normalize(name)
        let first = normalized.split(separator: ",").first.map(String.init) ?? normalized
        return [compact(normalized), compact(first)]
    }

    static func duplicateKey(forName name: String) -> String {
        compact(Food.normalize(name))
    }

    private static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Carga BEDCA en SwiftData la primera vez (o tras borrar los datos). Lee y convierte
/// el CSV fuera del hilo principal; solo las inserciones van en el contexto principal.
@MainActor
enum BedcaSeeder {
    @discardableResult
    static func seedIfNeeded(_ context: ModelContext) async -> Int {
        let bedca = FoodSource.bedca.rawValue
        let existing = (try? context.fetchCount(FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.sourceRaw == bedca }
        ))) ?? 0
        guard existing == 0, let url = BedcaImporter.bundledURL else { return 0 }

        let report = await Task.detached(priority: .userInitiated) {
            try? BedcaImporter.load(url: url)
        }.value
        guard let report else { return 0 }

        for item in report.foods {
            context.insert(Food.fromBedca(item))
        }
        try? context.save()
        return report.foods.count
    }

    /// Claves de duplicado de todos los alimentos BEDCA ya cargados.
    static func loadedKeys(in context: ModelContext) -> Set<String> {
        let bedca = FoodSource.bedca.rawValue
        let foods = (try? context.fetch(FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.sourceRaw == bedca }
        ))) ?? []
        return Set(foods.flatMap { BedcaImporter.duplicateKeys(forBedcaName: $0.name) })
    }
}

/// Prepara el catálogo de alimentos: BEDCA como fuente principal (si el CSV está en el
/// bundle) y foods.json como complemento para lo que BEDCA no tiene (platos, marcas).
@MainActor
enum FoodCatalog {
    private static var isPreparing = false

    static func prepare(_ context: ModelContext) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        await BedcaSeeder.seedIfNeeded(context)
        let bedcaKeys = BedcaSeeder.loadedKeys(in: context)
        FoodSeeder.seedIfNeeded(context, skipping: bedcaKeys)
        FoodSeeder.removeDuplicates(context, of: bedcaKeys)
    }
}

extension Food {
    static func fromBedca(_ item: BedcaFood) -> Food {
        let food = Food(
            name: item.name,
            source: .bedca,
            kcal: item.kcal,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            fiber: item.fiber,
            sugar: item.sugar
        )
        food.bedcaID = item.id
        food.saturatedFat = item.saturatedFat
        food.cholesterolMg = item.cholesterolMg
        food.sodiumMg = item.sodiumMg
        food.potassiumMg = item.potassiumMg
        food.calciumMg = item.calciumMg
        food.ironMg = item.ironMg
        food.vitaminCMg = item.vitaminCMg
        return food
    }
}
