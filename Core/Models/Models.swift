import Foundation
import SwiftData

/// Perfil y metas del usuario. En la v0.1 hay un único perfil y la meta vive en él;
/// el esquema de la nube (replica/schema.sql) separa `profiles` y `goals` para guardar historial.
@Model
final class UserProfile {
    var name: String
    var sexRaw: String
    var birthdate: Date
    var heightCm: Double
    var startWeightKg: Double
    var createdAt: Date

    var goalRaw: String
    var activityRaw: String
    var dietRaw: String
    var targetWeightKg: Double
    var paceKgWeek: Double
    var mealsPerDay: Int

    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var waterMl: Int

    init(
        name: String,
        sex: Sex,
        birthdate: Date,
        heightCm: Double,
        startWeightKg: Double,
        goal: GoalType,
        activity: ActivityLevel,
        diet: DietType,
        targetWeightKg: Double,
        paceKgWeek: Double,
        mealsPerDay: Int,
        targets: NutritionTargets
    ) {
        self.name = name
        self.sexRaw = sex.rawValue
        self.birthdate = birthdate
        self.heightCm = heightCm
        self.startWeightKg = startWeightKg
        self.createdAt = .now
        self.goalRaw = goal.rawValue
        self.activityRaw = activity.rawValue
        self.dietRaw = diet.rawValue
        self.targetWeightKg = targetWeightKg
        self.paceKgWeek = paceKgWeek
        self.mealsPerDay = mealsPerDay
        self.kcal = targets.kcal
        self.proteinG = targets.proteinG
        self.carbsG = targets.carbsG
        self.fatG = targets.fatG
        self.waterMl = targets.waterMl
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .female }
        set { sexRaw = newValue.rawValue }
    }
    var goal: GoalType {
        get { GoalType(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }
    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .light }
        set { activityRaw = newValue.rawValue }
    }
    var diet: DietType {
        get { DietType(rawValue: dietRaw) ?? .balanced }
        set { dietRaw = newValue.rawValue }
    }

    var age: Int { NutritionCalculator.age(from: birthdate) }

    var goalMacros: Macros {
        Macros(kcal: Double(kcal), protein: Double(proteinG), carbs: Double(carbsG), fat: Double(fatG))
    }

    func apply(_ targets: NutritionTargets) {
        kcal = targets.kcal
        proteinG = targets.proteinG
        carbsG = targets.carbsG
        fatG = targets.fatG
        waterMl = targets.waterMl
    }
}

/// Alimento. Valores por 100 g (o 100 ml).
@Model
final class Food {
    #Index<Food>([\.searchKey], [\.sourceRaw])

    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var sourceRaw: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    /// Ración típica opcional, por ejemplo "1 unidad mediana" = 180 g.
    var servingLabel: String?
    var servingGrams: Double?
    var isFavorite: Bool
    var lastUsedAt: Date?
    /// Nombre en minúsculas y sin tildes, para buscar.
    var searchKey: String

    // Nutrientes opcionales (por 100 g). Hoy solo los rellena BEDCA.
    // Añadidos en v0.2: al ser opcionales, SwiftData migra las bases existentes sin pasos extra.
    var bedcaID: Int? = nil
    var saturatedFat: Double? = nil
    var cholesterolMg: Double? = nil
    var sodiumMg: Double? = nil
    var potassiumMg: Double? = nil
    var calciumMg: Double? = nil
    var ironMg: Double? = nil
    var vitaminCMg: Double? = nil

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        source: FoodSource,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double? = nil,
        sugar: Double? = nil,
        servingLabel: String? = nil,
        servingGrams: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.sourceRaw = source.rawValue
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.isFavorite = false
        self.lastUsedAt = nil
        self.searchKey = Food.normalize([name, brand].compactMap { $0 }.joined(separator: " "))
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .seed }

    func macros(forGrams grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Un alimento registrado en una comida de un día. Guarda una copia de nombre y macros
/// para que el diario no cambie si luego se edita o borra el alimento.
@Model
final class FoodLog {
    var id: UUID
    /// Inicio del día local al que pertenece el registro.
    var day: Date
    var mealRaw: String
    var foodID: UUID?
    var name: String
    var grams: Double
    var portionText: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var methodRaw: String
    var loggedAt: Date

    init(day: Date, meal: MealSlot, food: Food, grams: Double, portionText: String, method: LogMethod = .search) {
        let m = food.macros(forGrams: grams)
        self.id = UUID()
        self.day = day.startOfDay
        self.mealRaw = meal.rawValue
        self.foodID = food.id
        self.name = food.name
        self.grams = grams
        self.portionText = portionText
        self.kcal = m.kcal
        self.protein = m.protein
        self.carbs = m.carbs
        self.fat = m.fat
        self.methodRaw = method.rawValue
        self.loggedAt = .now
    }

    var meal: MealSlot { MealSlot(rawValue: mealRaw) ?? .breakfast }
    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

@Model
final class BodyEntry {
    var id: UUID
    var day: Date
    var weightKg: Double
    var waistCm: Double?

    init(day: Date, weightKg: Double, waistCm: Double? = nil) {
        self.id = UUID()
        self.day = day.startOfDay
        self.weightKg = weightKg
        self.waistCm = waistCm
    }
}

@Model
final class WaterLog {
    var id: UUID
    var day: Date
    var ml: Int
    var loggedAt: Date

    init(day: Date, ml: Int) {
        self.id = UUID()
        self.day = day.startOfDay
        self.ml = ml
        self.loggedAt = .now
    }
}

struct Macros: Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
}

extension Sequence where Element == FoodLog {
    var totals: Macros { reduce(Macros()) { $0 + $1.macros } }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// "Hoy", "Ayer", "Mañana" o la fecha corta.
    var relativeDayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Hoy" }
        if cal.isDateInYesterday(self) { return "Ayer" }
        if cal.isDateInTomorrow(self) { return "Mañana" }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
