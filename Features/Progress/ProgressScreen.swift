import SwiftUI
import SwiftData
import Charts

/// S18: progreso de peso e historial de calorías.
struct ProgressScreen: View {
    enum Period: String, CaseIterable, Identifiable {
        case month = "1 M", quarter = "3 M", year = "1 A", all = "Todo"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 90
            case .year: 365
            case .all: nil
            }
        }
    }

    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \BodyEntry.day) private var entries: [BodyEntry]
    @Query private var recentLogs: [FoodLog]
    @State private var range: Period = .quarter
    @State private var addingWeight = false

    static let historyDays = 14

    init(profile: UserProfile) {
        self.profile = profile
        let cutoff = Date.now.startOfDay.adding(days: -(Self.historyDays - 1))
        _recentLogs = Query(filter: #Predicate<FoodLog> { $0.day >= cutoff })
    }

    private var visibleEntries: [BodyEntry] {
        guard let days = range.days else { return entries }
        let cutoff = Date.now.startOfDay.adding(days: -days)
        return entries.filter { $0.day >= cutoff }
    }

    private var current: Double { entries.last?.weightKg ?? profile.startWeightKg }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        StatTile(value: kg(profile.startWeightKg), label: "Inicio")
                        StatTile(value: kg(current), label: "Actual")
                        StatTile(value: kg(profile.targetWeightKg), label: "Meta")
                        StatTile(value: signedKg(current - profile.startWeightKg), label: "Cambio")
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }

                Section {
                    Picker("Periodo", selection: $range) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    WeightChart(entries: visibleEntries, target: profile.goal == .maintain ? nil : profile.targetWeightKg)
                        .frame(height: DS.Size.chartHeight)
                        .padding(.vertical, DS.Spacing.s)
                } header: {
                    Text("Peso")
                } footer: {
                    if entries.count < 2 {
                        Text("Registra tu peso cada semana, a la misma hora, para ver la tendencia.")
                    }
                }

                Section {
                    CaloriesChart(logs: recentLogs, goalKcal: profile.kcal, days: Self.historyDays)
                        .frame(height: DS.Size.chartHeight * 0.8)
                        .padding(.vertical, DS.Spacing.s)
                } header: {
                    Text("Calorías · últimos \(Self.historyDays) días")
                }

                Section("Registros") {
                    ForEach(Array(entries.reversed())) { entry in
                        LabeledContent {
                            Text(kg(entry.weightKg)).monospacedDigit()
                        } label: {
                            Text(entry.day.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .onDelete { offsets in
                        let reversed = Array(entries.reversed())
                        offsets.map { reversed[$0] }.forEach { context.delete($0) }
                    }
                }
            }
            .navigationTitle("Progreso")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addingWeight = true
                    } label: {
                        Label("Registrar peso", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $addingWeight) {
                AddWeightSheet(initialWeight: current)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func kg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " kg"
    }

    private func signedKg(_ value: Double) -> String {
        (value > 0 ? "+" : "") + kg(value)
    }
}

private struct WeightChart: View {
    let entries: [BodyEntry]
    let target: Double?

    private var domain: ClosedRange<Double> {
        var values = entries.map(\.weightKg)
        if let target { values.append(target) }
        let lo = (values.min() ?? 60) - 2
        let hi = (values.max() ?? 80) + 2
        return lo...hi
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("Sin registros en este periodo", systemImage: "scalemass")
        } else {
            Chart {
                ForEach(entries) { entry in
                    LineMark(x: .value("Fecha", entry.day, unit: .day),
                             y: .value("Peso", entry.weightKg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.brand)
                    PointMark(x: .value("Fecha", entry.day, unit: .day),
                              y: .value("Peso", entry.weightKg))
                        .foregroundStyle(Color.brand)
                }
                if let target {
                    RuleMark(y: .value("Meta", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Meta").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: domain)
            .accessibilityLabel("Gráfico de peso")
        }
    }
}

private struct CaloriesChart: View {
    struct DayTotal: Identifiable {
        let day: Date
        let kcal: Double
        var id: Date { day }
    }

    let logs: [FoodLog]
    let goalKcal: Int
    let days: Int

    private var totals: [DayTotal] {
        let byDay = Dictionary(grouping: logs, by: \.day)
        let today = Date.now.startOfDay
        return (0..<days).reversed().map { offset in
            let day = today.adding(days: -offset)
            return DayTotal(day: day, kcal: byDay[day]?.totals.kcal ?? 0)
        }
    }

    var body: some View {
        Chart {
            ForEach(totals) { total in
                BarMark(x: .value("Día", total.day, unit: .day),
                        y: .value("kcal", total.kcal))
                    .foregroundStyle(total.kcal > Double(goalKcal) * 1.05 ? Color.over : Color.brand)
                    .cornerRadius(DS.Radius.s / 2)
            }
            RuleMark(y: .value("Meta", goalKcal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.secondary)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .accessibilityLabel("Calorías por día frente a tu meta")
    }
}

/// S19: registrar el peso de un día.
struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var weight: Double
    @State private var day = Date.now

    init(initialWeight: Double) {
        _weight = State(initialValue: (initialWeight * 2).rounded() / 2)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $day, in: ...Date.now, displayedComponents: .date)
                WeightWheel(value: $weight)
            }
            .navigationTitle("Registrar peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                }
            }
        }
    }

    /// Un registro por día: si ya hay uno ese día, se sustituye.
    private func save() {
        let start = day.startOfDay
        let existing = (try? context.fetch(FetchDescriptor<BodyEntry>(
            predicate: #Predicate<BodyEntry> { $0.day == start }
        ))) ?? []
        if let entry = existing.first {
            entry.weightKg = weight
        } else {
            context.insert(BodyEntry(day: start, weightKg: weight))
        }
        try? context.save()
        dismiss()
    }
}
