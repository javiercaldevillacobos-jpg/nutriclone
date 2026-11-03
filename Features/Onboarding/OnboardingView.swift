import SwiftUI
import SwiftData

/// Respuestas del cuestionario inicial mientras se rellena.
struct OnboardingDraft {
    var name = ""
    var goal: GoalType = .lose
    var sex: Sex = .female
    var birthdate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    var heightCm = 170
    var weightKg = 70.0
    var targetWeightKg = 65.0
    var paceKgWeek = 0.5
    var activity: ActivityLevel = .light
    var diet: DietType = .balanced
    var mealsPerDay = 4

    var input: NutritionInput {
        NutritionInput(
            sex: sex,
            age: NutritionCalculator.age(from: birthdate),
            heightCm: Double(heightCm),
            weightKg: weightKg,
            activity: activity,
            goal: goal,
            paceKgWeek: goal == .maintain ? 0 : paceKgWeek,
            diet: diet
        )
    }

    var targets: NutritionTargets { NutritionCalculator.targets(for: input) }

    /// Mensaje si el peso meta no tiene sentido para el objetivo; nil si es válido.
    var targetProblem: String? {
        switch goal {
        case .lose where targetWeightKg >= weightKg:
            return "Para perder grasa, el peso meta tiene que ser menor que tu peso actual."
        case .gain where targetWeightKg <= weightKg:
            return "Para ganar músculo, el peso meta tiene que ser mayor que tu peso actual."
        default:
            break
        }
        if NutritionCalculator.bmi(weightKg: targetWeightKg, heightCm: Double(heightCm)) < 18.5 {
            return "Ese peso queda por debajo de un IMC saludable (18,5) para tu altura."
        }
        return nil
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, goal, sex, birthdate, height, weight, target, pace, activity, diet, meals, name, result
    }

    @Environment(\.modelContext) private var context
    @State private var draft = OnboardingDraft()
    @State private var step: Step = .welcome
    @State private var goingBack = false

    private var visibleSteps: [Step] {
        Step.allCases.filter { step in
            draft.goal != .maintain || (step != .target && step != .pace)
        }
    }

    private var progress: Double {
        guard let i = visibleSteps.firstIndex(of: step) else { return 0 }
        return Double(i) / Double(visibleSteps.count - 1)
    }

