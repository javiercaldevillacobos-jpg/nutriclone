import SwiftUI
import SwiftData

/// S07: buscar y elegir un alimento para una comida.
struct AddFoodView: View {
    let meal: MealSlot
    let day: Date
    let mealsPerDay: Int

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var query = ""
    @State private var creating = false
    @State private var scanning = false

    private var normalizedQuery: String { Food.normalize(query) }

    private var results: [Food] { FoodSearch.rank(foods, query: query) }

    private var recents: [Food] {
        foods
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(15)
            .map { $0 }
    }

    private var favorites: [Food] { foods.filter(\.isFavorite) }
    private var mine: [Food] { foods.filter { $0.source == .user } }

    var body: some View {
        NavigationStack {
            List {
                if normalizedQuery.isEmpty {
                    browseSections
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("Sin resultados", systemImage: "magnifyingglass")
                    } description: {
                        Text("No encontramos «\(query)». Puedes crearlo con sus valores nutricionales.")
                    } actions: {
                        Button("Crear «\(query)»") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Resultados") {
                        ForEach(results) { food in
                            NavigationLink(value: food) { FoodRow(food: food) }
                        }
                    }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Busca un alimento")
            .autocorrectionDisabled()
            .navigationTitle(meal.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Food.self) { food in
                FoodDetailView(food: food, meal: meal, day: day, mealsPerDay: mealsPerDay) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label("Crear alimento", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                CreateFoodView(initialName: query)
            }
            .dishScanFlow(isActive: $scanning, meal: meal, day: day, mealsPerDay: mealsPerDay) {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var browseSections: some View {
        Section {
            Button {
                scanning = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Escanear plato").font(.headline)
                        Text("Haz una foto y la IA estima alimentos y gramos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundStyle(Color.brand)
                }
            }
            .foregroundStyle(Color.primary)
        }
        if !favorites.isEmpty {
            Section {
                ForEach(favorites) { food in
                    NavigationLink(value: food) { FoodRow(food: food) }
                }
            } header: {
                Label("Favoritos", systemImage: "heart.fill")
            }
        }
        if !recents.isEmpty {
            Section {
                ForEach(recents) { food in
                    NavigationLink(value: food) { FoodRow(food: food) }
                }
            } header: {
                Label("Recientes", systemImage: "clock")
            }
        }
        if !mine.isEmpty {
            Section {
                ForEach(mine) { food in
                    NavigationLink(value: food) { FoodRow(food: food) }
                }
            } header: {
                Label("Mis alimentos", systemImage: "person")
            }
        }
        if favorites.isEmpty && recents.isEmpty {
            Section {
                ForEach(foods.prefix(40)) { food in
                    NavigationLink(value: food) { FoodRow(food: food) }
                }
            } header: {
                Text("Algunas ideas")
            } footer: {
                Text("Escribe arriba para buscar entre todos los alimentos. Los que uses aparecerán en Recientes.")
            }
        }
    }
}

struct FoodRow: View {
    let food: Food

    private var subtitle: String {
        if let label = food.servingLabel, let grams = food.servingGrams {
            let kcal = Int((food.kcal * grams / 100).rounded())
            return "\(label) (\(Int(grams)) g) · \(kcal) kcal"
        }
        return "100 g · \(Int(food.kcal.rounded())) kcal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Spacing.xs) {
                Text(food.name)
                    .lineLimit(2)
                if food.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.brand)
                        .accessibilityLabel("Favorito")
                }
            }
            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
