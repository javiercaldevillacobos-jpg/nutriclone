import SwiftUI
import PhotosUI
import SwiftData

/// Flujo completo de "Escanear plato": comprobar clave → cámara o galería → Gemini → revisión.
/// Se aplica como modificador a la vista que tiene el botón (AddFoodView).
struct DishScanFlow: ViewModifier {
    @Binding var isActive: Bool
    let meal: MealSlot
    let day: Date
    let mealsPerDay: Int
    let onAdded: () -> Void

    @Query private var foods: [Food]
    @AppStorage(GeminiModel.storageKey) private var modelRaw = GeminiModel.default.rawValue

    @State private var choosingSource = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var missingKeyAlert = false
    @State private var showingSettings = false
    @State private var analyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var lastImage: UIImage?
    @State private var failure: GeminiError?
    @State private var review: ScanReview?

    struct ScanReview: Identifiable {
        let id = UUID()
        let image: UIImage
        let items: [ScanItem]
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                guard active else { return }
                isActive = false
                start()
            }
            .confirmationDialog("Escanear plato", isPresented: $choosingSource, titleVisibility: .visible) {
                if CameraPicker.isAvailable {
                    Button("Hacer foto") { showingCamera = true }
                }
                Button("Elegir de la galería") { showingLibrary = true }
            } message: {
                Text("La foto se envía a Google Gemini para reconocer los alimentos.")
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in analyze(image) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        analyze(image)
                    } else {
                        failure = .imageEncoding
                    }
                }
            }
            .alert("Falta tu clave de Gemini", isPresented: $missingKeyAlert) {
                Button("Ir a ajustes") { showingSettings = true }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("El escáner usa tu propia clave gratuita de Google AI Studio. Pégala en ajustes y vuelve a intentarlo.")
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { GeminiSettingsView(presentedAsSheet: true) }
            }
            .overlay {
                if analyzing { AnalyzingOverlay { cancelAnalysis() } }
            }
            .sheet(item: $failure) { error in
                ScanErrorView(error: error) {
                    failure = nil
                    if let lastImage { analyze(lastImage) }
                } openSettings: {
                    failure = nil
                    showingSettings = true
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $review) { review in
                PhotoScanReviewView(
                    image: review.image,
                    initialItems: review.items,
                    meal: meal,
                    day: day,
                    mealsPerDay: mealsPerDay
                ) {
                    self.review = nil
                    onAdded()
                }
            }
    }

    private func start() {
        guard KeychainService.shared.geminiAPIKey != nil else {
            missingKeyAlert = true
            return
        }
        choosingSource = true
    }

    private func analyze(_ image: UIImage) {
        guard let key = KeychainService.shared.geminiAPIKey else {
            missingKeyAlert = true
            return
        }
        let model = GeminiModel(rawValue: modelRaw) ?? .default
        lastImage = image
        analyzing = true
        analysisTask = Task {
            do {
                let detected = try await GeminiService.shared.analyze(image: image, apiKey: key, model: model)
                guard !Task.isCancelled else { return }
                analyzing = false
                review = ScanReview(image: image, items: ScanMatcher.items(for: detected, in: foods))
            } catch is CancellationError {
                analyzing = false
            } catch let error as GeminiError {
                analyzing = false
                failure = error
            } catch {
                analyzing = false
                failure = .network(error.localizedDescription)
            }
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analyzing = false
    }
}

extension GeminiError: Identifiable {
    var id: String { errorDescription ?? "error" }
}

extension View {
    func dishScanFlow(isActive: Binding<Bool>, meal: MealSlot, day: Date, mealsPerDay: Int,
                      onAdded: @escaping () -> Void) -> some View {
        modifier(DishScanFlow(isActive: isActive, meal: meal, day: day, mealsPerDay: mealsPerDay, onAdded: onAdded))
    }
}

private struct AnalyzingOverlay: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: DS.Spacing.l) {
                SwiftUI.ProgressView()
                    .controlSize(.large)
                Text("Analizando tu plato…")
                    .font(.headline)
                Text("Suele tardar unos segundos. Si Google está saturado, reintentamos solos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.bordered)
            }
            .padding(DS.Spacing.xxl)
        }
        .transition(.opacity)
    }
}

private struct ScanErrorView: View {
    let error: GeminiError
    let onRetry: () -> Void
    let openSettings: () -> Void

    private var symbol: String {
        switch error {
        case .offline: "wifi.slash"
        case .rateLimited: "hourglass"
        case .missingKey, .invalidKey, .forbidden: "key.slash"
        case .timeout: "clock.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch error {
        case .offline: "Sin conexión"
        case .rateLimited: "Límite gratuito alcanzado"
        case .missingKey, .invalidKey, .forbidden: "Revisa tu clave"
        default: "No se pudo analizar"
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(error.errorDescription ?? "")
        } actions: {
            if error.isKeyProblem {
                Button("Abrir ajustes del escáner", action: openSettings)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Reintentar", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
