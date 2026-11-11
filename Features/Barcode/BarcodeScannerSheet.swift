import SwiftUI
import VisionKit
import Vision
import AVFoundation

/// S12: lector de códigos de barras. Usa el lector de VisionKit (todo en el iPhone, sin red) y,
/// si no hay cámara (simulador) o falta permiso, deja escribir el código a mano.
struct BarcodeScannerSheet: View {
    /// Devuelve el código ya normalizado (ver `Barcode.normalize`).
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var manualEntry = false
    @State private var manualCode = ""
    @State private var torchOn = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var cameraDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable && !manualEntry {
                    ZStack(alignment: .bottom) {
                        DataScannerRepresentable(torchOn: torchOn) { code in
                            finish(with: code)
                        }
                        .ignoresSafeArea()
                        Text("Apunta al código de barras del envase")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, DS.Spacing.l)
                            .padding(.vertical, DS.Spacing.s)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, DS.Spacing.xxl)
                    }
                } else {
                    manualForm
                }
            }
            .navigationTitle("Código de barras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if scannerAvailable {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if !manualEntry {
                            Button {
                                torchOn.toggle()
                            } label: {
                                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            }
                            .accessibilityLabel(torchOn ? "Apagar linterna" : "Encender linterna")
                        }
                        Button(manualEntry ? "Escanear" : "Escribir") { manualEntry.toggle() }
                    }
                }
            }
        }
    }

    private var manualForm: some View {
        Form {
            if !scannerAvailable {
                Section {
                    if cameraDenied {
                        Label("NutriClone no tiene permiso para usar la cámara.", systemImage: "camera.badge.ellipsis")
                        Button("Abrir Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else {
                        Label("El lector de códigos necesita la cámara de un iPhone. Aquí puedes escribir el número que aparece bajo las barras.",
                              systemImage: "barcode.viewfinder")
                            .font(.subheadline)
                    }
                }
            }
            Section {
                TextField("Ej. 8480000610218", text: $manualCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                Button("Buscar producto") {
                    if let code = Barcode.normalize(manualCode) { finish(with: code) }
                }
                .disabled(Barcode.normalize(manualCode) == nil)
            } header: {
                Text("Número del código")
            } footer: {
                if !manualCode.isEmpty && Barcode.normalize(manualCode) == nil {
                    Text("Revisa el número: debe tener 8, 12 o 13 cifras y el último dígito de control no cuadra.")
                        .foregroundStyle(Color.over)
                }
            }
        }
    }

    private func finish(with code: String) {
        onCode(code)
        dismiss()
    }
}

/// Envoltorio de DataScannerViewController que se para en el primer código válido.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let torchOn: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        // startScanning falla si la vista aún no está en pantalla: se lanza en el siguiente ciclo.
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning && !context.coordinator.didFinish {
            try? scanner.startScanning()
        }
        context.coordinator.setTorch(torchOn)
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        coordinator.setTorch(false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var didFinish = false
        private let feedback = UINotificationFeedbackGenerator()

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item], scanner: dataScanner)
        }

        private func handle(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !didFinish else { return }
            for item in items {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue else { continue }
                let isUPCE = barcode.observation.symbology == .upce
                guard let code = Barcode.normalize(payload, isUPCE: isUPCE) else { continue }
                didFinish = true
                scanner.stopScanning()
                feedback.notificationOccurred(.success)
                onCode(code)
                return
            }
        }

        func setTorch(_ on: Bool) {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch,
                  device.torchMode != (on ? .on : .off) else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }
}
