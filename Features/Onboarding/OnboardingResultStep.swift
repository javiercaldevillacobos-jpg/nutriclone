import SwiftUI

/// S03: metas calculadas y fecha estimada para llegar al peso meta.
struct OnboardingResultStep: View {
    let draft: OnboardingDraft

    private var targets: NutritionTargets { draft.targets }

    private var goalDate: Date? {
        guard draft.goal != .maintain,
              let weeks = NutritionCalculator.weeksToGoal(
                currentKg: draft.weightKg, targetKg: draft.targetWeightKg, paceKgWeek: draft.paceKgWeek)
        else { return nil }
        return Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: .now)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Text(draft.name.isEmpty ? "Tu plan está listo" : "\(draft.name), tu plan está listo")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressRing(progress: 1) {
                VStack(spacing: 0) {
                    Text("\(targets.kcal)")
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    Text("kcal al día")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: DS.Size.ringLarge, height: DS.Size.ringLarge)
            .accessibilityElement(children: .combine)

            HStack(spacing: DS.Spacing.l) {
                MacroBar(title: "Proteína", value: Double(targets.proteinG), goal: Double(targets.proteinG), color: .protein)
                MacroBar(title: "Carbohidratos", value: Double(targets.carbsG), goal: Double(targets.carbsG), color: .carbs)
                MacroBar(title: "Grasa", value: Double(targets.fatG), goal: Double(targets.fatG), color: .fat)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                if let goalDate {
                    Label {
                        Text("Al ritmo elegido llegarías a **\(draft.targetWeightKg.formatted()) kg** hacia el **\(goalDate.formatted(date: .long, time: .omitted))**.")
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                }
                Label("Gastas unas \(Int(targets.tdee.rounded())) kcal al día; en reposo, \(Int(targets.bmr.rounded())).",
                      systemImage: "flame")
                Label("Bebe unos \((Double(targets.waterMl) / 1000).formatted()) litros de agua al día.",
                      systemImage: "drop")
                if draft.goal == .lose && Double(targets.kcal) <= NutritionCalculator.minimumKcal(for: draft.sex) {
                    Label("Hemos subido las calorías al mínimo recomendado. Si quieres bajar más, consúltalo con un profesional.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.over)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.l)
            .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(Color.card))

            Text("Son estimaciones generales y no sustituyen el consejo de un profesional sanitario.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
