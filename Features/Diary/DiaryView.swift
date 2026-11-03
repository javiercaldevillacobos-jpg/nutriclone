import SwiftUI
import SwiftData

/// S06: diario del día.
struct DiaryView: View {
    let profile: UserProfile
    @State private var day = Date.now.startOfDay
    @State private var addingTo: MealSlot?

    var body: some View {
        NavigationStack {
            DiaryDayList(profile: profile, day: day) { addingTo = $0 }
                .safeAreaInset(edge: .top, spacing: 0) {
                    WeekStrip(selection: $day)
                        .background(.bar)
                }
                .navigationTitle(day.relativeDayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !Calendar.current.isDateInToday(day) {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Hoy") { withAnimation { day = Date.now.startOfDay } }
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            addingTo = MealSlot.suggested(mealsPerDay: profile.mealsPerDay)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Añadir alimento")
                    }
                }
                .sheet(item: $addingTo) { meal in
                    AddFoodView(meal: meal, day: day, mealsPerDay: profile.mealsPerDay)
                }
        }
    }
}

/// Contenido de un día concreto. Separado para poder filtrar las consultas por fecha.
private struct DiaryDayList: View {
    let profile: UserProfile
    let day: Date
    let onAdd: (MealSlot) -> Void

    @Environment(\.modelContext) private var context
    @Query private var logs: [FoodLog]
    @Query private var water: [WaterLog]

    init(profile: UserProfile, day: Date, onAdd: @escaping (MealSlot) -> Void) {
        self.profile = profile
        self.day = day
        self.onAdd = onAdd
        let start = day.startOfDay
        _logs = Query(filter: #Predicate<FoodLog> { $0.day == start }, sort: \FoodLog.loggedAt)
        _water = Query(filter: #Predicate<WaterLog> { $0.day == start }, sort: \WaterLog.loggedAt)
    }

    /// Las comidas configuradas más cualquier otra que tenga registros ese día.
    private var meals: [MealSlot] {
        let used = Set(logs.map(\.meal))
        let base = Set(MealSlot.slots(for: profile.mealsPerDay))
        return MealSlot.allCases.filter { base.contains($0) || used.contains($0) }
    }

    var body: some View {
        List {
            Section {
                DaySummaryCard(eaten: logs.totals, goal: profile.goalMacros)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(meals) { meal in
                MealSection(meal: meal, logs: logs.filter { $0.meal == meal }) {
                    onAdd(meal)
                } onDelete: { log in
                    context.delete(log)
                }
            }

            Section {
                WaterRow(day: day, logs: water, goalMl: profile.waterMl)
            } header: {
                Label("Agua", systemImage: "drop.fill")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(DS.Spacing.l)
    }
}

private struct DaySummaryCard: View {
    let eaten: Macros
    let goal: Macros

    private var remaining: Double { goal.kcal - eaten.kcal }

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.xl) {
                StatTile(value: "\(Int(eaten.kcal.rounded()))", label: "Comidas")
                ProgressRing(progress: goal.kcal > 0 ? eaten.kcal / goal.kcal : 0) {
                    VStack(spacing: 0) {
                        Text("\(Int(abs(remaining).rounded()))")
                            .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(remaining >= 0 ? "restantes" : "de más")
                            .font(.caption)
                            .foregroundStyle(remaining >= 0 ? Color.secondary : Color.over)
                    }
                }
                .frame(width: DS.Size.ringMedium, height: DS.Size.ringMedium)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calorías")
                .accessibilityValue(remaining >= 0
                    ? "Te quedan \(Int(remaining.rounded())) kilocalorías"
                    : "Te has pasado \(Int(-remaining.rounded())) kilocalorías")
                StatTile(value: "\(Int(goal.kcal.rounded()))", label: "Meta")
            }
            HStack(spacing: DS.Spacing.l) {
                MacroBar(title: "Proteína", value: eaten.protein, goal: goal.protein, color: .protein)
                MacroBar(title: "Carbos", value: eaten.carbs, goal: goal.carbs, color: .carbs)
                MacroBar(title: "Grasa", value: eaten.fat, goal: goal.fat, color: .fat)
            }
        }
        .padding(DS.Spacing.l)
        .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(Color.card))
    }
}

private struct MealSection: View {
    let meal: MealSlot
    let logs: [FoodLog]
    let onAdd: () -> Void
    let onDelete: (FoodLog) -> Void

    var body: some View {
        Section {
            ForEach(logs) { log in
                FoodLogRow(log: log)
            }
            .onDelete { offsets in
                offsets.map { logs[$0] }.forEach(onDelete)
            }
            Button(action: onAdd) {
                Label(logs.isEmpty ? "Añadir a \(meal.title.lowercased())" : "Añadir más",
                      systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Label(meal.title, systemImage: meal.symbol)
                Spacer()
                if !logs.isEmpty {
                    Text("\(Int(logs.totals.kcal.rounded())) kcal")
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct FoodLogRow: View {
    let log: FoodLog

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.name)
                    .lineLimit(2)
                Text(log.portionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(log.kcal.rounded())) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WaterRow: View {
    static let glassMl = 250

    let day: Date
    let logs: [WaterLog]
    let goalMl: Int

    @Environment(\.modelContext) private var context

    private var totalMl: Int { logs.reduce(0) { $0 + $1.ml } }
    private var goalGlasses: Int { max(goalMl / Self.glassMl, 1) }
    private var glasses: Int { totalMl / Self.glassMl }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack {
                Text("\((Double(totalMl) / 1000).formatted()) de \((Double(goalMl) / 1000).formatted()) L")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    if let last = logs.last { context.delete(last) }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title2)
                }
                .disabled(logs.isEmpty)
                .accessibilityLabel("Quitar un vaso")
                Button {
                    context.insert(WaterLog(day: day, ml: Self.glassMl))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Añadir un vaso de 250 mililitros")
            }
            .buttonStyle(.borderless)
            HStack(spacing: DS.Spacing.xs) {
                ForEach(0..<min(max(goalGlasses, glasses), 16), id: \.self) { i in
                    Image(systemName: i < glasses ? "drop.fill" : "drop")
                        .foregroundStyle(Color.water)
                }
            }
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.increase, trigger: totalMl)
    }
}

/// Tira de la semana para elegir día.
struct WeekStrip: View {
    @Binding var selection: Date

    private var week: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection.startOfDay
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                selection = selection.adding(days: -7)
            } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: DS.Size.minTap)
            }
            .accessibilityLabel("Semana anterior")
            ForEach(week, id: \.self) { date in
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selection)
                let isToday = Calendar.current.isDateInToday(date)
                Button {
                    selection = date
                } label: {
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.subheadline.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Size.minTap)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .fill(isSelected ? Color.brand : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Button {
                selection = selection.adding(days: 7)
            } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: DS.Size.minTap)
            }
            .accessibilityLabel("Semana siguiente")
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
