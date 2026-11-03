import Foundation

enum Sex: String, Codable, ChoiceOption {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Mujer" : "Hombre" }
    var detail: String? { nil }
    var symbol: String { "figure.stand" }
}

enum GoalType: String, Codable, ChoiceOption {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: "Perder grasa"
        case .maintain: "Mantener mi peso"
        case .gain: "Ganar músculo"
        }
    }
    var detail: String? {
        switch self {
        case .lose: "Déficit moderado y proteína alta para conservar músculo"
        case .maintain: "Comer lo que gastas y mejorar la calidad"
        case .gain: "Superávit pequeño para ganar sin acumular grasa"
        }
    }
    var symbol: String {
        switch self {
        case .lose: "arrow.down.right.circle"
        case .maintain: "equal.circle"
        case .gain: "arrow.up.right.circle"
        }
    }
}

enum ActivityLevel: String, Codable, ChoiceOption {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: "Poco activo"
        case .light: "Algo activo"
        case .moderate: "Activo"
        case .active: "Muy activo"
        case .veryActive: "Atleta"
        }
    }
    var detail: String? {
        switch self {
        case .sedentary: "Trabajo sentado y casi sin ejercicio"
        case .light: "Caminas a diario o entrenas 1–2 días"
        case .moderate: "Entrenas 3–5 días a la semana"
        case .active: "Entrenas fuerte 6–7 días o trabajo físico"
        case .veryActive: "Dos sesiones al día o trabajo muy físico"
        }
    }
    var symbol: String {
        switch self {
        case .sedentary: "chair.lounge"
        case .light: "figure.walk"
        case .moderate: "figure.run"
        case .active: "figure.strengthtraining.traditional"
        case .veryActive: "flame"
        }
    }
    /// Factor sobre el metabolismo basal.
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

enum DietType: String, Codable, ChoiceOption {
    case balanced, highProtein, lowCarb, keto, lowFat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balanced: "Equilibrada"
        case .highProtein: "Alta en proteína"
        case .lowCarb: "Baja en carbohidratos"
        case .keto: "Cetogénica"
        case .lowFat: "Baja en grasa"
        }
    }
    var detail: String? {
        switch self {
        case .balanced: "Reparto clásico, fácil de mantener"
        case .highProtein: "Más saciante, ideal si entrenas fuerza"
        case .lowCarb: "Unos 20 % de las calorías en carbohidratos"
        case .keto: "Menos de 30 g de carbohidratos al día"
        case .lowFat: "Más carbohidratos, grasa por debajo del 20 %"
        }
    }
    var symbol: String {
        switch self {
        case .balanced: "circle.grid.2x2"
        case .highProtein: "dumbbell"
        case .lowCarb: "leaf"
        case .keto: "drop.triangle"
        case .lowFat: "carrot"
        }
    }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast, morningSnack, lunch, afternoonSnack, dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Desayuno"
        case .morningSnack: "Media mañana"
        case .lunch: "Comida"
        case .afternoonSnack: "Merienda"
        case .dinner: "Cena"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .morningSnack: "cup.and.saucer"
        case .lunch: "sun.max"
        case .afternoonSnack: "takeoutbag.and.cup.and.straw"
        case .dinner: "moon.stars"
        }
    }

    /// Comidas que se muestran según cuántas hace el usuario al día.
    static func slots(for mealsPerDay: Int) -> [MealSlot] {
        switch mealsPerDay {
        case ...3: [.breakfast, .lunch, .dinner]
        case 4: [.breakfast, .lunch, .afternoonSnack, .dinner]
        default: allCases
        }
    }

    /// Comida que toca según la hora, para preseleccionarla.
    static func suggested(at date: Date = .now, mealsPerDay: Int) -> MealSlot {
        let hour = Calendar.current.component(.hour, from: date)
        let guess: MealSlot = switch hour {
        case ..<11: .breakfast
        case 11..<13: .morningSnack
        case 13..<17: .lunch
        case 17..<20: .afternoonSnack
        default: .dinner
        }
        let visible = slots(for: mealsPerDay)
        return visible.contains(guess) ? guess : (visible.last { $0.order <= guess.order } ?? .breakfast)
    }

    var order: Int { MealSlot.allCases.firstIndex(of: self) ?? 0 }
}

enum LogMethod: String, Codable {
    case search, barcode, photo, voice, text, plan, quick
}

enum FoodSource: String, Codable {
    /// foods.json incluido (genéricos de referencia USDA).
    case seed
    /// BEDCA (AESAN), cargado desde bedca_foods.csv.
    case bedca
    case user
    case openFoodFacts
}
