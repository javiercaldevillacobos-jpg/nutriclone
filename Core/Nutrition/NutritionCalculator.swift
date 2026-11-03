import Foundation

struct NutritionInput: Equatable {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var activity: ActivityLevel
    var goal: GoalType
    var paceKgWeek: Double
    var diet: DietType
}

struct NutritionTargets: Equatable {
    var bmr: Double
    var tdee: Double
    var kcal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var waterMl: Int
}

/// Cálculo de metas diarias.
/// - Metabolismo basal: ecuación de Mifflin-St Jeor (1990).
/// - Gasto total: basal × factor de actividad.
/// - Objetivo: 1 kg de grasa ≈ 7700 kcal; el déficit se limita al 25 % del gasto
///   y nunca baja de un mínimo de seguridad.
enum NutritionCalculator {
    static let kcalPerKgFat = 7700.0
    static let maxDeficitFraction = 0.25
    static let maxSurplus = 500.0
    static let ketoCarbsG = 25.0

    static func minimumKcal(for sex: Sex) -> Double { sex == .female ? 1200 : 1500 }

    static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    static func targets(for input: NutritionInput) -> NutritionTargets {
        let bmr = bmr(sex: input.sex, age: input.age, heightCm: input.heightCm, weightKg: input.weightKg)
        let tdee = bmr * input.activity.factor
        let dailyDelta = input.paceKgWeek * kcalPerKgFat / 7

        var kcal: Double
        switch input.goal {
        case .lose:
            kcal = tdee - min(dailyDelta, tdee * maxDeficitFraction)
            kcal = max(kcal, minimumKcal(for: input.sex))
        case .maintain:
            kcal = tdee
        case .gain:
            kcal = tdee + min(dailyDelta, maxSurplus)
        }
        kcal = (kcal / 10).rounded() * 10

        let macros = macroSplit(kcal: kcal, weightKg: input.weightKg, goal: input.goal, diet: input.diet)
        return NutritionTargets(
            bmr: bmr,
            tdee: tdee,
            kcal: Int(kcal),
            proteinG: macros.protein,
            carbsG: macros.carbs,
            fatG: macros.fat,
            waterMl: waterMl(weightKg: input.weightKg)
        )
    }

    /// Reparte las calorías en gramos de proteína (4 kcal/g), carbohidratos (4) y grasa (9).
    static func macroSplit(kcal: Double, weightKg: Double, goal: GoalType, diet: DietType)
        -> (protein: Int, carbs: Int, fat: Int)
    {
        var proteinPerKg: Double = switch goal {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
        if diet == .highProtein { proteinPerKg += 0.4 }
        // La proteína nunca pasa del 40 % de las calorías.
        let protein = min(proteinPerKg * weightKg, kcal * 0.40 / 4)
        let remaining = kcal - protein * 4

        let carbs: Double
        let fat: Double
        switch diet {
        case .keto:
            carbs = min(ketoCarbsG, remaining / 4)
            fat = (remaining - carbs * 4) / 9
        case .lowCarb:
            carbs = min(kcal * 0.20 / 4, remaining / 4)
            fat = (remaining - carbs * 4) / 9
        case .balanced, .highProtein, .lowFat:
            let fatShare: Double = switch diet {
            case .lowFat: 0.18
            case .highProtein: 0.25
            default: 0.28
            }
            fat = min(kcal * fatShare / 9, remaining / 9)
            carbs = (remaining - fat * 9) / 4
        }
        return (Int(protein.rounded()), Int(max(carbs, 0).rounded()), Int(max(fat, 0).rounded()))
    }

    /// 35 ml por kg, redondeado a vasos de 250 ml, entre 1,5 y 4 litros.
    static func waterMl(weightKg: Double) -> Int {
        let raw = min(max(weightKg * 35, 1500), 4000)
        return Int((raw / 250).rounded()) * 250
    }

    static func age(from birthdate: Date, now: Date = .now) -> Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: now).year ?? 0
    }

    /// Semanas hasta el peso meta al ritmo elegido; nil si ya está o el ritmo es 0.
    static func weeksToGoal(currentKg: Double, targetKg: Double, paceKgWeek: Double) -> Int? {
        let diff = abs(currentKg - targetKg)
        guard diff >= 0.1, paceKgWeek > 0 else { return nil }
        return Int((diff / paceKgWeek).rounded(.up))
    }

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        return weightKg / (m * m)
    }
}
