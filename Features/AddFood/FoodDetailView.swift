import SwiftUI
import SwiftData

/// S08: detalle de un alimento, elegir ración y añadirlo al diario.
struct FoodDetailView: View {
    enum Unit: Hashable {
        case grams, serving
    }

    @Bindable var food: Food
    let day: Date
    let mealsPerDay: Int
    let onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @State private var meal: MealSlot
    @State private var unit: Unit
    @State private var amount: Double
    @State private var added = false

    init(food: Food, meal: MealSlot, day: Date, mealsPerDay: Int, onAdded: @escaping () -> Void) {
        _food = Bindable(food)
        self.day = day
        self.mealsPerDay = mealsPerDay
        self.onAdded = onAdded
        _meal = State(initialValue: meal)
        let hasServing = food.servingGrams != nil
        _unit = State(initialValue: hasServing ? .serving : .grams)
        _amount = State(initialValue: hasServing ? 1 : 100)
    }

    private var grams: Double {
        switch unit {
        case .grams: amount
        case .serving: amount * (food.servingGrams ?? 100)
        }
    }

    private var macros: Macros { food.macros(forGrams: grams) }

    private var portionText: String {
        switch unit {
        case .grams:
            return "\(Int(grams.rounded())) g"
        case .serving:
            let label = food.servingLabel ?? "ración"
            let count = amount.formatted(.number.precision(.fractionLength(0...2)))
            return amount == 1 ? "\(label) · \(Int(grams.rounded())) g" : "\(count) × \(label) · \(Int(grams.rounded())) g"
        }
    }

    /// Micronutrientes disponibles (mg por 100 g), en el orden en que se muestran.
    private struct Micronutrient: Identifiable {
        let name: String
        let perHundredGrams: Double
        var id: String { name }
    }

    private var micronutrients: [Micronutrient] {
        let all: [(String, Double?)] = [
            ("Sodio", food.sodiumMg),
            ("Potasio", food.potassiumMg),
            ("Calcio", food.calciumMg),
            ("Hierro", food.ironMg),
            ("Vitamina C", food.vitaminCMg),
            ("Colesterol", food.cholesterolMg),
        ]
        return all.compactMap { entry in
            entry.1.map { Micronutrient(name: entry.0, perHundredGrams: $0) }
        }
    }

    private var mealOptions: [MealSlot] {
        let base = MealSlot.slots(for: mealsPerDay)
        return base.contains(meal) ? base : MealSlot.allCases
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text(food.name)
                        .font(.title2.bold())
                    if let brand = food.brand, !brand.isEmpty {
                        Text(brand).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Text("\(Int(macros.kcal.rounded()))")
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    HStack(spacing: DS.Spacing.l) {
                        MacroPill(title: "Proteína", grams: macros.protein, color: .protein)
                        MacroPill(title: "Carbos", grams: macros.carbs, color: .carbs)
                        MacroPill(title: "Grasa", grams: macros.fat, color: .fat)
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
            }

            Section("Cantidad") {
                if food.servingGrams != nil {
                    Picker("Unidad", selection: $unit) {
                        Text(food.servingLabel ?? "Ración").tag(Unit.serving)
                        Text("Gramos").tag(Unit.grams)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unit) { _, newUnit in
                        amount = newUnit == .grams ? 100 : 1
                    }
                }
                Stepper(value: $amount, in: 0...5000, step: unit == .grams ? 10 : 0.5) {
                    HStack {
                        TextField("Cantidad", value: $amount, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                            .frame(maxWidth: 100)
                        Text(unit == .grams ? "g" : "× \(food.servingLabel ?? "ración")")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Picker("Comida", selection: $meal) {
                    ForEach(mealOptions) { Text($0.title).tag($0) }
                }
            }

            Section {
                NutrientRow(name: "Calorías", value: macros.kcal, unit: "kcal")
                NutrientRow(name: "Proteína", value: macros.protein, unit: "g")
                NutrientRow(name: "Carbohidratos", value: macros.carbs, unit: "g")
                if let sugar = food.sugar {
                    NutrientRow(name: "de los cuales azúcares", value: sugar * grams / 100, unit: "g", indented: true)
                }
                if let fiber = food.fiber {
                    NutrientRow(name: "Fibra", value: fiber * grams / 100, unit: "g")
                }
                NutrientRow(name: "Grasa", value: macros.fat, unit: "g")
                if let saturated = food.saturatedFat {
                    NutrientRow(name: "de la cual saturada", value: saturated * grams / 100, unit: "g", indented: true)
                }
            } header: {
                Text("Nutrientes en \(Int(grams.rounded())) g")
            } footer: {
                if food.source == .seed {
                    Text("Valores medios aproximados de referencia (USDA FoodData Central).")
                }
            }

            if !micronutrients.isEmpty {
                Section("Vitaminas y minerales") {
                    ForEach(micronutrients) { item in
                        NutrientRow(name: item.name, value: item.perHundredGrams * grams / 100, unit: "mg")
                    }
                }
            }

            if food.source == .bedca {
                Section {
                    Link(destination: BedcaImporter.websiteURL) {
                        Label("Fuente: \(BedcaImporter.attribution)", systemImage: "building.columns")
                            .font(.footnote)
                    }
                } footer: {
                    Text("Valores por 100 g de porción comestible. Energía convertida a kcal cuando BEDCA la da en kJ.")
                }
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    food.isFavorite.toggle()
                } label: {
                    Image(systemName: food.isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(food.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos")
                .sensoryFeedback(.selection, trigger: food.isFavorite)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                add()
            } label: {
                Text("Añadir a \(meal.title.lowercased()) · \(Int(macros.kcal.rounded())) kcal")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(grams <= 0)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.s)
            .background(.bar)
        }
        .sensoryFeedback(.success, trigger: added)
    }

    private func add() {
        context.insert(FoodLog(day: day, meal: meal, food: food, grams: grams, portionText: portionText))
        food.lastUsedAt = .now
        try? context.save()
        added = true
        onAdded()
    }
}

private struct MacroPill: View {
    let title: String
    let grams: Double
    let color: Color

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle().fill(color).frame(width: DS.Spacing.s, height: DS.Spacing.s)
            Text("\(title) \(grams.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(.caption.monospacedDigit())
        }
    }
}

struct NutrientRow: View {
    let name: String
    let value: Double
    let unit: String
    var indented = false

    var body: some View {
        LabeledContent {
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                .monospacedDigit()
        } label: {
            Text(name)
                .padding(.leading, indented ? DS.Spacing.l : 0)
                .foregroundStyle(indented ? Color.secondary : Color.primary)
        }
    }
}
