import SwiftUI
import SwiftData

/// S24: perfil, metas y ajustes.
struct ProfileView: View {
    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \BodyEntry.day, order: .reverse) private var entries: [BodyEntry]
    @State private var confirmingReset = false

    private var currentWeight: Double { entries.first?.weightKg ?? profile.startWeightKg }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tu nombre", text: $profile.name)
                    LabeledContent("Plan", value: "Premium · todo incluido")
                }

                Section {
                    LabeledContent("Calorías", value: "\(profile.kcal) kcal")
                    LabeledContent("Proteína", value: "\(profile.proteinG) g")
                    LabeledContent("Carbohidratos", value: "\(profile.carbsG) g")
                    LabeledContent("Grasa", value: "\(profile.fatG) g")
                    LabeledContent("Agua", value: "\((Double(profile.waterMl) / 1000).formatted()) L")
                    NavigationLink("Cambiar objetivo y metas") {
                        GoalEditorView(profile: profile, currentWeight: currentWeight)
                    }
                } header: {
                    Text("Metas diarias")
                } footer: {
                    Text("Objetivo: \(profile.goal.title.lowercased()) · \(profile.diet.title.lowercased()) · \(profile.activity.title.lowercased()).")
                }

                Section("Diario") {
                    Picker("Comidas al día", selection: $profile.mealsPerDay) {
                        ForEach(3...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                }

                Section {
                    NavigationLink {
                        GeminiSettingsView()
                    } label: {
                        Label("Escáner de platos", systemImage: "camera.viewfinder")
                    }
                } footer: {
                    Text("Registra un plato con una foto usando tu clave gratuita de Gemini.")
                }

                Section("Tus datos") {
                    LabeledContent("Sexo", value: profile.sex.title)
                    LabeledContent("Edad", value: "\(profile.age) años")
                    LabeledContent("Altura", value: "\(Int(profile.heightCm)) cm")
                    LabeledContent("Peso actual", value: currentWeight.formatted(.number.precision(.fractionLength(1))) + " kg")
                }

                Section {
                    Link(destination: BedcaImporter.websiteURL) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("BEDCA · AESAN")
                                .font(.headline)
                            Text("Datos de composición de alimentos: AESAN/BEDCA (Base de Datos Española de Composición de Alimentos). Uso personal, educativo y no comercial.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(BedcaImporter.attribution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: OpenFoodFactsService.websiteURL) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("Open Food Facts")
                                .font(.headline)
                            Text("Productos envasados por código de barras. Base de datos abierta y colaborativa, licencia ODbL.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("USDA FoodData Central")
                            .font(.headline)
                        Text("Valores de referencia de los alimentos genéricos que no están en BEDCA (dominio público).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Fuentes de datos")
                } footer: {
                    Text("AESAN y BEDCA no se responsabilizan del uso de estos datos.")
                }

                Section {
                    Button("Borrar todos mis datos", role: .destructive) {
                        confirmingReset = true
                    }
                } footer: {
                    Text("NutriClone ofrece estimaciones generales y no sustituye el consejo de un profesional sanitario.")
                }
            }
            .navigationTitle("Perfil")
            .confirmationDialog("¿Borrar todos tus datos?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Borrar y empezar de cero", role: .destructive, action: resetAll)
            } message: {
                Text("Se eliminarán tu perfil, tus registros de comidas, agua y peso, y tus alimentos propios. No se puede deshacer.")
            }
        }
    }

    private func resetAll() {
        deleteAll(FoodLog.self)
        deleteAll(WaterLog.self)
        deleteAll(BodyEntry.self)
        // Se borran también los alimentos; el cuestionario vuelve a cargar la base incluida.
        deleteAll(Food.self)
        deleteAll(UserProfile.self)
        try? context.save()
    }

    /// Borra objeto a objeto (no en lote) para que las vistas con @Query se enteren.
    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
            context.delete(item)
        }
    }
}

/// S25: cambiar objetivo, actividad, dieta y ritmo, y recalcular metas.
struct GoalEditorView: View {
    let profile: UserProfile
    let currentWeight: Double

    @Environment(\.dismiss) private var dismiss
    @State private var goal: GoalType
    @State private var activity: ActivityLevel
    @State private var diet: DietType
    @State private var pace: Double
    @State private var targetWeight: Double

    init(profile: UserProfile, currentWeight: Double) {
        self.profile = profile
        self.currentWeight = currentWeight
        _goal = State(initialValue: profile.goal)
        _activity = State(initialValue: profile.activity)
        _diet = State(initialValue: profile.diet)
        _pace = State(initialValue: profile.paceKgWeek > 0 ? profile.paceKgWeek : 0.5)
        _targetWeight = State(initialValue: (profile.targetWeightKg * 2).rounded() / 2)
    }

    private var input: NutritionInput {
        NutritionInput(
            sex: profile.sex,
            age: profile.age,
            heightCm: profile.heightCm,
            weightKg: currentWeight,
            activity: activity,
            goal: goal,
            paceKgWeek: goal == .maintain ? 0 : pace,
            diet: diet
        )
    }

    private var preview: NutritionTargets { NutritionCalculator.targets(for: input) }

    private var targetIsValid: Bool {
        switch goal {
        case .lose: targetWeight < currentWeight
        case .gain: targetWeight > currentWeight
        case .maintain: true
        }
    }

    var body: some View {
        Form {
            Section("Objetivo") {
                Picker("Objetivo", selection: $goal) {
                    ForEach(GoalType.allCases) { Text($0.title).tag($0) }
                }
                if goal != .maintain {
                    Picker("Ritmo", selection: $pace) {
                        ForEach(goal == .gain ? [0.25, 0.5] : [0.25, 0.5, 0.75, 1.0], id: \.self) {
                            Text("\($0.formatted()) kg/semana").tag($0)
                        }
                    }
                    LabeledContent("Peso meta") {
                        Stepper(value: $targetWeight, in: 30...250, step: 0.5) {
                            Text(targetWeight.formatted(.number.precision(.fractionLength(1))) + " kg")
                                .monospacedDigit()
                        }
                    }
                    if !targetIsValid {
                        Text(goal == .lose ? "La meta debe ser menor que tu peso actual." : "La meta debe ser mayor que tu peso actual.")
                            .font(.footnote)
                            .foregroundStyle(Color.over)
                    }
                }
            }
            Section("Actividad") {
                Picker("Actividad", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Alimentación") {
                Picker("Tipo de dieta", selection: $diet) {
                    ForEach(DietType.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                LabeledContent("Calorías", value: "\(preview.kcal) kcal")
                LabeledContent("Proteína", value: "\(preview.proteinG) g")
                LabeledContent("Carbohidratos", value: "\(preview.carbsG) g")
                LabeledContent("Grasa", value: "\(preview.fatG) g")
            } header: {
                Text("Nuevas metas")
            } footer: {
                Text("Calculadas con tu peso actual (\(currentWeight.formatted(.number.precision(.fractionLength(1)))) kg).")
            }
        }
        .navigationTitle("Objetivo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(!targetIsValid)
            }
        }
    }

    private func save() {
        profile.goal = goal
        profile.activity = activity
        profile.diet = diet
        profile.paceKgWeek = goal == .maintain ? 0 : pace
        profile.targetWeightKg = goal == .maintain ? currentWeight : targetWeight
        profile.apply(preview)
        dismiss()
    }
}
