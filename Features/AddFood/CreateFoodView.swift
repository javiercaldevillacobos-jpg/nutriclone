import SwiftUI
import SwiftData

/// S13: crear un alimento propio a partir de la etiqueta nutricional.
struct CreateFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var brand = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var servingLabel = ""
    @State private var servingGrams: Double?

    init(initialName: String = "") {
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedName.isEmpty && (kcal ?? -1) >= 0
            && [protein, carbs, fat].allSatisfy { ($0 ?? 0) >= 0 }
    }

    /// Aviso si los macros no cuadran con las calorías (más de un 20 % de diferencia).
    private var mismatchWarning: String? {
        guard let kcal, kcal > 0 else { return nil }
        let fromMacros = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
        guard fromMacros > 0, abs(fromMacros - kcal) / kcal > 0.2 else { return nil }
        return "Con esos macros saldrían unas \(Int(fromMacros.rounded())) kcal. Revisa la etiqueta."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $name)
                    TextField("Marca (opcional)", text: $brand)
                }
                Section {
                    numberField("Calorías", value: $kcal, unit: "kcal")
                    numberField("Proteína", value: $protein, unit: "g")
                    numberField("Carbohidratos", value: $carbs, unit: "g")
                    numberField("Grasa", value: $fat, unit: "g")
                } header: {
                    Text("Por 100 g o 100 ml")
                } footer: {
                    if let mismatchWarning {
                        Text(mismatchWarning).foregroundStyle(Color.over)
                    }
                }
                Section {
                    TextField("Nombre de la ración, p. ej. 1 tarrina", text: $servingLabel)
                    numberField("Peso de la ración", value: $servingGrams, unit: "g")
                } header: {
                    Text("Ración (opcional)")
                }
            }
            .navigationTitle("Nuevo alimento")
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
        let label = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasServing = !label.isEmpty && (servingGrams ?? 0) > 0
        let food = Food(
            name: trimmedName,
            brand: brand.isEmpty ? nil : brand,
            source: .user,
            kcal: kcal ?? 0,
            protein: protein ?? 0,
            carbs: carbs ?? 0,
            fat: fat ?? 0,
            servingLabel: hasServing ? label : nil,
            servingGrams: hasServing ? servingGrams : nil
        )
        food.lastUsedAt = .now
        context.insert(food)
        try? context.save()
        dismiss()
    }
}
