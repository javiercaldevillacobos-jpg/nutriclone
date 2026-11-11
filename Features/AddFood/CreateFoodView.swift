import SwiftUI
import SwiftData

/// Datos de un alimento antes de guardarlo: vacío, con un nombre, o rellenado desde Open Food Facts.
struct FoodDraft {
    var name = ""
    var brand = ""
    var barcode: String?
    var source: FoodSource = .user
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?
    var saturatedFat: Double?
    var sodiumMg: Double?
    var servingLabel = ""
    var servingGrams: Double?
}

extension FoodDraft {
    init(product: OFFProduct) {
        self.init(
            name: product.name ?? "",
            brand: product.brand ?? "",
            barcode: product.barcode,
            source: .openFoodFacts,
            kcal: product.kcal.map { ($0 * 10).rounded() / 10 },
            protein: product.protein,
            carbs: product.carbs,
            fat: product.fat,
            fiber: product.fiber,
            sugar: product.sugar,
            saturatedFat: product.saturatedFat,
            sodiumMg: product.sodiumMg,
            servingLabel: product.servingLabel ?? "",
            servingGrams: product.servingGrams
        )
    }
}

/// S13: crear un alimento a partir de la etiqueta nutricional. También sirve para revisar
/// un producto escaneado antes de guardarlo.
struct CreateFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: FoodDraft
    private let notice: String?
    private let onSaved: ((Food) -> Void)?

    init(initialName: String = "") {
        _draft = State(initialValue: FoodDraft(name: initialName))
        notice = nil
        onSaved = nil
    }

    init(draft: FoodDraft, notice: String? = nil, onSaved: ((Food) -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.notice = notice
        self.onSaved = onSaved
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && (draft.kcal ?? -1) >= 0
            && [draft.protein, draft.carbs, draft.fat].allSatisfy { ($0 ?? 0) >= 0 }
    }

    /// Aviso si los macros no cuadran con las calorías (más de un 20 % de diferencia).
    private var mismatchWarning: String? {
        guard let kcal = draft.kcal, kcal > 0 else { return nil }
        let fromMacros = (draft.protein ?? 0) * 4 + (draft.carbs ?? 0) * 4 + (draft.fat ?? 0) * 9
        guard fromMacros > 0, abs(fromMacros - kcal) / kcal > 0.2 else { return nil }
        return "Con esos macros saldrían unas \(Int(fromMacros.rounded())) kcal. Revisa la etiqueta."
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: draft.source == .openFoodFacts ? "checkmark.circle" : "info.circle")
                            .font(.subheadline)
                    }
                }
                Section {
                    TextField("Nombre", text: $draft.name)
                    TextField("Marca (opcional)", text: $draft.brand)
                    if let barcode = draft.barcode {
                        LabeledContent("Código", value: barcode)
                            .monospacedDigit()
                    }
                }
                Section {
                    numberField("Calorías", value: $draft.kcal, unit: "kcal")
                    numberField("Proteína", value: $draft.protein, unit: "g")
                    numberField("Carbohidratos", value: $draft.carbs, unit: "g")
                    numberField("de los cuales azúcares", value: $draft.sugar, unit: "g")
                    numberField("Grasa", value: $draft.fat, unit: "g")
                    numberField("de la cual saturada", value: $draft.saturatedFat, unit: "g")
                    numberField("Fibra", value: $draft.fiber, unit: "g")
                } header: {
                    Text("Por 100 g o 100 ml")
                } footer: {
                    if let mismatchWarning {
                        Text(mismatchWarning).foregroundStyle(Color.over)
                    }
                }
                Section {
                    TextField("Nombre de la ración, p. ej. 1 tarrina", text: $draft.servingLabel)
                    numberField("Peso de la ración", value: $draft.servingGrams, unit: "g")
                } header: {
                    Text("Ración (opcional)")
                } footer: {
                    if draft.source == .openFoodFacts {
                        Text("Datos de Open Food Facts, base de datos colaborativa (licencia ODbL). Compruébalos con la etiqueta.")
                    }
                }
            }
            .navigationTitle(draft.barcode == nil ? "Nuevo alimento" : "Revisa el producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: DS.Spacing.xs) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let label = draft.servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasServing = !label.isEmpty && (draft.servingGrams ?? 0) > 0
        let brand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = Food(
            name: trimmedName,
            brand: brand.isEmpty ? nil : brand,
            barcode: draft.barcode,
            source: draft.source,
            kcal: draft.kcal ?? 0,
            protein: draft.protein ?? 0,
            carbs: draft.carbs ?? 0,
            fat: draft.fat ?? 0,
            fiber: draft.fiber,
            sugar: draft.sugar,
            servingLabel: hasServing ? label : nil,
            servingGrams: hasServing ? draft.servingGrams : nil
        )
        food.saturatedFat = draft.saturatedFat
        food.sodiumMg = draft.sodiumMg
        food.lastUsedAt = .now
        context.insert(food)
        try? context.save()
        onSaved?(food)
        dismiss()
    }
}
