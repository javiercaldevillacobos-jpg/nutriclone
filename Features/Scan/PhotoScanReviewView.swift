import SwiftUI
import SwiftData

/// Revisión de lo que detectó el escáner antes de guardarlo: gramos editables, cambiar el
/// alimento si la coincidencia no es buena, quitar filas y elegir la comida.
struct PhotoScanReviewView: View {
    let image: UIImage
    let day: Date
    let mealsPerDay: Int
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var items: [ScanItem]
    @State private var meal: MealSlot
    @State private var replacingIndex: Int?

    init(image: UIImage, initialItems: [ScanItem], meal: MealSlot, day: Date, mealsPerDay: Int,
         onAdded: @escaping () -> Void) {
        self.image = image
        self.day = day
        self.mealsPerDay = mealsPerDay
        self.onAdded = onAdded
        _items = State(initialValue: initialItems)
        _meal = State(initialValue: meal)
    }

    private var total: Macros { items.reduce(Macros()) { $0 + $1.macros } }
    private var addable: [ScanItem] { items.filter { $0.include && $0.food != nil && $0.grams > 0 } }
    private var pendingReview: Int { items.filter { $0.include && $0.food == nil }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .accessibilityLabel("Foto del plato")
                    Picker("Añadir a", selection: $meal) {
                        ForEach(MealSlot.slots(for: mealsPerDay)) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ForEach($items) { $item in
                        ScanItemRow(item: $item) {
                            replacingIndex = items.firstIndex { $0.id == item.id }
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                } header: {
                    Text("Alimentos detectados")
                } footer: {
                    Text("Son estimaciones de la IA. Ajusta los gramos y toca un alimento para cambiarlo por otro de la base.")
                }
            }
            .navigationTitle("Revisar plato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DS.Spacing.s) {
                    HStack {
                        Text("Total")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(total.kcal.rounded())) kcal")
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    HStack {
                        Text("P \(Int(total.protein.rounded())) g").foregroundStyle(Color.protein)
                        Spacer()
                        Text("C \(Int(total.carbs.rounded())) g").foregroundStyle(Color.carbs)
                        Spacer()
                        Text("G \(Int(total.fat.rounded())) g").foregroundStyle(Color.fat)
                    }
                    .font(.subheadline.monospacedDigit())
                    if pendingReview > 0 {
                        Label("\(pendingReview) sin alimento asignado: no se añadirán", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.over)
                    }
                    Button("Añadir al diario", action: addToDiary)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(addable.isEmpty)
                }
                .padding(DS.Spacing.l)
                .background(.bar)
            }
            .sheet(isPresented: Binding(
                get: { replacingIndex != nil },
                set: { if !$0 { replacingIndex = nil } }
            )) {
                if let index = replacingIndex, items.indices.contains(index) {
                    FoodPickerView(initialQuery: items[index].detectedName) { food in
                        items[index].food = food
                        items[index].needsReview = false
                        items[index].include = true
                        replacingIndex = nil
                    }
                }
            }
        }
    }

    private func addToDiary() {
        for item in addable {
            guard let food = item.food else { continue }
            let portion = "\(Int(item.grams.rounded())) g · foto"
            context.insert(FoodLog(day: day, meal: meal, food: food, grams: item.grams,
                                   portionText: portion, method: .photo))
            food.lastUsedAt = .now
        }
        try? context.save()
        dismiss()
        onAdded()
    }
}

private struct ScanItemRow: View {
    @Binding var item: ScanItem
    let onChangeFood: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .top) {
                Button(action: onChangeFood) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.food?.name ?? item.detectedName)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                        if item.food == nil {
                            Label("Sin coincidencia: toca para buscarlo", systemImage: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(Color.over)
                        } else if item.needsReview {
                            Label("Detectado como «\(item.detectedName)». Revisa que sea correcto", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(Color.carbs)
                        } else {
                            Text("Detectado: \(item.detectedName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Toggle("Incluir", isOn: $item.include)
                    .labelsHidden()
            }
            HStack {
                TextField("Gramos", value: $item.grams, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())
                    .frame(maxWidth: 70)
                Text("g").foregroundStyle(.secondary)
                Stepper("Gramos", value: $item.grams, in: 0...3000, step: 10)
                    .labelsHidden()
                Spacer()
                Text("\(Int(item.macros.kcal.rounded())) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(item.include ? 1 : 0.5)
        .padding(.vertical, DS.Spacing.xs)
    }
}

/// Buscador para elegir el alimento correcto de una fila del escáner.
struct FoodPickerView: View {
    let onPick: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var query: String

    init(initialQuery: String, onPick: @escaping (Food) -> Void) {
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    private var results: [Food] {
        let ranked = FoodSearch.rank(foods, query: query)
        if !ranked.isEmpty { return ranked }
        // Si ninguna palabra encaja del todo, prueba con la primera.
        let first = ScanMatcher.tokens(of: query).first ?? ""
        return FoodSearch.rank(foods, query: first)
    }

    var body: some View {
        NavigationStack {
            List(results) { food in
                Button {
                    onPick(food)
                } label: {
                    FoodRow(food: food)
                        .foregroundStyle(Color.primary)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Busca un alimento")
            .navigationTitle("Elegir alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}
