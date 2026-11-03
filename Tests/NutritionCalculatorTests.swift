import Foundation
import Testing
@testable import NutriClone

struct NutritionCalculatorTests {
    private func input(
        sex: Sex = .male, age: Int = 30, height: Double = 180, weight: Double = 80,
        activity: ActivityLevel = .moderate, goal: GoalType = .maintain,
        pace: Double = 0.5, diet: DietType = .balanced
    ) -> NutritionInput {
        NutritionInput(sex: sex, age: age, heightCm: height, weightKg: weight,
                       activity: activity, goal: goal, paceKgWeek: pace, diet: diet)
    }

    @Test func bmrMale() {
        // 10·80 + 6,25·180 − 5·30 + 5
        #expect(NutritionCalculator.bmr(sex: .male, age: 30, heightCm: 180, weightKg: 80) == 1780)
    }

    @Test func bmrFemale() {
        // 10·60 + 6,25·165 − 5·25 − 161
        let bmr = NutritionCalculator.bmr(sex: .female, age: 25, heightCm: 165, weightKg: 60)
        #expect(abs(bmr - 1345.25) < 0.001)
    }

    @Test func maintainEqualsTdee() {
        let t = NutritionCalculator.targets(for: input())
        #expect(abs(Double(t.kcal) - 1780 * 1.55) <= 5)
    }

    @Test func losingCreatesDeficit() {
        let maintain = NutritionCalculator.targets(for: input())
        let lose = NutritionCalculator.targets(for: input(goal: .lose, pace: 0.5))
        // 0,5 kg/semana ≈ 550 kcal/día
        #expect(maintain.kcal - lose.kcal >= 540)
        #expect(maintain.kcal - lose.kcal <= 560)
    }

    @Test func deficitIsCappedAndFloored() {
        let small = input(sex: .female, age: 60, height: 150, weight: 48,
                          activity: .sedentary, goal: .lose, pace: 1.0)
        let t = NutritionCalculator.targets(for: small)
        #expect(Double(t.kcal) >= NutritionCalculator.minimumKcal(for: .female))
    }

    @Test func surplusIsCapped() {
        let maintain = NutritionCalculator.targets(for: input())
        let gain = NutritionCalculator.targets(for: input(goal: .gain, pace: 1.0))
        #expect(gain.kcal - maintain.kcal <= 510)
    }

    @Test(arguments: [DietType.balanced, .highProtein, .lowCarb, .keto, .lowFat])
    func macrosAddUpToCalories(diet: DietType) {
        for goal in [GoalType.lose, .maintain, .gain] {
            let t = NutritionCalculator.targets(for: input(goal: goal, diet: diet))
            let fromMacros = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
            #expect(abs(fromMacros - t.kcal) <= 15, "\(diet) \(goal): \(fromMacros) vs \(t.kcal)")
        }
    }

    @Test func ketoKeepsCarbsLow() {
        let t = NutritionCalculator.targets(for: input(diet: .keto))
        #expect(t.carbsG <= 30)
    }

    @Test func waterIsRoundedToGlasses() {
        #expect(NutritionCalculator.waterMl(weightKg: 70) % 250 == 0)
        #expect(NutritionCalculator.waterMl(weightKg: 30) == 1500)
        #expect(NutritionCalculator.waterMl(weightKg: 200) == 4000)
    }

    @Test func weeksToGoal() {
        #expect(NutritionCalculator.weeksToGoal(currentKg: 80, targetKg: 75, paceKgWeek: 0.5) == 10)
        #expect(NutritionCalculator.weeksToGoal(currentKg: 80, targetKg: 80, paceKgWeek: 0.5) == nil)
    }

    @Test func mealSlotsFollowMealsPerDay() {
        #expect(MealSlot.slots(for: 3) == [.breakfast, .lunch, .dinner])
        #expect(MealSlot.slots(for: 4).count == 4)
        #expect(MealSlot.slots(for: 5).count == 5)
    }

    @Test func searchKeyIgnoresAccents() {
        #expect(Food.normalize("Plátano  ") == "platano")
        #expect(Food.normalize("JAMÓN Serrano") == "jamon serrano")
    }
}