    private var canContinue: Bool {
        step != .target || draft.targetProblem == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ScrollView {
                content
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingBack ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: goingBack ? .trailing : .leading).combined(with: .opacity)
                    ))
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(Color.screen)
    }

    // MARK: - Partes fijas

    private var header: some View {
        HStack(spacing: DS.Spacing.m) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: DS.Size.minTap, height: DS.Size.minTap)
            }
            .accessibilityLabel("Atrás")
            SwiftUI.ProgressView(value: progress)
                .tint(.brand)
                .animation(.smooth, value: progress)
        }
        .padding(.horizontal, DS.Spacing.l)
    }

    private var footer: some View {
        Button {
            if step == .result { finish() } else { move(by: 1) }
        } label: {
            Text(step == .welcome ? "Empezar" : step == .result ? "Empezar a registrar" : "Continuar")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canContinue)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.l)
    }

    private func move(by delta: Int) {
        guard let i = visibleSteps.firstIndex(of: step) else { return }
        let next = i + delta
        guard visibleSteps.indices.contains(next) else { return }
        goingBack = delta < 0
        withAnimation(.snappy) { step = visibleSteps[next] }
    }

    // MARK: - Pasos

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .goal:
            StepScaffold(title: "¿Qué quieres conseguir?") {
                ChoiceList(selection: $draft.goal)
            }
        case .sex:
            StepScaffold(title: "Sexo biológico",
                         subtitle: "Cambia la fórmula del gasto en reposo.") {
                ChoiceList(selection: $draft.sex)
            }
        case .birthdate:
            StepScaffold(title: "¿Cuándo naciste?") {
                DatePicker("Fecha de nacimiento", selection: $draft.birthdate,
                           in: Self.birthRange, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Text("\(NutritionCalculator.age(from: draft.birthdate)) años")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
            }
        case .height:
            StepScaffold(title: "¿Cuánto mides?") {
                Picker("Altura", selection: $draft.heightCm) {
                    ForEach(120...230, id: \.self) { Text("\($0) cm").tag($0) }
                }
                .pickerStyle(.wheel)
            }
        case .weight:
            StepScaffold(title: "¿Cuánto pesas ahora?") {
                WeightWheel(value: $draft.weightKg)
            }
            .onChange(of: draft.weightKg) { _, newValue in
                // Propone una meta coherente con el objetivo.
                let delta: Double = switch draft.goal {
                case .lose: -5
                case .gain: 3
                case .maintain: 0
                }
                draft.targetWeightKg = newValue + delta
            }
        case .target:
            StepScaffold(title: "¿Cuál es tu peso meta?") {
                WeightWheel(value: $draft.targetWeightKg)
                if let problem = draft.targetProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                }
            }
        case .pace:
            StepScaffold(title: draft.goal == .lose ? "¿A qué ritmo quieres perder?" : "¿A qué ritmo quieres ganar?",
                         subtitle: "Un ritmo moderado es más fácil de mantener.") {
                PaceChooser(goal: draft.goal, pace: $draft.paceKgWeek)
            }
        case .activity:
            StepScaffold(title: "¿Cómo de activo eres?") {
                ChoiceList(selection: $draft.activity)
            }
        case .diet:
            StepScaffold(title: "¿Qué tipo de alimentación prefieres?",
                         subtitle: "Puedes cambiarlo cuando quieras en Perfil.") {
                ChoiceList(selection: $draft.diet)
            }
        case .meals:
            StepScaffold(title: "¿Cuántas comidas haces al día?") {
                Picker("Comidas al día", selection: $draft.mealsPerDay) {
                    ForEach(3...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text(MealSlot.slots(for: draft.mealsPerDay).map(\.title).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .name:
            StepScaffold(title: "¿Cómo te llamamos?", subtitle: "Opcional.") {
                TextField("Tu nombre", text: $draft.name)
                    .textContentType(.givenName)
                    .font(.title3)
                    .padding(DS.Spacing.l)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.m).fill(Color.card))
            }
        case .result:
            OnboardingResultStep(draft: draft)
        }
    }

    static let birthRange: ClosedRange<Date> = {
        let cal = Calendar.current
        let oldest = cal.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let youngest = cal.date(byAdding: .year, value: -14, to: .now) ?? .now
        return oldest...youngest
    }()

    private func finish() {
        let targets = draft.targets
        let profile = UserProfile(
            name: draft.name.trimmingCharacters(in: .whitespaces),
            sex: draft.sex,
            birthdate: draft.birthdate,
            heightCm: Double(draft.heightCm),
            startWeightKg: draft.weightKg,
            goal: draft.goal,
            activity: draft.activity,
            diet: draft.diet,
            targetWeightKg: draft.goal == .maintain ? draft.weightKg : draft.targetWeightKg,
            paceKgWeek: draft.goal == .maintain ? 0 : draft.paceKgWeek,
            mealsPerDay: draft.mealsPerDay,
            targets: targets
        )
        context.insert(profile)
        context.insert(BodyEntry(day: .now, weightKg: draft.weightKg))
        try? context.save()
    }
}

// MARK: - Piezas del cuestionario

private struct StepScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            Spacer(minLength: DS.Spacing.xxl)
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.brand)
            Text("Come bien sin contar a ojo")
                .font(.largeTitle.bold())
            Text("Responde unas preguntas y calculamos cuántas calorías y macros necesitas cada día para tu objetivo.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Label("Metas diarias hechas para ti", systemImage: "target")
                Label("Registra comidas en segundos", systemImage: "bolt")
                Label("Mira tu progreso semana a semana", systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.headline)
        }
    }
}

/// Selector de peso en pasos de 0,5 kg.
struct WeightWheel: View {
    @Binding var value: Double

    private static let options: [Double] = Array(stride(from: 30.0, through: 250.0, by: 0.5))

    var body: some View {
        Picker("Peso", selection: $value) {
            ForEach(Self.options, id: \.self) { kg in
                Text(kg.formatted(.number.precision(.fractionLength(1))) + " kg").tag(kg)
            }
        }
        .pickerStyle(.wheel)
        .onAppear {
            // Asegura que el valor coincide con una opción de la rueda.
            value = (value * 2).rounded() / 2
        }
    }
}

private struct PaceChooser: View {
    let goal: GoalType
    @Binding var pace: Double

    private var options: [(Double, String)] {
        goal == .gain
            ? [(0.25, "Tranquilo"), (0.5, "Normal")]
            : [(0.25, "Suave"), (0.5, "Recomendado"), (0.75, "Rápido"), (1.0, "Muy rápido")]
    }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.0 == pace
                Button {
                    pace = option.0
                } label: {
                    HStack {
                        Text(option.1).font(.headline)
                        Spacer()
                        Text("\(option.0.formatted()) kg/semana")
                            .foregroundStyle(.secondary)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.brand : Color.secondary)
                    }
                    .padding(DS.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .fill(selected ? Color.brandSoft : Color.card)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            if !options.contains(where: { $0.0 == pace }) { pace = options[0].0 }
        }
    }
}
