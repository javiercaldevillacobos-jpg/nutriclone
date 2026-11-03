import SwiftUI

/// Anillo de progreso. `progress` puede pasar de 1: el exceso se pinta con el color de aviso.
struct ProgressRing<Center: View>: View {
    let progress: Double
    var color: Color = .brand
    var lineWidth: CGFloat = DS.Size.ringStroke
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress > 1 ? Color.over : color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            center()
        }
    }
}

/// Barra horizontal de un macronutriente: consumido sobre meta.
struct MacroBar: View {
    let title: String
    let value: Double
    let goal: Double
    let color: Color

    private var fraction: Double { goal > 0 ? value / goal : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ringTrack)
                    Capsule()
                        .fill(fraction > 1.05 ? Color.over : color)
                        .frame(width: geo.size.width * min(fraction, 1))
                        .animation(.smooth, value: fraction)
                }
            }
            .frame(height: DS.Size.barHeight)
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                .font(.caption.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value.rounded())) de \(Int(goal.rounded())) gramos")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: DS.Size.minTap + 8)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(isEnabled ? Color.brand : Color.secondary.opacity(0.4))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Opción seleccionable de una lista (cuestionario, ajustes).
protocol ChoiceOption: Hashable, Identifiable, CaseIterable {
    var title: String { get }
    var detail: String? { get }
    var symbol: String { get }
}

struct ChoiceList<Option: ChoiceOption>: View {
    @Binding var selection: Option

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(Array(Option.allCases)) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: DS.Spacing.m) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                            .frame(width: 32)
                            .foregroundStyle(Color.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.headline)
                            if let detail = option.detail {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.brand : Color.secondary)
                    }
                    .padding(DS.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .fill(isSelected ? Color.brandSoft : Color.card)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Fila "valor + etiqueta" usada en resúmenes.
struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
